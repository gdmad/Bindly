import Foundation

/// Downloads, verifies and unpacks the two pieces into `LocalServerLayout`, and removes them again.
/// Every step happens in the staging folder; the live folders are swapped only once everything is
/// ready, so a failed or cancelled install leaves the previous state untouched.
struct LocalServerInstaller {
    struct Components: OptionSet {
        let rawValue: Int
        static let jre = Components(rawValue: 1)
        static let languageTool = Components(rawValue: 2)
        static let all: Components = [.jre, .languageTool]
    }

    typealias Progress = @Sendable (_ fraction: Double, _ step: String) -> Void

    let layout: LocalServerLayout
    var architecture: LocalServerRelease.Architecture = .current

    // MARK: - Versions

    /// What the publishers offer now: one metadata request and one HEAD, nothing is downloaded.
    func remoteVersions() async throws -> RemoteVersions {
        async let jre = fetchJREAsset()
        async let stamp = fetchLanguageToolStamp()
        return try await RemoteVersions(jreRelease: jre.releaseName, languageToolStamp: stamp)
    }

    private func fetchJREAsset() async throws -> LocalServerRelease.JREAsset {
        let (data, response) = try await URLSession.shared.data(from: LocalServerRelease.jreMetadataURL(architecture: architecture))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw LocalServerError.badResponse(http.statusCode) }
        return try LocalServerRelease.parseJREAsset(data)
    }

    private func fetchLanguageToolStamp() async throws -> String {
        var request = URLRequest(url: LocalServerRelease.languageToolURL)
        request.httpMethod = "HEAD"
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else { throw LocalServerError.badResponse(http.statusCode) }
        return LocalServerRelease.languageToolStamp(http)
    }

    // MARK: - Install / update

    /// Installs (or replaces) `parts`. `existing` supplies the parts that stay as they are.
    /// The server must not be running: its files are moved.
    func install(_ parts: Components, existing: LocalServerManifest?, progress: @escaping Progress) async throws -> LocalServerManifest {
        let fm = FileManager.default
        try? fm.removeItem(at: layout.stagingDir)
        try fm.createDirectory(at: layout.stagingDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: layout.stagingDir) }

        // The Java runtime is small next to LanguageTool, so it takes a small share of the bar.
        let weights: [(Components, Double)] = [(.jre, 0.15), (.languageTool, 0.85)].filter { parts.contains($0.0) }
        let total = weights.reduce(0) { $0 + $1.1 }
        var start = 0.0
        var jreRelease = existing?.jreRelease ?? ""
        var ltVersion = existing?.languageToolVersion ?? ""
        var ltStamp = existing?.languageToolStamp ?? ""
        var prepared: [(dir: URL, target: URL)] = []

        for (part, weight) in weights {
            let slice = weight / total
            let range = (start, start + slice)
            start += slice
            if part == .jre {
                let asset = try await prepareJRE(range: range, progress: progress)
                jreRelease = asset.release
                prepared.append((asset.dir, layout.jreDir))
            } else {
                let result = try await prepareLanguageTool(range: range, progress: progress)
                ltVersion = result.version
                ltStamp = result.stamp
                prepared.append((result.dir, layout.serverDir))
            }
        }

        try Task.checkCancellation()
        progress(0.99, "Finishing")
        try swap(prepared)

        let manifest = LocalServerManifest(jreRelease: jreRelease, languageToolVersion: ltVersion,
                                           languageToolStamp: ltStamp, installedAt: existing?.installedAt ?? Date(),
                                           lastUpdateCheck: Date())
        try write(manifest)
        return manifest
    }

    func write(_ manifest: LocalServerManifest) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: layout.manifestFile, options: .atomic)
    }

    func readManifest() -> LocalServerManifest? {
        guard let data = try? Data(contentsOf: layout.manifestFile) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LocalServerManifest.self, from: data)
    }

    /// Removes everything the installer ever put on disk: the whole folder.
    func remove() throws {
        guard FileManager.default.fileExists(atPath: layout.root.path) else { return }
        try FileManager.default.removeItem(at: layout.root)
    }

    // MARK: - Pieces

    private func prepareJRE(range: (Double, Double), progress: @escaping Progress) async throws -> (dir: URL, release: String) {
        progress(range.0, "Looking up the Java runtime")
        let asset = try await fetchJREAsset()
        let archive = layout.stagingDir.appendingPathComponent("jre.tar.gz")
        let downloadEnd = range.0 + (range.1 - range.0) * 0.85
        _ = try await FileDownloader.download(asset.url, to: archive, expectedSize: asset.size) { fraction in
            progress(range.0 + (downloadEnd - range.0) * fraction, "Downloading the Java runtime")
        }
        progress(downloadEnd, "Verifying the Java runtime")
        guard try LocalServerRelease.sha256Hex(of: archive) == asset.sha256 else { throw LocalServerError.checksumMismatch }
        try Task.checkCancellation()

        progress(downloadEnd, "Unpacking the Java runtime")
        let unpacked = layout.stagingDir.appendingPathComponent("jre-x", isDirectory: true)
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        try await CommandRunner.run("/usr/bin/tar", ["-xzf", archive.path, "-C", unpacked.path])
        try? FileManager.default.removeItem(at: archive)
        guard let dir = LocalServerLayout.singleTopLevelDirectory(in: unpacked),
              FileManager.default.fileExists(atPath: dir.appendingPathComponent("Contents/Home/bin/java").path)
        else { throw LocalServerError.unexpectedArchive("Java runtime") }
        try await clearQuarantine(dir)
        progress(range.1, "Java runtime ready")
        return (dir, asset.releaseName)
    }

    private func prepareLanguageTool(range: (Double, Double), progress: @escaping Progress)
        async throws -> (dir: URL, version: String, stamp: String) {
        let archive = layout.stagingDir.appendingPathComponent("languagetool.zip")
        let downloadEnd = range.0 + (range.1 - range.0) * 0.92
        let response = try await FileDownloader.download(LocalServerRelease.languageToolURL, to: archive) { fraction in
            progress(range.0 + (downloadEnd - range.0) * fraction, "Downloading LanguageTool")
        }
        try Task.checkCancellation()

        progress(downloadEnd, "Unpacking LanguageTool")
        let unpacked = layout.stagingDir.appendingPathComponent("server-x", isDirectory: true)
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        try await CommandRunner.run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])
        try? FileManager.default.removeItem(at: archive)
        guard let dir = LocalServerLayout.singleTopLevelDirectory(in: unpacked),
              FileManager.default.fileExists(atPath: dir.appendingPathComponent("languagetool-server.jar").path)
        else { throw LocalServerError.unexpectedArchive("LanguageTool") }
        try await clearQuarantine(dir)
        progress(range.1, "LanguageTool ready")
        return (dir, dir.lastPathComponent.replacingOccurrences(of: "LanguageTool-", with: ""),
                LocalServerRelease.languageToolStamp(response))
    }

    /// Downloads made by `URLSession` are not quarantined, so this is a safeguard, not a requirement.
    private func clearQuarantine(_ dir: URL) async throws {
        _ = try? await CommandRunner.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", dir.path])
    }

    /// Moves each prepared folder into place, parking the one it replaces; if any step fails, the
    /// parked folders go back.
    private func swap(_ prepared: [(dir: URL, target: URL)]) throws {
        let fm = FileManager.default
        var parked: [(old: URL, target: URL)] = []
        var placed: [URL] = []
        do {
            for (index, item) in prepared.enumerated() {
                if fm.fileExists(atPath: item.target.path) {
                    let old = layout.stagingDir.appendingPathComponent("old-\(index)")
                    try fm.moveItem(at: item.target, to: old)
                    parked.append((old, item.target))
                }
                try fm.moveItem(at: item.dir, to: item.target)
                placed.append(item.target)
            }
        } catch {
            for target in placed { try? fm.removeItem(at: target) }
            for entry in parked { try? fm.moveItem(at: entry.old, to: entry.target) }
            throw error
        }
    }
}
