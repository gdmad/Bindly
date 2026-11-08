import Foundation
import Darwin

/// Port choice for the local server. The port is a setting; when it is taken the server moves to the
/// next free one and the user is told, rather than failing to start.
enum LocalServerPort {
    static let defaultPort = 8081
    static let allowed = 1024...65535

    /// `preferred` if it is free, otherwise the first free port above it. Nil when none is found
    /// within `attempts` ports (or `preferred` is not a usable port at all).
    static func pick(preferred: Int, attempts: Int = 50, isFree: (Int) -> Bool) -> Int? {
        guard allowed.contains(preferred) else { return nil }
        for port in preferred..<min(preferred + attempts, allowed.upperBound + 1) where isFree(port) {
            return port
        }
        return nil
    }

    /// Whether nothing is listening on `port` of the loopback interface, which is the only address
    /// the server binds to.
    static func isFree(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
