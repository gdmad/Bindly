import Foundation

/// Where BindAll keeps its files. The end-to-end test build (`com.evgeny.bindall.e2e`) gets a folder
/// of its own, so a test run never touches the learned words, history or usage data of the real app.
enum AppPaths {
    static let e2eBundleID = "com.evgeny.bindall.e2e"

    static var isE2EBuild: Bool { Bundle.main.bundleIdentifier == e2eBundleID }

    /// `~/Library/Application Support/BindAll` (or `BindAll E2E` for the test build), created on demand.
    static var supportDirectory: URL {
        let dir = URL.applicationSupportDirectory.appending(path: isE2EBuild ? "BindAll E2E" : "BindAll",
                                                            directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
