import Foundation

/// Where the portable server lives. Everything sits under one folder, so deleting it removes every
/// trace and nothing is installed into the system.
struct LocalServerLayout: Equatable {
    let root: URL

    /// `~/Library/Application Support/Bindly/LanguageTool` -- the test build's own folder for it, so a
    /// test install never touches the real one.
    static var standard: LocalServerLayout {
        LocalServerLayout(root: AppPaths.supportDirectory.appendingPathComponent("LanguageTool", isDirectory: true))
    }

    var jreDir: URL { root.appendingPathComponent("jre", isDirectory: true) }
    var serverDir: URL { root.appendingPathComponent("server", isDirectory: true) }
    var javaExecutable: URL { jreDir.appendingPathComponent("Contents/Home/bin/java") }
    var serverJar: URL { serverDir.appendingPathComponent("languagetool-server.jar") }
    var logFile: URL { root.appendingPathComponent("server.log") }
    var pidFile: URL { root.appendingPathComponent("server.pid") }
    var manifestFile: URL { root.appendingPathComponent("install.json") }
    /// Downloads and unpacked archives are prepared here and moved into place only when complete.
    var stagingDir: URL { root.appendingPathComponent(".staging", isDirectory: true) }

    /// Installed means a manifest and both runnable pieces, not merely a folder.
    func isInstalled(fileManager: FileManager = .default) -> Bool {
        [manifestFile, javaExecutable, serverJar].allSatisfy { fileManager.fileExists(atPath: $0.path) }
    }

    /// The archives unpack into a single versioned folder (`LanguageTool-6.6`,
    /// `jdk-21.0.12.1+1-jre`); this finds it so it can be moved to a fixed name.
    static func singleTopLevelDirectory(in dir: URL, fileManager: FileManager = .default) -> URL? {
        let items = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                          options: [.skipsHiddenFiles])) ?? []
        let dirs = items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        return dirs.count == 1 ? dirs[0] : nil
    }

    /// Total size on disk of the installation, in bytes.
    func diskUsage(fileManager: FileManager = .default) -> Int64 {
        guard let walker = fileManager.enumerator(at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in walker {
            total += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }
}
