import AppKit
import Foundation

/// Turns the phone's messages into actions on the Mac, and keeps the phone
/// informed — the Mac twin of PowerPointController on Windows.
final class Controller: ObservableObject {
    let settings = HostSettings()
    private lazy var link = HostLink(settings: settings)
    private let presenter = Presenter()
    private let overlay = Overlay()
    private var poll: Timer?

    @Published var phoneName = ""
    @Published var connected = false
    @Published var presentationLine = "…"
    @Published var addresses: [String] = []
    @Published var log: [String] = []

    private var lastState = ""
    private var tool = Tool.mouse

    // the extra screens
    private var board: BoardWindow?
    private var picker: PickerWindow?
    private var media: MediaWindow?
    private var doc: DocWindow?
    private var quiz: QuizServer?
    private var quizScreen: QuizScreen?
    private var camera: CameraWindow?
    private var gallery: GalleryWindow?
    private lazy var files = Transfer(send: { [weak self] in self?.link.send($0) },
                                      log: { [weak self] in self?.append($0) })
    /// every page of drawings (slide 5, board page 2, a photo…) keeps its own ink and marks
    private var pages: [String: (strokes: [OverlayView.Stroke], marks: [OverlayView.Mark])] = [:]
    private var pageKey = ""

    private var topWindow: FullScreen? {
        if let m = media, m.isVisible { return m }
        if let d = doc, d.isVisible { return d }
        if let b = board, b.isVisible { return b }
        if let p = picker, p.isVisible { return p }
        if let q = quizScreen, q.isVisible { return q }
        if let c = camera, c.isVisible { return c }
        if let g = gallery, g.isVisible { return g }
        return nil
    }
    private var viewName: String {
        if media?.isVisible == true { return "media" }
        if doc?.isVisible == true { return "doc" }
        if board?.isVisible == true { return "board" }
        if picker?.isVisible == true { return "picker" }
        if quizScreen?.isVisible == true { return "quiz" }
        if camera?.isVisible == true { return "phone" }
        if gallery?.isVisible == true { return "gallery" }
        return ""
    }
    private var viewKey: String {
        if media?.isVisible == true { return "media:" + (media?.currentName ?? "") }
        if let d = doc, d.isVisible { return d.key }
        if let b = board, b.isVisible { return b.key }
        if picker?.isVisible == true { return "picker" }
        if quizScreen?.isVisible == true { return "quiz" }
        if camera?.isVisible == true { return "phone" }
        if let g = gallery, g.isVisible { return g.key }
        return "slide:\(presenter.slide)"
    }

    /// Show one screen; the others step aside.
    private func showOnly(_ which: String) {
        if which != "media" { media?.orderOut(nil); media?.stop() }
        if which != "doc" { doc?.orderOut(nil) }
        if which != "board" { board?.orderOut(nil) }
        if which != "picker" { picker?.orderOut(nil) }
        if which != "quiz" { quizScreen?.orderOut(nil) }
        if which != "phone" { camera?.orderOut(nil) }
        if which != "gallery" { gallery?.orderOut(nil) }
        lastState = ""
    }

    /// Remember this page's drawings and load the new page's.
    private func switchPage(to key: String) {
        guard key != pageKey else { return }
        let v = overlay.state
        if !pageKey.isEmpty { pages[pageKey] = (v.strokes, v.marks) }
        pageKey = key
        let saved = pages[key] ?? ([], [])
        v.strokes = saved.strokes
        v.marks = saved.marks
        v.current = nil
        overlay.refresh()
    }
    private var inkColor = NSColor.systemRed
    private var inkSize: CGFloat = 4

    func start() {
        Input.ensurePermission()
        link.onLog = { [weak self] m in self?.append(m) }
        link.onConnected = { [weak self] ok, name in
            guard let self else { return }
            self.connected = ok
            self.phoneName = name
            self.append(ok ? "Phone connected: \(name)" : "Phone disconnected")
            if !ok { self.overlay.state.laserOn = false; self.overlay.state.spotOn = false; self.overlay.refresh() }
        }
        link.onLine = { [weak self] m in self?.handle(m) }
        // an iPhone shares its screen through a separate little program, which connects to us
        iphoneScreen.onLog = { [weak self] m in self?.append(m) }
        iphoneScreen.onFrame = { [weak self] image in
            guard let self else { return }
            if self.camera == nil { self.camera = CameraWindow() }
            if self.camera?.isVisible != true { self.showOnly("phone") }
            self.camera?.place(self.presenter.showFrame)
            self.camera?.show(image, rotation: 0, fill: false)
        }
        iphoneScreen.onStreaming = { [weak self] on in
            if !on { self?.camera?.orderOut(nil); self?.lastState = ""; self?.tick() }
        }
        files.onProgress = { [weak self] name, pct, toPhone in
            if pct == 0 || pct == 100 { self?.append((toPhone ? "→ phone: " : "← phone: ") + name + (pct == 100 ? " ✓" : "")) }
        }
        files.onMedia = { [weak self] url, index in
            guard let self else { return }
            if self.media == nil { self.media = MediaWindow() }
            if index == 0 { self.media?.clear() }
            self.media?.add(url)
            self.showOnly("media")
            self.media?.place(self.presenter.showFrame)
            self.media?.showCurrent()
            self.lastState = ""
        }
        files.onDoc = { [weak self] url in
            guard let self else { return }
            if url.pathExtension.lowercased() == "pdf" {
                if self.doc == nil { self.doc = DocWindow() }
                self.showOnly("doc")
                self.doc?.place(self.presenter.showFrame)
                if self.doc?.open(url) != true { self.append("Could not open \(url.lastPathComponent)") }
            } else {
                // Word / PowerPoint: let the Mac open it with its own program
                NSWorkspace.shared.open(url)
                self.append("Opened \(url.lastPathComponent) with its normal Mac program.")
            }
            self.lastState = ""
        }
        link.start()
        addresses = Net.addresses()
        poll = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in self?.tick() }
        append("UOR-RC for Mac started. PIN \(settings.pin)")
    }

    func stop() { poll?.invalidate(); link.stop(); iphoneScreen.stop() }

    /// 💾 Every whiteboard page as a picture in the UOR-RC folder on the Desktop.
    private func saveBoard() {
        guard let b = board else { return }
        let dir = Transfer.folder.appendingPathComponent("Whiteboard " + DateFormatter.fileStamp.string(from: Date()))
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let current = (overlay.state.strokes, overlay.state.marks)
        pages[pageKey] = current
        for p in 1...max(1, b.pages) {
            let key = "board:\(p)"
            let saved = pages[key] ?? ([], [])
            let size = b.frame.size
            let image = NSImage(size: size)
            image.lockFocus()
            let bg: NSColor = b.background == "black" ? NSColor(white: 0.09, alpha: 1)
                            : b.background == "green" ? NSColor(red: 0.12, green: 0.30, blue: 0.23, alpha: 1) : .white
            bg.setFill(); NSRect(origin: .zero, size: size).fill()
            if let ctx = NSGraphicsContext.current?.cgContext {
                for s in saved.strokes where s.points.count > 1 {
                    ctx.setLineCap(.round); ctx.setLineJoin(.round)
                    ctx.setLineWidth(max(1, s.width * size.height / 1080))
                    ctx.setStrokeColor(s.color.withAlphaComponent(s.highlight ? 0.42 : 1).cgColor)
                    ctx.beginPath()
                    ctx.move(to: CGPoint(x: s.points[0].x * size.width, y: (1 - s.points[0].y) * size.height))
                    for pt in s.points.dropFirst() {
                        ctx.addLine(to: CGPoint(x: pt.x * size.width, y: (1 - pt.y) * size.height))
                    }
                    ctx.strokePath()
                }
            }
            image.unlockFocus()
            if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("page \(p).png"))
            }
        }
        append("Whiteboard saved: \(dir.path)")
        link.send(["e": "saved", "path": dir.path, "pages": b.pages])
    }

    private var mirrorOn = false
    private var mirrorWaiting = false
    private var lastThumb = Date.distantPast

    /// 📺 Sends the Mac's screen to the phone, paced by the phone's answers.
    private func startMirror() {
        DispatchQueue.global().async { [weak self] in
            while let self, self.mirrorOn, self.link.isConnected {
                if self.mirrorWaiting { Thread.sleep(forTimeInterval: 0.05); continue }
                guard let jpeg = Controller.screenJpeg(width: 900, quality: 0.5) else { break }
                self.mirrorWaiting = true
                self.link.send(["e": "frame", "img": jpeg.base64EncodedString()])
                Thread.sleep(forTimeInterval: 0.08)
            }
        }
    }

    /// A small picture of what is on the projector — the phone shows it under the touchpad.
    private func sendThumb() {
        guard Date().timeIntervalSince(lastThumb) > 1.2, topWindow == nil else { return }
        lastThumb = Date()
        DispatchQueue.global().async { [weak self] in
            guard let self, let jpeg = Controller.screenJpeg(width: 640, quality: 0.45) else { return }
            self.link.send(["e": "thumb", "which": "cur", "slide": self.presenter.slide,
                            "img": jpeg.base64EncodedString()])
        }
    }

    static func screenJpeg(width: CGFloat, quality: CGFloat) -> Data? {
        guard let screen = NSScreen.main,
              let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
              let shot = CGDisplayCreateImage(id) else { return nil }
        let scale = width / CGFloat(shot.width)
        let size = NSSize(width: width, height: CGFloat(shot.height) * scale)
        let image = NSImage(cgImage: shot, size: size)
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    private var cameraRotation = 0
    private var cameraFill = false
    private let audio = AudioOut()
    private let iphoneScreen = PhoneScreenServer()

    /// The quiz changed: repaint the projector and tell the teacher's phone.
    private func quizChanged() {
        guard let q = quiz else { return }
        let counts = q.counts()
        let top = q.top(8)
        quizScreen?.update(question: q.question, options: q.options, counts: counts, reveal: q.reveal,
                           correct: q.correct, open: q.isOpen, left: q.left, seconds: q.seconds,
                           players: q.playerCount, index: q.qIndex, count: q.qCount,
                           url: q.bestUrl(), top: top)
        link.send(["e": "quiz", "open": q.isOpen, "reveal": q.reveal, "correct": q.correct,
                   "n": q.optionCount, "counts": counts, "total": q.total, "players": q.playerCount,
                   "left": q.left, "qi": q.qIndex, "qn": q.qCount, "url": q.bestUrl(),
                   "top": top.map { ["name": $0.name, "score": $0.score] }])
    }

    private func append(_ line: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        log.append("[\(stamp)] \(line)")
        if log.count > 300 { log.removeFirst(100) }
    }

    // ── what the phone shows ───────────────────────────────────────────
    private func tick() {
        presenter.refresh()
        presentationLine = presenter.statusLine
        let frame = presenter.showFrame
        overlay.place(on: frame)
        topWindow?.place(frame)
        switchPage(to: viewKey)
        let state: [String: Any] = [
            "e": "state", "ppt": presenter.app != .none, "show": presenter.presenting,
            "name": presenter.docName, "slide": presenter.slide, "total": presenter.total,
            "click": -1, "clicks": -1, "screen": "normal", "notes": presenter.notes,
            "sw": presenter.showFrame.width, "sh": presenter.showFrame.height,
            "view": viewName,
            "page": board?.isVisible == true ? board!.page : (doc?.isVisible == true ? doc!.page : 0),
            "pages": board?.isVisible == true ? board!.pages : (doc?.isVisible == true ? doc!.pages : (gallery?.isVisible == true ? gallery!.count : 0)),
            "single": gallery?.single ?? true,
            "bg": board?.background ?? "", "doc": doc?.name ?? "", "mi": -1, "phone": false
        ]
        sendThumb()
        let key = "\(presenter.slide)|\(presenter.total)|\(presenter.presenting)|\(presenter.docName)|\(viewName)|\(board?.page ?? 0)|\(doc?.page ?? 0)|\(board?.background ?? "")"
        if key != lastState {
            lastState = key
            link.send(state)
        }
    }

    // ── the phone's messages ───────────────────────────────────────────
    private func handle(_ m: [String: Any]) {
        let c = m.str("c")
        let v = overlay.state
        switch c {
        case "hello": lastState = ""; tick()
        case "ping": link.send(["e": "pong"])

        // slides
        case "next", "prev":
            let forward = c == "next"
            if media?.isVisible == true { forward ? media?.next() : media?.prev() }
            else if doc?.isVisible == true { forward ? doc?.next() : doc?.prev() }
            else if board?.isVisible == true { forward ? board?.nextPage() : board?.prevPage() }
            else if gallery?.isVisible == true, gallery?.single == true { forward ? gallery?.next() : gallery?.prev() }
            else { forward ? presenter.next() : presenter.previous() }
            lastState = ""; tick()
        case "goto": presenter.goTo(m.int("n")); lastState = ""; tick()
        case "start": presenter.start(fromCurrent: m.str("from") == "current"); lastState = ""; tick()
        case "end": presenter.end(); lastState = ""; tick()
        case "screen": presenter.screen(m.str("m"))

        // touchpad & keyboard
        case "rel": Input.moveRelative(dx: m.num("dx"), dy: m.num("dy"))
        case "abs":
            let f = presenter.showFrame
            Input.moveAbsolute(x: f.minX + m.num("x") * f.width, y: f.minY + m.num("y") * f.height)
        case "btn": Input.button(m.str("b"), m.str("a"))
        case "scroll": Input.scroll(m.int("d"))
        case "type": Input.type(m.str("text"))
        case "key": Input.named(m.str("k"), ctrl: m.bool("ctrl"), shift: m.bool("shift"),
                                alt: m.bool("alt"), cmd: m.bool("win"), repeatCount: max(1, m.int("n")))

        // tools
        case "tool": tool = Tool(rawValue: m.str("t")) ?? .mouse
        case "color":
            inkColor = NSColor(hex: m.str("rgb")) ?? .systemRed
        case "laser", "laser_style":
            if m.has("x") { v.laser = CGPoint(x: m.num("x"), y: m.num("y")) }
            if c == "laser" { v.laserOn = m.bool("active") }
            if m.has("size") { v.laserSize = CGFloat(m.num("size")) }
            if m.has("color") { v.laserColor = NSColor(hex: m.str("color")) ?? .systemRed }
            if m.has("label") { v.laserLabel = m.str("label") }
            overlay.refresh()
        case "spot", "spot_style":
            if m.has("x") { v.spot = CGPoint(x: m.num("x"), y: m.num("y")) }
            if c == "spot" { v.spotOn = m.bool("active") }
            if m.has("radius") { v.spotRadius = CGFloat(m.num("radius")) }
            if m.has("style") { v.spotStyle = m.str("style") }
            overlay.refresh()
        case "lens", "lens_style":
            if m.has("x") { v.lens = CGPoint(x: m.num("x"), y: m.num("y")) }
            if c == "lens" { v.lensOn = m.bool("active") }
            if m.has("radius") { v.lensRadius = CGFloat(m.num("radius")) }
            if m.has("zoom") { v.lensZoom = CGFloat(m.num("zoom")) }
            if m.has("bright") { v.lensBright = CGFloat(m.num("bright")) / 100 }
            if m.has("dim") { v.lensDim = m.bool("dim") }
            overlay.refresh()

        // pen / highlighter / eraser
        case "ink_start":
            inkSize = CGFloat(m.num("size"))
            if m.has("color") { inkColor = NSColor(hex: m.str("color")) ?? inkColor }
            v.current = OverlayView.Stroke(points: [CGPoint(x: m.num("x"), y: m.num("y"))],
                                           color: inkColor, width: inkSize, highlight: m.bool("hl"))
            overlay.refresh()
        case "ink_pts":
            if let arr = m["p"] as? [Double] {
                var pts = v.current?.points ?? []
                var i = 0
                while i + 1 < arr.count { pts.append(CGPoint(x: arr[i], y: arr[i + 1])); i += 2 }
                v.current?.points = pts
                overlay.refresh()
            }
        case "ink_end":
            if let s = v.current { v.strokes.append(s) }
            v.current = nil
            overlay.refresh()
        case "ink_erase":
            let p = CGPoint(x: m.num("x"), y: m.num("y"))
            v.strokes.removeAll { s in s.points.contains { hypot($0.x - p.x, $0.y - p.y) < 0.02 } }
            overlay.refresh()
        case "ink_erase_end":
            break                      // nothing to finish on the Mac side
        case "back_show":              // "▶ Back to PowerPoint" from the Android app
            NSWorkspace.shared.runningApplications.first { $0.localizedName == "Microsoft PowerPoint" || $0.localizedName == "Keynote" }?
                .activate(options: [])
        case "desktop":
            Input.key(0x67)            // F11 — show the desktop
        case "clear":
            v.strokes.removeAll(); v.marks.removeAll(); v.current = nil
            pages[pageKey] = ([], [])
            overlay.refresh()

        // timer
        case "timer":
            let secs = m.int("sec")
            v.timerText = (m.bool("visible") && secs >= 0)
                ? String(format: "%@ %02d:%02d", m.str("mode") == "up" ? "⏱" : "⌛", secs / 60, secs % 60) : nil
            v.timerUrgent = m.str("mode") != "up" && secs <= 60
            overlay.refresh()

        // ── 🧑‍🏫 whiteboard ──
        case "board":
            if board == nil { board = BoardWindow() }
            switch m.str("a") {
            case "open":
                if !m.str("v").isEmpty { board?.setBackground(m.str("v")) }
                showOnly("board"); board?.place(presenter.showFrame)
            case "next": board?.nextPage()
            case "prev": board?.prevPage()
            case "bg": board?.setBackground(m.str("v"))
            case "save": saveBoard()
            case "close": showOnly("")
            default: break
            }
            lastState = ""; tick()

        // ── 🎲 random picker ──
        case "picker":
            if m.str("a") == "close" { showOnly(""); lastState = ""; tick(); return }
            let names = (m["names"] as? [String]) ?? []
            guard !names.isEmpty else { return }
            if picker == nil { picker = PickerWindow() }
            showOnly("picker")
            picker?.place(presenter.showFrame)
            picker?.pick(names: names, winner: m.int("winner"), title: m.str("title"),
                         remaining: m.has("remaining") ? m.int("remaining") : -1,
                         wheel: m.str("style") == "wheel") { [weak self] name in
                self?.link.send(["e": "picked", "name": name])
            }
            lastState = ""; tick()

        // ── 🖼 photos & videos ──
        case "media":
            guard let mw = media else { return }
            switch m.str("a") {
            case "show": showOnly("media"); mw.place(presenter.showFrame); mw.showCurrent()
            case "hide": mw.orderOut(nil); mw.stop()
            case "next": mw.next()
            case "prev": mw.prev()
            case "toggle": mw.togglePlay()
            case "rel": mw.seek(by: m.num("v"))
            case "vol": mw.volume(Float(m.num("v")))
            case "fill": mw.fill.toggle()
            case "close": mw.clear(); showOnly("")
            default: break
            }
            lastState = ""; tick()

        // ── 📑 document pages ──
        case "doc":
            switch m.str("a") {
            case "next": doc?.next()
            case "prev": doc?.prev()
            case "close": showOnly("")
            default: break
            }
            lastState = ""; tick()

        // ── 🗳️ live quiz ──
        case "quiz":
            if quiz == nil {
                let q = QuizServer()
                q.onChange = { [weak self] in self?.quizChanged() }
                quiz = q
            }
            guard let q = quiz else { return }
            switch m.str("a") {
            case "start":
                if !q.start() { append("The quiz could not start (ports 8088–8095 are busy)."); return }
                var opts = (m["opts"] as? [String]) ?? []
                while opts.count < max(2, m.int("n")) { opts.append("") }
                q.newQuestion(m.str("q"), options: opts, correct: m.has("correct") ? m.int("correct") : -1,
                              index: m.int("qi"), count: m.int("qn"), seconds: m.int("secs"))
                if quizScreen == nil { quizScreen = QuizScreen() }
                quizScreen?.showScores = false
                showOnly("quiz")
                quizScreen?.place(presenter.showFrame)
                append("Quiz open at " + q.bestUrl() + " — students join the same Wi-Fi.")
            case "reveal": q.showResults()
            case "correct": q.setCorrect(m.int("v"))
            case "reset": q.resetScores()
            case "scores":
                quizScreen?.showScores.toggle()
                showOnly("quiz"); quizScreen?.place(presenter.showFrame)
            case "show": showOnly("quiz"); quizScreen?.place(presenter.showFrame)
            case "close": q.closeQuestion(); showOnly("")
            default: break
            }
            quizChanged(); lastState = ""; tick()

        // ── 📷 the phone's camera, live on the projector ──
        case "phone_frame":
            if let data = Data(base64Encoded: m.str("img")), let image = NSImage(data: data) {
                if camera == nil { camera = CameraWindow() }
                if camera?.isVisible != true { showOnly("phone") }
                camera?.place(presenter.showFrame)
                camera?.show(image, rotation: cameraRotation, fill: cameraFill)
                lastState = ""
            }
            link.send(["e": "phone_ack"])
        case "phone_view":
            cameraRotation = m.int("rot"); cameraFill = m.bool("fill")
        case "phone_stop":
            camera?.orderOut(nil); lastState = ""; tick()

        // ── 📸 group photos ──
        case "shot":
            if let data = Data(base64Encoded: m.str("img")), let image = NSImage(data: data) {
                let dir = Transfer.folder.appendingPathComponent("Camera")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let label = m.str("label").replacingOccurrences(of: "/", with: "-")
                let file = dir.appendingPathComponent("\(DateFormatter.fileStamp.string(from: Date())) \(label).jpg")
                try? data.write(to: file)
                if gallery == nil { gallery = GalleryWindow() }
                gallery?.add(image, caption: label)
                append("📸 Photo saved: \(file.path)")
                if m.bool("show") {
                    gallery?.single = m.bool("single")
                    showOnly("gallery"); gallery?.place(presenter.showFrame)
                }
                lastState = ""; tick()
            }
        case "gallery":
            guard let g = gallery else { return }
            switch m.str("a") {
            case "show": showOnly("gallery"); g.place(presenter.showFrame)
            case "grid": g.single = false
            case "single": g.single = true
            case "next": g.next()
            case "prev": g.prev()
            case "clear": g.clear()
            case "close": showOnly("")
            default: break
            }
            lastState = ""; tick()

        // ── 🎤 the phone's microphone, played on the Mac ──
        case "audio": audio.play(base64: m.str("d"), rate: m.int("r"), channels: max(1, m.int("ch")))
        case "audio_stop": audio.stop()

        // ── 📱 the iPhone is about to share its screen ──
        case "screen_token":
            iphoneScreen.setToken(m.str("token"))
            append("Ready for the iPhone's screen.")

        // ── 🔍 projector zoom (pinch on the phone) ──
        case "zoom":
            v.zoom = CGFloat(max(1, min(m.num("s"), 4)))
            v.zoomX = CGFloat(min(max(m.num("x"), 0), 1))
            v.zoomY = CGFloat(min(max(m.num("y"), 0), 1))
            overlay.refresh()

        // ── 📺 the Mac's screen, live on the phone's touchpad ──
        case "mirror":
            mirrorOn = m.bool("on")
            if mirrorOn { startMirror() }
        case "sabs":                    // tapping on the mirrored screen
            let f = presenter.showFrame
            Input.moveAbsolute(x: f.minX + m.num("x") * f.width, y: f.minY + m.num("y") * f.height)
            if m.str("a") != "move" { Input.button("left", m.str("a")) }
        case "frame_ack":
            mirrorWaiting = false

        // ── placing numbers and text: the light preview before the tap ──
        case "ann_preview":
            let colors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen,
                                     .systemTeal, .systemBlue, .systemPurple, .systemPink]
            let count = v.marks.filter { $0.kind == "number" }.count
            v.preview = OverlayView.Mark(kind: m.str("kind"), x: CGFloat(m.num("x")), y: CGFloat(m.num("y")),
                                         text: m.str("kind") == "number" ? "\(count + 1)" : m.str("text"),
                                         color: colors[count % colors.count], size: CGFloat(max(16, m.num("size"))))
            overlay.refresh()
        case "ann_preview_end":
            v.preview = nil; overlay.refresh()
        case "ann_delete":
            let x = CGFloat(m.num("x")), y = CGFloat(m.num("y"))
            v.marks.removeAll { hypot($0.x - x, $0.y - y) < 0.05 }
            overlay.refresh()

        // ── ⏰ time is up ──
        case "timer_alert":
            v.flash = Date()
            overlay.refresh()
            NSSound.beep()

        // ── things a Mac cannot do ──
        case "pc_speaker", "join_wifi":
            link.send(["e": c, "on": false, "error": "not-on-mac"])

        // ── 📁 files both ways ──
        case "fs": files.handle(m)

        // ── 🔢 numbers and 📍 text on the page ──
        case "ann_tap":
            let x = CGFloat(m.num("x")), y = CGFloat(m.num("y"))
            if m.str("kind") == "number" {
                if let hit = v.marks.firstIndex(where: { $0.kind == "number" && hypot($0.x - x, $0.y - y) < 0.03 }) {
                    v.marks.remove(at: hit)                       // tap a number again to remove it
                } else {
                    let colors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen,
                                             .systemTeal, .systemBlue, .systemPurple, .systemPink]
                    let count = v.marks.filter { $0.kind == "number" }.count
                    v.marks.append(OverlayView.Mark(kind: "number", x: x, y: y, text: "\(count + 1)",
                                                    color: colors[count % colors.count], size: CGFloat(max(16, m.num("size")))))
                }
                overlay.refresh()
            } else {
                link.send(["e": "new_text", "sx": Double(x), "sy": Double(y)])
            }
        case "text_save":
            let text = m.str("text")
            if !text.isEmpty {
                v.marks.append(OverlayView.Mark(kind: "text", x: CGFloat(m.num("sx")), y: CGFloat(m.num("sy")),
                                                text: text, color: NSColor(hex: m.str("color")) ?? .systemYellow,
                                                size: CGFloat(max(10, m.num("fontSize")))))
                overlay.refresh()
            }

        default: break   // still Windows-only: quiz, camera, phone-screen sharing
        }
    }
}

extension DateFormatter {
    static let fileStamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH-mm"; return f
    }()
}

extension NSColor {
    /// "#RRGGBB" → colour
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255,
                  blue: CGFloat(v & 255) / 255, alpha: 1)
    }
}
