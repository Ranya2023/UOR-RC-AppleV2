import Foundation
import Network
import UIKit

/// The iPhone side: hears the computer's beacon, answers with proof of the PIN,
/// then accepts the computer's connection. Works with UOR-RC on Windows *and* on Mac.
final class Link: ObservableObject {
    @Published var connected = false
    @Published var computerName = ""
    @Published var found: [String: Beacon] = [:]       // computers seen on this Wi-Fi
    @Published var slide = 0
    @Published var total = 0
    @Published var notes = ""
    @Published var presenting = false
    @Published var slideAspect: CGFloat = 16.0 / 9.0
    @Published var view = ""          // "", board, doc, media, picker
    @Published var page = 0
    @Published var pages = 0
    @Published var boardBg = "white"
    @Published var picked = ""
    @Published var fileStatus = ""
    @Published var quizOptions = 4
    @Published var quizCorrect = -1
    @Published var quizReveal = false
    @Published var quizTotal = 0
    @Published var quizPlayers = 0
    @Published var quizLeft = -1
    @Published var quizTop: [(name: String, score: Int)] = []
    var runQuiz: SavedQuiz?
    var runIndex = 0
    var onAck: (() -> Void)?
    @Published var slideImage: UIImage?        // picture of what is on the projector
    @Published var mirrorImage: UIImage?       // 📺 the computer's screen
    @Published var mirrorOn = false
    @Published var timerText = ""
    @Published var receivedFile: URL?
    @Published var askText: (x: Double, y: Double)?     // 📍 the computer wants the words for a label
    @Published var slideTitles: [String] = []
    @Published var caretSeen = false
    private var timer: Timer?
    private var timerSeconds = 0
    private var timerUp = false
    private var timerShow = true
    private var incoming: (handle: FileHandle, url: URL, name: String)?

    struct Beacon: Identifiable {
        let id: String
        var name: String
        var ip: String
        var port: UInt16          // the port the computer sent it from — we answer there
        var nonce: String
        var seen = Date()
    }

    private var udp: UdpSocket?
    private var tcp: NWListener?
    private var conn: NWConnection?
    private let lines = LineBuffer()
    private let myNonce = Wire.nonce()
    private var expected: [String: String] = [:]       // computer id → the PIN we answered with
    private var ping: Timer?

    var pins: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "pins") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "pins") }
    }
    var chosen: String? {
        get { UserDefaults.standard.string(forKey: "chosenPC") }
        set { UserDefaults.standard.set(newValue, forKey: "chosenPC") }
    }

    func start() {
        udp = UdpSocket(port: Wire.beaconPort, broadcast: true)
        udp?.onPacket = { [weak self] data, ip, port in self?.onPacket(data, ip: ip, port: port) }
        udp?.listen()
        // a harmless broadcast makes iOS show its "find devices on the local network" question
        if let hello = try? JSONSerialization.data(withJSONObject: ["remco": 1, "type": "hello"]) {
            udp?.send(hello, to: "255.255.255.255", port: Wire.beaconPort)
        }
        startServer()
    }

    // ── the computer's beacon ──────────────────────────────────────────
    private func onPacket(_ data: Data, ip: String, port: UInt16) {
        guard let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              m.str("type") == "beacon" else { return }
        let id = m.str("id")
        guard !id.isEmpty else { return }
        let b = Beacon(id: id, name: m.str("name"), ip: ip, port: port, nonce: m.str("nonce"))
        DispatchQueue.main.async { self.found[id] = b }
        guard !connected, id == chosen, let pin = pins[id], !m.bool("connected") else { return }
        reply(to: b, pin: pin)
    }

    /// "Yes, it's me — here is proof I know your PIN."
    private func reply(to b: Beacon, pin: String) {
        expected[b.id] = pin
        let payload: [String: Any] = [
            "remco": 1, "type": "reply", "id": b.id, "phone": UIDevice.current.name,
            "port": Int(Wire.phonePort), "proof": Wire.proof(pin: pin, nonce: b.nonce), "pnonce": myNonce
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        udp?.send(data, to: b.ip, port: b.port)
    }

    func connect(to b: Beacon, pin: String) {
        pins[b.id] = pin
        chosen = b.id
        reply(to: b, pin: pin)
    }

    // ── the computer connects to us ────────────────────────────────────
    private func startServer() {
        do {
            guard let port = NWEndpoint.Port(rawValue: Wire.phonePort) else { return }
            let l = try NWListener(using: .tcp, on: port)
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.start(queue: .global())
            tcp = l
        } catch {
            print("server: \(error)")
        }
    }

    private func accept(_ c: NWConnection) {
        c.start(queue: .global())
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self,
                  let data,
                  let text = String(data: data, encoding: .utf8),
                  let first = text.split(separator: "\n").first.map(String.init),
                  let hello = Wire.decode(first),
                  hello.str("e") == "pc_hello",
                  let pin = self.expected[hello.str("id")],
                  hello.str("proof") == Wire.proof(pin: pin, nonce: self.myNonce)
            else { c.cancel(); return }
            self.conn = c
            DispatchQueue.main.async {
                self.connected = true
                self.computerName = hello.str("name")
                self.send(["c": "hello", "v": 2])
                // get ready for screen sharing: a private token, and where the computer is
                let token = UUID().uuidString
                let host = self.found[hello.str("id")]?.ip ?? ""
                ScreenShare.remember(host: host, token: token)
                self.send(["c": "screen_token", "token": token])
                self.ping = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                    self?.send(["c": "ping"])
                }
            }
            self.receive()
        }
    }

    private func receive() {
        conn?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, _ in
            guard let self else { return }
            if let data, !data.isEmpty {
                for line in self.lines.push(data) {
                    if let m = Wire.decode(line) { DispatchQueue.main.async { self.onMessage(m) } }
                }
            }
            if done { self.dropped(); return }
            self.receive()
        }
    }

    private func dropped() {
        DispatchQueue.main.async {
            self.connected = false
            self.ping?.invalidate(); self.ping = nil
            self.conn?.cancel(); self.conn = nil
        }
    }

    private func onMessage(_ m: [String: Any]) {
        switch m.str("e") {
        case "picked": picked = m.str("name"); return
        case "saved": fileStatus = "Whiteboard saved on the computer"; return

        case "phone_ack": onAck?(); return
        case "thumb":
            if let d = Data(base64Encoded: m.str("img")), let img = UIImage(data: d) { slideImage = img }
            return
        case "frame":
            if let d = Data(base64Encoded: m.str("img")), let img = UIImage(data: d) {
                mirrorImage = img
                send(["c": "frame_ack"])
            }
            return
        case "fs": receiveFile(m); return
        case "new_text", "edit_text":
            askText = (m.num("sx"), m.num("sy")); return
        case "slides":
            slideTitles = (m["titles"] as? [String]) ?? []; return
        case "caret":
            caretSeen = m.bool("on"); return
        case "media":
            view = m.bool("open") ? "media" : (view == "media" ? "" : view); return
        case "quiz":
            quizOptions = m.int("n"); quizCorrect = m.int("correct"); quizReveal = m.bool("reveal")
            quizTotal = m.int("total"); quizPlayers = m.int("players"); quizLeft = m.int("left")
            quizTop = ((m["top"] as? [[String: Any]]) ?? []).map { (name: $0.str("name"), score: $0.int("score")) }
            return
        case "state": break
        default: return
        }
        view = m.str("view"); page = m.int("page"); pages = m.int("pages")
        if !m.str("bg").isEmpty { boardBg = m.str("bg") }
        slide = m.int("slide")
        total = m.int("total")
        notes = m.str("notes")
        presenting = m.bool("show")
        let w = m.num("sw"), h = m.num("sh")
        if h > 0 { slideAspect = CGFloat(w / h) }
    }

    func send(_ o: [String: Any]) {
        guard let data = Wire.encode(o), let c = conn, connected else { return }
        c.send(content: data, completion: .contentProcessed { _ in })
    }

    /// Sends a photo, video or document to the computer, in chunks like the Android app.
    func sendFile(data: Data, name: String, present: Bool, kind: String, index: Int) {
        guard connected else { return }
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).description
        send(["c": "fs", "t": "start", "id": id, "name": name, "size": data.count,
              "present": present, "kind": kind, "index": index])
        DispatchQueue.global().async {
            let chunk = 48 * 1024
            var seq = 0, offset = 0
            while offset < data.count {
                let end = min(offset + chunk, data.count)
                let part = data.subdata(in: offset..<end)
                self.send(["c": "fs", "t": "chunk", "id": id, "seq": seq, "d": part.base64EncodedString()])
                offset = end; seq += 1
                usleep(6000)                    // gentle pacing, same idea as on Android
                DispatchQueue.main.async { self.fileStatus = "→ \(name) \(offset * 100 / max(1, data.count))%" }
            }
            self.send(["c": "fs", "t": "end", "id": id])
            DispatchQueue.main.async { self.fileStatus = "" }
        }
    }

    /// Sends question number [i] of the quiz being played.
    func sendQuestion(_ i: Int) {
        guard let quiz = runQuiz, i >= 0, i < quiz.questions.count else { return }
        runIndex = i
        let q = quiz.questions[i]
        send(["c": "quiz", "a": "start", "q": q.text, "opts": q.options,
              "n": max(2, q.options.count), "correct": q.correct, "secs": q.seconds,
              "qi": i + 1, "qn": quiz.questions.count])
        view = "quiz"
    }

    // ── ⌛ timer ──────────────────────────────────────────────────────
    func startTimer(minutes: Int, up: Bool, show: Bool) {
        timerUp = up; timerShow = show
        timerSeconds = up ? 0 : minutes * 60
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.timerSeconds += self.timerUp ? 1 : -1
            if !self.timerUp, self.timerSeconds <= 0 {
                self.timerSeconds = 0
                self.timer?.invalidate()
                self.send(["c": "timer_alert"])
            }
            self.pushTimer()
        }
        pushTimer()
    }
    func pauseTimer() { timer?.invalidate(); timer = nil; pushTimer(running: false) }
    func resetTimer() {
        timer?.invalidate(); timer = nil; timerSeconds = 0; timerText = ""
        send(["c": "timer", "mode": timerUp ? "up" : "down", "sec": -1, "running": false, "visible": false])
    }
    private func pushTimer(running: Bool = true) {
        timerText = String(format: "%@ %02d:%02d", timerUp ? "⏱" : "⌛", timerSeconds / 60, timerSeconds % 60)
        send(["c": "timer", "mode": timerUp ? "up" : "down", "sec": timerSeconds,
              "running": running, "visible": timerShow])
    }

    /// 📥 A file the computer is sending us — it lands in the app's Files folder.
    private func receiveFile(_ m: [String: Any]) {
        let id = m.str("id")
        switch m.str("t") {
        case "start":
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = dir.appendingPathComponent(m.str("name").isEmpty ? "file" : m.str("name"))
            FileManager.default.createFile(atPath: url.path, contents: nil)
            if let h = try? FileHandle(forWritingTo: url) {
                incoming = (h, url, m.str("name"))
                fileStatus = "← " + m.str("name")
                send(["c": "fs", "t": "ack", "id": id, "seq": -1])
            }
        case "chunk":
            if let inc = incoming, let d = Data(base64Encoded: m.str("d")) {
                inc.handle.write(d)
                send(["c": "fs", "t": "ack", "id": id, "seq": m.int("seq")])
            }
        case "end":
            if let inc = incoming {
                try? inc.handle.close()
                receivedFile = inc.url
                fileStatus = "✓ " + inc.name
                send(["c": "fs", "t": "done", "id": id, "ok": true])
                incoming = nil
            }
        default: break
        }
    }

    /// 📍 Sends the words for a text label the computer asked about.
    func saveText(_ text: String, color: String = "#facc15", size: Int = 28) {
        guard let at = askText else { return }
        send(["c": "text_save", "sx": at.x, "sy": at.y, "text": text, "color": color, "fontSize": size])
        askText = nil
    }

    /// 📺 Ask the computer to send its screen (or stop).
    func setMirror(_ on: Bool) {
        mirrorOn = on
        if !on { mirrorImage = nil }
        send(["c": "mirror", "on": on])
    }

    func disconnect() {
        chosen = nil
        conn?.cancel()
        dropped()
    }
}
