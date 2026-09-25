import AppKit
import AVKit
import PDFKit

/// A full-screen window over the projector (whiteboard, picker, photos, documents).
class FullScreen: NSWindow {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = true
        backgroundColor = .black
        level = .modalPanel                      // above the slide show, below the drawing layer
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ignoresMouseEvents = false
    }
    func place(_ frame: CGRect) {
        if self.frame != frame { setFrame(frame, display: true) }
        orderFrontRegardless()
    }
}

// ─────────────────────────────────────────────────────────────────────
//  🧑‍🏫 Whiteboard — pages you write on with the pen
// ─────────────────────────────────────────────────────────────────────
final class BoardWindow: FullScreen {
    private let view = BoardView()
    var page = 1 { didSet { view.page = page; view.needsDisplay = true } }
    var pages = 1 { didSet { view.pages = pages; view.needsDisplay = true } }
    var key: String { "board:\(page)" }

    init() {
        super.init(frame: .zero)
        contentView = view
    }

    func setBackground(_ name: String) { view.kind = name; view.needsDisplay = true }
    var background: String { view.kind }

    func nextPage() { if page == pages { pages += 1 }; page += 1 }
    func prevPage() { if page > 1 { page -= 1 } }

    final class BoardView: NSView {
        var kind = "white"
        var page = 1
        var pages = 1
        override var isFlipped: Bool { true }
        override func draw(_ r: NSRect) {
            let bg: NSColor = kind == "black" ? NSColor(white: 0.09, alpha: 1)
                            : kind == "green" ? NSColor(red: 0.12, green: 0.30, blue: 0.23, alpha: 1)
                            : .white
            bg.setFill(); bounds.fill()
            if kind == "grid" {
                NSColor(red: 0.25, green: 0.4, blue: 0.7, alpha: 0.18).setStroke()
                let step = bounds.height / 18
                let path = NSBezierPath(); path.lineWidth = 1
                var x = step; while x < bounds.width { path.move(to: CGPoint(x: x, y: 0)); path.line(to: CGPoint(x: x, y: bounds.height)); x += step }
                var y = step; while y < bounds.height { path.move(to: CGPoint(x: 0, y: y)); path.line(to: CGPoint(x: bounds.width, y: y)); y += step }
                path.stroke()
            }
            let label = "\(page) / \(pages)"
            let color: NSColor = (kind == "black" || kind == "green") ? NSColor(white: 1, alpha: 0.5) : NSColor(white: 0, alpha: 0.45)
            let font = NSFont.systemFont(ofSize: bounds.height / 40, weight: .bold)
            let text = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: color])
            text.draw(at: CGPoint(x: bounds.maxX - text.size().width - 24, y: bounds.maxY - text.size().height - 18))
        }
    }
}

// ─────────────────────────────────────────────────────────────────────
//  🎲 Random picker — names spin and land on the chosen student
// ─────────────────────────────────────────────────────────────────────
final class PickerWindow: FullScreen {
    private let view = PickerView()
    init() { super.init(frame: .zero); contentView = view }
    func pick(names: [String], winner: Int, title: String, remaining: Int, wheel: Bool, done: @escaping (String) -> Void) {
        view.start(names: names, winner: winner, title: title, remaining: remaining, wheel: wheel, done: done)
    }

    final class PickerView: NSView {
        private var names: [String] = []
        private var winner = 0
        private var title = ""
        private var remaining = -1
        private var wheel = false
        private var start = Date()
        private var timer: Timer?
        private var done: ((String) -> Void)?
        private var reported = false
        private let spin: TimeInterval = 3.8

        override var isFlipped: Bool { true }

        func start(names: [String], winner: Int, title: String, remaining: Int, wheel: Bool, done: @escaping (String) -> Void) {
            guard !names.isEmpty else { return }
            self.names = names
            self.winner = max(0, min(winner, names.count - 1))
            self.title = title; self.remaining = remaining; self.wheel = wheel; self.done = done
            self.start = Date(); self.reported = false
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] t in
                guard let self else { return }
                self.needsDisplay = true
                if Date().timeIntervalSince(self.start) > self.spin + 3 { t.invalidate() }
            }
        }

        private func ease(_ t: Double) -> Double { 1 - pow(1 - min(max(t, 0), 1), 3) }

        override func draw(_ r: NSRect) {
            NSColor(red: 0.06, green: 0.08, blue: 0.13, alpha: 1).setFill(); bounds.fill()
            guard !names.isEmpty else { return }
            let t = Date().timeIntervalSince(start)
            let p = ease(t / spin)
            let finished = t >= spin
            let px = { (v: CGFloat) in v * self.bounds.height / 1080 }

            let head = NSAttributedString(string: "🎲  " + (title.isEmpty ? "Random pick" : title), attributes: [
                .font: NSFont.systemFont(ofSize: px(38), weight: .bold),
                .foregroundColor: NSColor(white: 0.65, alpha: 1)])
            head.draw(at: CGPoint(x: (bounds.width - head.size().width) / 2, y: px(50)))

            if wheel { drawWheel(p: p, finished: finished, px: px) } else { drawName(p: p, finished: finished, px: px) }

            if remaining >= 0 {
                let left = NSAttributedString(string: "\(remaining) left", attributes: [
                    .font: NSFont.systemFont(ofSize: px(26)), .foregroundColor: NSColor(white: 0.55, alpha: 1)])
                left.draw(at: CGPoint(x: (bounds.width - left.size().width) / 2, y: bounds.maxY - px(90)))
            }
            if finished, !reported { reported = true; done?(names[winner]) }
        }

        private func drawName(p: Double, finished: Bool, px: (CGFloat) -> CGFloat) {
            let laps = names.count < 10 ? 3 : 1
            let steps = max(22, laps * names.count) + winner
            let index = (Int(Double(steps) * p)) % names.count
            let name = finished ? names[winner] : names[index]
            var size = px(finished ? 150 : 120)
            var attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size, weight: .heavy),
                .foregroundColor: finished ? NSColor(red: 0.98, green: 0.75, blue: 0.14, alpha: 1) : NSColor.white]
            var text = NSAttributedString(string: name, attributes: attrs)
            if text.size().width > bounds.width * 0.9 {
                size *= bounds.width * 0.9 / text.size().width
                attrs[.font] = NSFont.systemFont(ofSize: size, weight: .heavy)
                text = NSAttributedString(string: name, attributes: attrs)
            }
            text.draw(at: CGPoint(x: (bounds.width - text.size().width) / 2, y: bounds.midY - text.size().height / 2))
        }

        private func drawWheel(p: Double, finished: Bool, px: (CGFloat) -> CGFloat) {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            let n = names.count
            let r = min(bounds.width, bounds.height) * 0.38
            let c = CGPoint(x: bounds.midX, y: bounds.midY + px(20))
            let seg = 360.0 / Double(n)
            let end = 270.0 - (Double(winner) * seg + seg / 2) + 360 * Double(n <= 6 ? 6 : 4)
            let rot = end * p
            let colors: [NSColor] = [.systemRed, .systemBlue, .systemYellow, .systemGreen, .systemPurple, .systemOrange, .systemTeal, .systemPink]
            for i in 0..<n {
                let a0 = (rot + Double(i) * seg) * .pi / 180
                let a1 = a0 + seg * .pi / 180
                ctx.beginPath()
                ctx.move(to: c)
                ctx.addArc(center: c, radius: r, startAngle: a0, endAngle: a1, clockwise: false)
                ctx.closePath()
                colors[i % colors.count].setFill()
                ctx.fillPath()
                // the name along the slice
                ctx.saveGState()
                ctx.translateBy(x: c.x, y: c.y)
                ctx.rotate(by: CGFloat(a0 + seg * .pi / 360))
                let f = NSFont.systemFont(ofSize: max(px(12), min(px(30), r * 1.2 / CGFloat(max(6, n)))), weight: .bold)
                let s = NSAttributedString(string: names[i], attributes: [.font: f, .foregroundColor: NSColor.white])
                s.draw(at: CGPoint(x: r * 0.30, y: -s.size().height / 2))
                ctx.restoreGState()
            }
            NSColor(red: 0.98, green: 0.75, blue: 0.14, alpha: 1).setStroke()
            let rim = NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            rim.lineWidth = px(6); rim.stroke()
            // pointer
            let tri = NSBezierPath()
            tri.move(to: CGPoint(x: c.x, y: c.y - r + px(24)))
            tri.line(to: CGPoint(x: c.x - px(24), y: c.y - r - px(24)))
            tri.line(to: CGPoint(x: c.x + px(24), y: c.y - r - px(24)))
            tri.close()
            NSColor(red: 0.98, green: 0.75, blue: 0.14, alpha: 1).setFill(); tri.fill()
            if finished {
                let s = NSAttributedString(string: names[winner], attributes: [
                    .font: NSFont.systemFont(ofSize: px(54), weight: .heavy),
                    .foregroundColor: NSColor(red: 0.98, green: 0.75, blue: 0.14, alpha: 1)])
                s.draw(at: CGPoint(x: (bounds.width - s.size().width) / 2, y: bounds.maxY - px(150)))
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────
//  🖼 Photos & videos, and 📑 PDF pages
// ─────────────────────────────────────────────────────────────────────
final class MediaWindow: FullScreen {
    private let imageView = NSImageView()
    private let playerView = AVPlayerView()
    private var items: [URL] = []
    private var index = 0
    var fill = false { didSet { imageView.imageScaling = fill ? .scaleProportionallyUpOrDown : .scaleProportionallyDown } }
    var count: Int { items.count }
    var currentName: String { index < items.count ? items[index].lastPathComponent : "" }

    init() {
        super.init(frame: .zero)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.autoresizingMask = [.width, .height]
        playerView.controlsStyle = .none
        playerView.autoresizingMask = [.width, .height]
        let host = NSView()
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        contentView = host
    }

    func add(_ url: URL) { items.append(url); index = items.count - 1 }
    func clear() { items.removeAll(); index = 0; stop() }
    func next() { guard !items.isEmpty else { return }; index = (index + 1) % items.count; showCurrent() }
    func prev() { guard !items.isEmpty else { return }; index = (index - 1 + items.count) % items.count; showCurrent() }

    func showCurrent() {
        guard index < items.count, let host = contentView else { return }
        let url = items[index]
        host.subviews.forEach { $0.removeFromSuperview() }
        let isVideo = ["mp4", "mov", "m4v", "webm", "mkv", "avi"].contains(url.pathExtension.lowercased())
        if isVideo {
            let player = AVPlayer(url: url)
            playerView.player = player
            playerView.frame = host.bounds
            host.addSubview(playerView)
            player.play()
        } else {
            playerView.player?.pause()
            imageView.image = NSImage(contentsOf: url)
            imageView.frame = host.bounds
            host.addSubview(imageView)
        }
        orderFrontRegardless()
    }

    func togglePlay() {
        guard let p = playerView.player else { return }
        p.rate == 0 ? p.play() : p.pause()
    }
    func seek(by seconds: Double) {
        guard let p = playerView.player else { return }
        let t = CMTimeGetSeconds(p.currentTime()) + seconds
        p.seek(to: CMTime(seconds: max(0, t), preferredTimescale: 600))
    }
    func volume(_ delta: Float) {
        guard let p = playerView.player else { return }
        p.volume = max(0, min(1, p.volume + delta))
    }
    func stop() { playerView.player?.pause(); playerView.player = nil }
}

/// 📑 PDF pages, driven with NEXT / ◀ like slides.
final class DocWindow: FullScreen {
    private let pdfView = PDFView()
    private(set) var pages = 0
    private(set) var page = 1
    private(set) var name = ""
    var key: String { "doc:\(name):\(page)" }

    init() {
        super.init(frame: .zero)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.backgroundColor = .black
        pdfView.autoresizingMask = [.width, .height]
        contentView = pdfView
    }

    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let doc = PDFDocument(url: url) else { return false }
        pdfView.document = doc
        pages = doc.pageCount
        page = 1
        name = url.lastPathComponent
        pdfView.goToFirstPage(nil)
        orderFrontRegardless()
        return true
    }

    func next() { if page < pages { page += 1; pdfView.goToNextPage(nil) } }
    func prev() { if page > 1 { page -= 1; pdfView.goToPreviousPage(nil) } }
}
