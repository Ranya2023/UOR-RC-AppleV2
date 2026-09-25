import Foundation
import Network

/// The Mac side of the connection: shouts a beacon, checks the phone's PIN proof,
/// then connects to the phone. Same protocol as UOR-RC on Windows, so the same
/// Android app connects to a Mac without any change.
final class HostLink {
    /// The Mac listens for answers on this port and sends its beacons from it,
    /// so the phone's answer always comes back to us.
    private static let replyPort: UInt16 = 47800

    private let settings: HostSettings
    private var udp: UdpSocket?
    private var phone: NWConnection?
    private let lines = LineBuffer()
    private var nonces: [String] = []
    private let lock = NSLock()
    private var timer: Timer?
    private var connecting = false

    var onLine: (([String: Any]) -> Void)?
    var onConnected: ((Bool, String) -> Void)?
    var onLog: ((String) -> Void)?
    private(set) var isConnected = false
    private(set) var peer = ""

    init(settings: HostSettings) { self.settings = settings }

    func start() {
        udp = UdpSocket(port: HostLink.replyPort, broadcast: true) ?? UdpSocket(port: 0, broadcast: true)
        udp?.onPacket = { [weak self] data, ip, port in self?.onPacket(data, from: ip, port: port) }
        udp?.listen()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.sendBeacon() }
        onLog?("Looking for the phone on " + Net.addresses().joined(separator: ", "))
    }

    func stop() {
        timer?.invalidate(); timer = nil
        udp?.stop(); udp = nil
        phone?.cancel(); phone = nil
        isConnected = false
    }

    // ── 1 · beacon ─────────────────────────────────────────────────────
    private func sendBeacon() {
        guard !isConnected, !connecting, let udp else { return }
        let n = Wire.nonce()
        lock.lock(); nonces.insert(n, at: 0); if nonces.count > 12 { nonces.removeLast() }; lock.unlock()
        let payload: [String: Any] = [
            "remco": 1, "type": "beacon", "id": settings.id,
            "name": Host.current().localizedName ?? "Mac",
            "bt": "", "nonce": n, "connected": false
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        for address in Net.broadcastAddresses() { udp.send(data, to: address, port: Wire.beaconPort) }
    }

    // ── 2 · the phone answers on the same socket ───────────────────────
    private func onPacket(_ data: Data, from ip: String, port: UInt16) {
        guard let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              m.str("type") == "reply", m.str("id") == settings.id,
              !isConnected, !connecting else { return }
        let given = m.str("proof")
        lock.lock(); let ok = nonces.contains { Wire.proof(pin: settings.pin, nonce: $0) == given }; lock.unlock()
        guard ok else { return }
        connecting = true
        let phonePort = m.int("port") == 0 ? Wire.phonePort : UInt16(m.int("port"))
        connect(to: ip, port: phonePort, phoneName: m.str("phone"), phoneNonce: m.str("pnonce"))
    }

    // ── 3 · the Mac connects to the phone ──────────────────────────────
    private func connect(to ip: String, port: UInt16, phoneName: String, phoneNonce: String) {
        guard let p = NWEndpoint.Port(rawValue: port) else { connecting = false; return }
        let conn = NWConnection(host: NWEndpoint.Host(ip), port: p, using: .tcp)
        phone = conn
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.connecting = false
                self.isConnected = true
                self.peer = phoneName.isEmpty ? "phone" : phoneName
                self.sendNow(["e": "pc_hello", "id": self.settings.id,
                              "name": Host.current().localizedName ?? "Mac", "bt": "",
                              "proof": Wire.proof(pin: self.settings.pin, nonce: phoneNonce)])
                DispatchQueue.main.async { self.onConnected?(true, self.peer) }
                self.receive()
            case .failed, .cancelled:
                self.connecting = false
                if self.isConnected {
                    self.isConnected = false
                    DispatchQueue.main.async { self.onConnected?(false, self.peer) }
                }
            default:
                break
            }
        }
        conn.start(queue: .global())
    }

    private func receive() {
        phone?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, _ in
            guard let self else { return }
            if let data, !data.isEmpty {
                for line in self.lines.push(data) {
                    if let m = Wire.decode(line) { DispatchQueue.main.async { self.onLine?(m) } }
                }
            }
            if done {
                self.isConnected = false
                DispatchQueue.main.async { self.onConnected?(false, self.peer) }
                return
            }
            self.receive()
        }
    }

    func send(_ object: [String: Any]) {
        guard isConnected else { return }
        sendNow(object)
    }

    private func sendNow(_ object: [String: Any]) {
        guard let data = Wire.encode(object), let conn = phone else { return }
        conn.send(content: data, completion: .contentProcessed { _ in })
    }

    static func addresses() -> [String] { Net.addresses() }
}

/// PIN and identity, kept in the Mac's own settings.
final class HostSettings {
    let id: String
    var pin: String

    init() {
        let d = UserDefaults.standard
        let savedId = d.string(forKey: "uorrc.id")
            ?? String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))
        let savedPin = d.string(forKey: "uorrc.pin") ?? String(format: "%04d", Int.random(in: 1000...9999))
        id = savedId
        pin = savedPin
        d.set(savedId, forKey: "uorrc.id")
        d.set(savedPin, forKey: "uorrc.pin")
    }

    func newPin() {
        pin = String(format: "%04d", Int.random(in: 1000...9999))
        UserDefaults.standard.set(pin, forKey: "uorrc.pin")
    }
}
