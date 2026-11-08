import Foundation

/// What is installed, written next to the files (`install.json`). Its presence is what marks an
/// installation as complete.
struct LocalServerManifest: Codable, Equatable {
    var jreRelease: String
    var languageToolVersion: String
    /// `LocalServerRelease.languageToolStamp` of the archive that was installed.
    var languageToolStamp: String
    var installedAt: Date
    var lastUpdateCheck: Date?
    /// The outcome of the last check, kept so "update available" survives a restart.
    var available: LocalServerUpdates?

    func newer(than remote: RemoteVersions) -> LocalServerUpdates {
        LocalServerUpdates(jre: remote.jreRelease != jreRelease,
                           languageTool: remote.languageToolStamp != languageToolStamp)
    }

    /// Passive checks (when the settings block opens) run at most once a week.
    static let checkInterval: TimeInterval = 7 * 24 * 3600

    func isCheckDue(now: Date = Date()) -> Bool {
        guard let last = lastUpdateCheck else { return true }
        return now.timeIntervalSince(last) >= Self.checkInterval
    }
}

/// What the publishers currently offer.
struct RemoteVersions: Equatable {
    let jreRelease: String
    let languageToolStamp: String
}

/// Which installed pieces have a newer release. They update independently of each other.
struct LocalServerUpdates: Codable, Equatable {
    var jre: Bool
    var languageTool: Bool
    var any: Bool { jre || languageTool }
}
