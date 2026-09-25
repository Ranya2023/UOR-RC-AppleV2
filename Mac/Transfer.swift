import Foundation

/// Files both ways, using exactly the same chunk protocol as UOR-RC on Windows:
/// start · chunk · end · ack · done · cancel, with at most 8 chunks in flight.
/// Files from the phone land in a **UOR-RC** folder on the Desktop.
final class Transfer {
    private let send: ([String: Any]) -> Void
    private let log: (String) -> Void
    var onMedia: ((URL, Int) -> Void)?      // a photo / video to show full-screen
    var onDoc: ((URL) -> Void)?             // a PDF to present
    var onProgress: ((String, Int, Bool) -> Void)?

    private struct Incoming {
        var handle: FileHandle
        var url: URL
        var name: String
        var size: Int
        var got: Int = 0
        var present: Bool
        var doc: Bool
        var index: Int
    }
    private var incoming: [String: Incoming] = [:]

    init(send: @escaping ([String: Any]) -> Void, log: @escaping (String) -> Void) {
        self.send = send
        self.log = log
    }

    static var folder: URL {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let dir = desktop.appendingPathComponent("UOR-RC")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func unique(_ url: URL) -> URL {
        var candidate = url
        var i = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let stem = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            candidate = url.deletingLastPathComponent()
                .appendingPathComponent("\(stem) (\(i))")
                .appendingPathExtension(ext)
            i += 1
        }
        return candidate
    }

    /// A {"c":"fs", …} message from the phone.
    func handle(_ m: [String: Any]) {
        let id = m.str("id")
        switch m.str("t") {
        case "start":
            let name = m.str("name").isEmpty ? "file" : m.str("name").replacingOccurrences(of: "/", with: "_")
            let present = m.bool("present")
            let doc = m.str("kind") == "doc"
            let base = (present && !doc) ? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("UOR-RC-media")
                                         : Transfer.folder
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let url = Transfer.unique(base.appendingPathComponent(name))
            FileManager.default.createFile(atPath: url.path, contents: nil)
            guard let h = try? FileHandle(forWritingTo: url) else {
                send(["c": "fs", "t": "cancel", "id": id]); return
            }
            incoming[id] = Incoming(handle: h, url: url, name: name, size: m.int("size"),
                                    present: present, doc: doc, index: m.int("index"))
            log("Receiving from phone: \(name)")
            onProgress?(name, 0, false)
            send(["e": "fs", "t": "ack", "id": id, "seq": -1])
        case "chunk":
            guard var inc = incoming[id] else { return }
            if let data = Data(base64Encoded: m.str("d")) {
                inc.handle.write(data)
                inc.got += data.count
                incoming[id] = inc
                if inc.size > 0 { onProgress?(inc.name, inc.got * 100 / inc.size, false) }
            }
            send(["e": "fs", "t": "ack", "id": id, "seq": m.int("seq")])
        case "end":
            guard let inc = incoming.removeValue(forKey: id) else { return }
            try? inc.handle.close()
            send(["e": "fs", "t": "done", "id": id, "ok": true])
            onProgress?(inc.name, 100, false)
            if inc.doc { onDoc?(inc.url) }
            else if inc.present { onMedia?(inc.url, inc.index) }
            else { log("Saved: \(inc.url.path)") }
        case "cancel":
            if let inc = incoming.removeValue(forKey: id) {
                try? inc.handle.close()
                try? FileManager.default.removeItem(at: inc.url)
                log("Transfer stopped.")
            }
        case "ack", "done":
            acks[id]?.signal()
        default: break
        }
    }

    // ── sending to the phone ───────────────────────────────────────────
    private var acks: [String: DispatchSemaphore] = [:]
    private let queue = DispatchQueue(label: "uorrc.files")

    func sendToPhone(_ urls: [URL]) {
        queue.async { for u in urls { self.sendOne(u) } }
    }

    private func sendOne(_ url: URL) {
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).description
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let name = url.lastPathComponent
        let sem = DispatchSemaphore(value: 0)
        acks[id] = sem
        defer { acks[id] = nil }
        log("Sending to phone: \(name)")
        send(["e": "fs", "t": "start", "id": id, "name": name, "size": size])
        guard sem.wait(timeout: .now() + 15) == .success, let file = try? FileHandle(forReadingFrom: url) else {
            log("The phone did not accept \(name)."); return
        }
        for _ in 0..<8 { sem.signal() }                 // allow 8 chunks in flight
        var seq = 0
        var sent = 0
        while let chunk = try? file.read(upToCount: 48 * 1024), !chunk.isEmpty {
            guard sem.wait(timeout: .now() + 20) == .success else {
                send(["e": "fs", "t": "cancel", "id": id]); log("Stopped sending \(name)."); return
            }
            send(["e": "fs", "t": "chunk", "id": id, "seq": seq, "d": chunk.base64EncodedString()])
            seq += 1
            sent += chunk.count
            if size > 0 { onProgress?(name, sent * 100 / size, true) }
        }
        try? file.close()
        send(["e": "fs", "t": "end", "id": id])
        onProgress?(name, 100, true)
        log("Sent to phone: \(name)")
    }
}
