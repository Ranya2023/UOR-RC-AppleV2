import Foundation

/// A tiny UDP helper built on plain BSD sockets — the same code on macOS and iOS.
/// Plain sockets keep the beacon/answer exchange predictable: we send from the very
/// socket we listen on, so the phone's answer comes back to us.
public final class UdpSocket {
    private var fd: Int32 = -1
    private var running = false
    public var onPacket: ((Data, String, UInt16) -> Void)?

    /// port 0 = any free port
    public init?(port: UInt16, broadcast: Bool) {
        fd = socket(AF_INET, SOCK_DGRAM, 0)
        if fd < 0 { return nil }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
        if broadcast { setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size)) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &addr) { raw in
            raw.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bound != 0 { close(fd); fd = -1; return nil }
    }

    /// Starts receiving in the background; every packet goes to `onPacket`.
    public func listen() {
        guard fd >= 0, !running else { return }
        running = true
        let handle = fd
        Thread {
            var buffer = [UInt8](repeating: 0, count: 4096)
            while self.running {
                var from = sockaddr_in()
                var len = socklen_t(MemoryLayout<sockaddr_in>.size)
                let n = withUnsafeMutablePointer(to: &from) { raw in
                    raw.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        recvfrom(handle, &buffer, buffer.count, 0, sa, &len)
                    }
                }
                if n <= 0 { if self.running { usleep(200_000) }; continue }
                let data = Data(buffer[0..<n])
                let ip = String(cString: inet_ntoa(from.sin_addr))
                let port = UInt16(bigEndian: from.sin_port)
                self.onPacket?(data, ip, port)
            }
        }.start()
    }

    public func send(_ data: Data, to host: String, port: UInt16) {
        guard fd >= 0 else { return }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr(host)
        _ = data.withUnsafeBytes { bytes in
            withUnsafePointer(to: &addr) { raw in
                raw.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, bytes.baseAddress, data.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    public func stop() {
        running = false
        if fd >= 0 { close(fd); fd = -1 }
    }

    deinit { stop() }
}

/// This device's IPv4 addresses and their broadcast addresses.
public enum Net {
    public static func interfaces() -> [(ip: String, broadcast: String)] {
        var result: [(String, String)] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return result }
        defer { freeifaddrs(head) }
        var ptr = head
        while let p = ptr {
            let f = p.pointee
            if let sa = f.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
               (f.ifa_flags & UInt32(IFF_UP)) != 0, (f.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                let ip = String(cString: host)
                var bcast = ""
                if let b = f.ifa_dstaddr {
                    var bh = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(b, socklen_t(b.pointee.sa_len), &bh, socklen_t(bh.count), nil, 0, NI_NUMERICHOST)
                    bcast = String(cString: bh)
                }
                if !ip.isEmpty { result.append((ip, bcast)) }
            }
            ptr = f.ifa_next
        }
        return result
    }

    public static func addresses() -> [String] { interfaces().map { $0.ip } }

    public static func broadcastAddresses() -> [String] {
        var list = ["255.255.255.255"]
        for i in interfaces() where !i.broadcast.isEmpty { list.append(i.broadcast) }
        return Array(Set(list))
    }
}
