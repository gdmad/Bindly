import Foundation
import CryptoKit

/// Where the two pieces come from. Nothing is bundled with the app: the user downloads them on
/// request, straight from their publishers.
enum LocalServerRelease {
    /// LanguageTool ships a rolling "stable" archive; its version is read from the folder inside.
    static let languageToolURL = URL(string: "https://languagetool.org/download/LanguageTool-stable.zip")!

    /// Temurin 21 (LTS): LanguageTool 6.x needs Java 17 or newer.
    static let javaFeatureVersion = 21

    enum Architecture: String {
        case arm64 = "aarch64"
        case x64

        static var current: Architecture {
            #if arch(arm64)
            return .arm64
            #else
            return .x64
            #endif
        }
    }

    /// Adoptium's metadata for the newest JRE of the pinned Java version.
    static func jreMetadataURL(architecture: Architecture) -> URL {
        URL(string: "https://api.adoptium.net/v3/assets/latest/\(javaFeatureVersion)/hotspot"
            + "?architecture=\(architecture.rawValue)&image_type=jre&os=mac&vendor=eclipse")!
    }

    struct JREAsset: Equatable {
        let releaseName: String
        let url: URL
        let sha256: String
        let size: Int64
    }

    enum ParseError: Error { case noAsset }

    static func parseJREAsset(_ data: Data) throws -> JREAsset {
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = list.first,
              let name = first["release_name"] as? String,
              let binary = first["binary"] as? [String: Any],
              let package = binary["package"] as? [String: Any],
              let link = (package["link"] as? String).flatMap(URL.init(string:)),
              let checksum = package["checksum"] as? String else { throw ParseError.noAsset }
        let size = (package["size"] as? NSNumber)?.int64Value ?? 0
        return JREAsset(releaseName: name, url: link, sha256: checksum.lowercased(), size: size)
    }

    /// Identifies a published LanguageTool archive without downloading it. `Last-Modified` and the
    /// length are stable across the CDN's nodes, the `ETag` is only the fallback.
    static func languageToolStamp(_ response: HTTPURLResponse) -> String {
        let length = response.value(forHTTPHeaderField: "Content-Length") ?? ""
        if let modified = response.value(forHTTPHeaderField: "Last-Modified") { return "\(modified)|\(length)" }
        return "\(response.value(forHTTPHeaderField: "ETag") ?? "")|\(length)"
    }

    /// Streams the file through SHA-256, so the 48 MB archive is never held in memory.
    static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
