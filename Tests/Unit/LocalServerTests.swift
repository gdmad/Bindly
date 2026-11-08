import Foundation

func runLocalServerTests() {
    print("LocalServer settings")
    var target = Settings()
    target.languageToolMode = .selfHosted
    target.languageToolBaseURL = "http://my-server:8010/v2"
    check(target.languageToolConnection(token: "").baseURL == "http://my-server:8010/v2", "custom target uses the user's URL")
    target.languageToolTarget = .local
    target.localServerPort = 8123
    eq(target.languageToolConnection(token: "").baseURL, "http://127.0.0.1:8123/v2", "local target uses the loopback port")
    eq(target.languageToolBaseURL, "http://my-server:8010/v2", "the user's URL is kept while the local server is used")
    check(target.languageToolConnection(token: "tok").apiKey.isEmpty, "the local server never gets credentials")
    target.languageToolMode = .free
    check(!target.usesLocalServer, "the local server is used only in self-hosted mode")
    var removed = Settings()
    removed.languageToolMode = .selfHosted
    removed.languageToolTarget = .local
    removed.languageToolBaseURL = "http://my-server:8010/v2"
    removed.localServerRemoved()
    check(removed.languageToolTarget == .custom && removed.languageToolMode == .selfHosted,
          "removal falls back to the user's own server")
    removed.languageToolTarget = .local
    removed.languageToolBaseURL = "https://api.languagetool.org/v2"
    removed.localServerRemoved()
    check(removed.languageToolTarget == .custom && removed.languageToolMode == .free,
          "removal falls back to the public server when there is no own URL")
    var legacy = try! JSONDecoder().decode(Settings.self, from: Data("{\"languageToolMode\":\"selfHosted\"}".utf8))
    check(legacy.languageToolTarget == .custom && legacy.localServerPort == LocalServerPort.defaultPort,
          "settings saved before the local server decode with the custom target")
    legacy.localServerPort = 9000
    let roundTrip = try! JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(legacy))
    check(roundTrip.localServerPort == 9000, "the port survives a save")
    
    print("LocalServerPort")
    check(LocalServerPort.pick(preferred: 8081, isFree: { _ in true }) == 8081, "a free port is kept")
    check(LocalServerPort.pick(preferred: 8081, isFree: { $0 >= 8083 }) == 8083, "a busy port moves to the next free one")
    check(LocalServerPort.pick(preferred: 8081, attempts: 3, isFree: { _ in false }) == nil, "no free port gives nil")
    check(LocalServerPort.pick(preferred: 80, isFree: { _ in true }) == nil, "a privileged port is refused")
    check(LocalServerPort.pick(preferred: 65535, isFree: { $0 == 65535 }) == 65535, "the top port is usable")
    check(LocalServerPort.pick(preferred: 65535, isFree: { _ in false }) == nil, "the search stops at the top port")
    let probe = socket(AF_INET, SOCK_STREAM, 0)
    var probeAddr = sockaddr_in()
    probeAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    probeAddr.sin_family = sa_family_t(AF_INET)
    probeAddr.sin_port = 0
    probeAddr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    _ = withUnsafePointer(to: &probeAddr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(probe, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    listen(probe, 1)
    var probeLen = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &probeAddr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(probe, $0, &probeLen) } }
    let busyPort = Int(UInt16(bigEndian: probeAddr.sin_port))
    check(!LocalServerPort.isFree(busyPort), "a port with a listener is reported busy")
    close(probe)
    check(LocalServerPort.isFree(busyPort), "the port is free again once the listener is gone")
    
    print("LocalServerRelease")
    let adoptium = """
    [{"release_name":"jdk-21.0.12.1+1","binary":{"package":{"link":"https://example.com/jre.tar.gz",
    "checksum":"ABCDEF0123","size":48144965,"name":"jre.tar.gz"}}}]
    """.data(using: .utf8)!
    let asset = try! LocalServerRelease.parseJREAsset(adoptium)
    check(asset.releaseName == "jdk-21.0.12.1+1" && asset.url.absoluteString == "https://example.com/jre.tar.gz",
          "Adoptium metadata gives the release and the link")
    eq(asset.sha256, "abcdef0123", "the checksum is lower-cased")
    check(asset.size == 48144965, "the size is read")
    check((try? LocalServerRelease.parseJREAsset(Data("[]".utf8))) == nil, "an empty metadata list is an error")
    let armURL = LocalServerRelease.jreMetadataURL(architecture: .arm64).absoluteString
    check(armURL.contains("architecture=aarch64") && armURL.contains("image_type=jre") && armURL.contains("/21/"),
          "the arm64 query asks for the Java 21 JRE")
    check(LocalServerRelease.jreMetadataURL(architecture: .x64).absoluteString.contains("architecture=x64"),
          "the x64 query asks for x64")
    let digestFile = FileManager.default.temporaryDirectory.appendingPathComponent("bindall-digest-\(UUID().uuidString)")
    try! Data("abc".utf8).write(to: digestFile)
    eq(try! LocalServerRelease.sha256Hex(of: digestFile),
       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256 of a file")
    try? FileManager.default.removeItem(at: digestFile)
    func stampResponse(_ headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://x")!, statusCode: 200, httpVersion: nil, headerFields: headers)!
    }
    eq(LocalServerRelease.languageToolStamp(stampResponse(["Last-Modified": "Thu, 27 Mar 2025", "Content-Length": "10", "ETag": "\"a\""])),
       "Thu, 27 Mar 2025|10", "the stamp prefers Last-Modified over the ETag")
    eq(LocalServerRelease.languageToolStamp(stampResponse(["ETag": "\"a\"", "Content-Length": "10"])),
       "\"a\"|10", "the stamp falls back to the ETag")
    
    print("LocalServerManifest")
    let installedAt = Date(timeIntervalSince1970: 1_000_000)
    var manifest = LocalServerManifest(jreRelease: "jdk-21.0.12.1+1", languageToolVersion: "6.6",
                                       languageToolStamp: "stamp-1", installedAt: installedAt)
    let same = manifest.newer(than: RemoteVersions(jreRelease: "jdk-21.0.12.1+1", languageToolStamp: "stamp-1"))
    check(!same.any, "identical versions need no update")
    let newJRE = manifest.newer(than: RemoteVersions(jreRelease: "jdk-21.0.13+1", languageToolStamp: "stamp-1"))
    check(newJRE.jre && !newJRE.languageTool, "a newer JRE is flagged alone")
    let newLT = manifest.newer(than: RemoteVersions(jreRelease: "jdk-21.0.12.1+1", languageToolStamp: "stamp-2"))
    check(!newLT.jre && newLT.languageTool, "a newer LanguageTool is flagged alone")
    check(manifest.isCheckDue(now: installedAt), "a never-checked install is due")
    manifest.lastUpdateCheck = installedAt
    check(!manifest.isCheckDue(now: installedAt.addingTimeInterval(6 * 24 * 3600)), "a check within a week is not due")
    check(manifest.isCheckDue(now: installedAt.addingTimeInterval(7 * 24 * 3600)), "a week later it is due")
    manifest.available = newLT
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    check((try? decoder.decode(LocalServerManifest.self, from: encoder.encode(manifest))) == manifest,
          "the manifest survives a round trip, pending update included")
    
    print("LocalServerLayout")
    let tmpRoot = FileManager.default.temporaryDirectory.appendingPathComponent("bindall-layout-\(UUID().uuidString)")
    let layout = LocalServerLayout(root: tmpRoot)
    check(!layout.isInstalled(), "an empty folder is not an installation")
    eq(layout.javaExecutable.path, tmpRoot.path + "/jre/Contents/Home/bin/java", "java lives under the JRE folder")
    try! FileManager.default.createDirectory(at: layout.javaExecutable.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: layout.javaExecutable.path, contents: Data())
    try! FileManager.default.createDirectory(at: layout.serverDir, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: layout.serverJar.path, contents: Data("jar".utf8))
    check(!layout.isInstalled(), "the pieces without a manifest are not a complete installation")
    FileManager.default.createFile(atPath: layout.manifestFile.path, contents: Data("{}".utf8))
    check(layout.isInstalled(), "manifest plus java plus the jar is an installation")
    check(layout.diskUsage() > 0, "disk usage counts the files")
    let nested = tmpRoot.appendingPathComponent("unpacked/LanguageTool-6.6", isDirectory: true)
    try! FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    check(LocalServerLayout.singleTopLevelDirectory(in: tmpRoot.appendingPathComponent("unpacked"))?.lastPathComponent == "LanguageTool-6.6",
          "the single versioned folder inside an archive is found")
    try! FileManager.default.createDirectory(at: tmpRoot.appendingPathComponent("unpacked/other"), withIntermediateDirectories: true)
    check(LocalServerLayout.singleTopLevelDirectory(in: tmpRoot.appendingPathComponent("unpacked")) == nil,
          "two top-level folders are not a valid archive")
    try? FileManager.default.removeItem(at: tmpRoot)
    
}
