import Foundation
import AppKit

/// Receives an iPhone's screen. Apple runs iPhone screen sharing in a separate
/// little program that cannot use the app's own connection, so it connects here
/// instead — one picture per line, and only with the token the phone gave us.
final class PhoneScreenServer {
    static let port: UInt16 = 47803
    private var fd: Int32 = -1
    private var running = false
    private var token = ""
    var onFrame: ((NSImage) -> Void)?
    var onStreaming: ((Bool) -> Void)?
    var onLog: ((String) -> Void)?

    func setToken(_ t: String) {
        token = t
        start()
    }

    private func start() {
        guard !running, !token.isEmpty else { return }
        let s = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard s >= 0 else { return }
        var yes: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = PhoneScreenServer.port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &addr) { raw in
            raw.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, Darwin.listen(s, 4) == 0 else { Darwin.close(s); return }
        fd = s
        running = true
        Thread { [weak self] in
            while let self, self.running {
                let client = Darwin.accept(s, nil, nil)
                if client < 0 { if self.running { usleep(200_000) }; continue }
                Thread { self.serve(client) }.start()
            }
        }.start()
    }

    private func serve(_ client: Int32) {
        defer { Darwin.close(client) }
        var buffer = Data()
        var started = false
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        func nextLine() -> String? {
            while true {
                if let i = buffer.firstIndex(of: 0x0A) {
                    let line = buffer.subdata(in: buffer.startIndex..<i)
                    buffer.removeSubrange(buffer.startIndex...i)
                    return String(data: line, encoding: .utf8)
                }
                let n = Darwin.recv(client, &chunk, chunk.count, 0)
                if n <= 0 { return nil }
                buffer.append(contentsOf: chunk[0..<n])
                if buffer.count > 32_000_000 { return nil }
            }
        }
        guard let hello = nextLine(),
              let m = Wire.decode(hello), m.str("token") == token, !token.isEmpty else {
            DispatchQueue.main.async { self.onLog?("A phone screen connection was refused (wrong token).") }
            return
        }
        started = true
        DispatchQueue.main.async { self.onStreaming?(true); self.onLog?("📱 The phone's screen is now showing.") }
        while let line = nextLine() {
            guard let m = Wire.decode(line), let data = Data(base64Encoded: m.str("img")),
                  let image = NSImage(data: data) else { continue }
            DispatchQueue.main.async { self.onFrame?(image) }
            _ = "{\"t\":\"ack\"}\n".withCString { Darwin.send(client, $0, strlen($0), 0) }   // one picture at a time
        }
        if started { DispatchQueue.main.async { self.onStreaming?(false); self.onLog?("📱 The phone's screen stopped.") } }
    }

    func stop() { running = false; if fd >= 0 { Darwin.close(fd); fd = -1 } }
}
