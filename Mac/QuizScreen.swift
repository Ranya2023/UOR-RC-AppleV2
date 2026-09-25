import AppKit
import CoreImage

/// 🗳️ What the projector shows during the quiz: the question, the answers with
/// their share of the votes, the countdown, the join code — and 🏆 the scores.
final class QuizScreen: FullScreen {
    private let view = QuizView()
    init() { super.init(frame: .zero); contentView = view }

    func update(question: String, options: [String], counts: [Int], reveal: Bool, correct: Int,
                open: Bool, left: Int, seconds: Int, players: Int, index: Int, count: Int,
                url: String, top: [(name: String, score: Int, last: Int)]) {
        view.question = question; view.options = options; view.counts = counts
        view.reveal = reveal; view.correct = correct; view.isOpen = open
        view.left = left; view.seconds = max(1, seconds)
        view.players = players; view.qIndex = index; view.qCount = count
        view.top = top
        if view.url != url { view.url = url; view.qr = QuizScreen.qrImage(url) }
        view.needsDisplay = true
    }

    var showScores: Bool {
        get { view.showScores }
        set { view.showScores = newValue; view.needsDisplay = true }
    }

    /// A QR code students can scan to open the quiz.
    static func qrImage(_ text: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    final class QuizView: NSView {
        var question = ""; var options: [String] = []; var counts: [Int] = []
        var reveal = false; var correct = -1; var isOpen = true
        var left = -1; var seconds = 30; var players = 0
        var qIndex = 0; var qCount = 0
        var url = ""; var qr: NSImage?
        var top: [(name: String, score: Int, last: Int)] = []
        var showScores = false

        private let colors: [NSColor] = [
            NSColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1), NSColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1),
            NSColor(red: 0.92, green: 0.70, blue: 0.03, alpha: 1), NSColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1),
            NSColor(red: 0.66, green: 0.33, blue: 0.97, alpha: 1), NSColor(red: 0.98, green: 0.45, blue: 0.09, alpha: 1)]

        override var isFlipped: Bool { true }
        private func px(_ v: CGFloat) -> CGFloat { v * bounds.height / 1080 }

        override func draw(_ r: NSRect) {
            NSColor(red: 0.07, green: 0.08, blue: 0.14, alpha: 1).setFill(); bounds.fill()
            if showScores { drawScores(); return }
            let n = max(2, max(options.count, counts.count))
            let total = counts.reduce(0, +)

            // question
            let title = (qCount > 1 ? "(\(qIndex)/\(qCount))  " : "") + (question.isEmpty ? "🗳️  Quiz" : question)
            draw(title, size: px(50), weight: .bold, color: .white,
                 in: CGRect(x: px(40), y: px(30), width: bounds.width - px(80), height: px(130)), center: true)

            // countdown ring
            if left >= 0, isOpen, let ctx = NSGraphicsContext.current?.cgContext {
                let d = px(110), m = px(26)
                let box = CGRect(x: bounds.maxX - d - m, y: m, width: d, height: d)
                ctx.setLineWidth(px(9))
                ctx.setStrokeColor(NSColor(white: 1, alpha: 0.22).cgColor)
                ctx.strokeEllipse(in: box)
                ctx.setStrokeColor((left <= 5 ? NSColor.systemRed : NSColor(red: 0.31, green: 0.49, blue: 1, alpha: 1)).cgColor)
                let frac = CGFloat(left) / CGFloat(max(1, seconds))
                ctx.addArc(center: CGPoint(x: box.midX, y: box.midY), radius: d / 2,
                           startAngle: -.pi / 2, endAngle: -.pi / 2 + 2 * .pi * frac, clockwise: false)
                ctx.strokePath()
                draw("\(left)", size: px(42), weight: .bold, color: .white, in: box, center: true)
            }

            // how to join
            var y = px(200)
            if let qr {
                draw("Scan & type your name", size: px(24), weight: .bold, color: .white,
                     in: CGRect(x: px(60), y: y, width: px(320), height: px(34)), center: false)
                let side = px(230)
                NSColor.white.setFill()
                NSRect(x: px(60), y: y + px(42), width: side, height: side).fill()
                qr.draw(in: NSRect(x: px(70), y: y + px(52), width: side - px(20), height: side - px(20)))
                draw(url, size: px(22), weight: .bold, color: NSColor(red: 0.5, green: 0.66, blue: 1, alpha: 1),
                     in: CGRect(x: px(60), y: y + side + px(52), width: px(420), height: px(30)), center: false)
                y += side + px(110)
            }

            // answers
            let rx = px(420), rw = bounds.width - rx - px(70)
            draw("👥 \(players) students   ·   ✍️ \(total) answered" + (isOpen ? "" : "   ·   closed"),
                 size: px(30), weight: .bold, color: .white,
                 in: CGRect(x: rx, y: px(190), width: rw, height: px(40)), center: false)
            let top0 = px(256), gap = px(12)
            let barH = min(px(110), (bounds.height - top0 - px(50) - gap * CGFloat(n - 1)) / CGFloat(n))
            for i in 0..<n {
                let yy = top0 + CGFloat(i) * (barH + gap)
                let color = colors[i % colors.count]
                color.setFill()
                NSRect(x: rx, y: yy, width: barH, height: barH).fill()
                draw(String(UnicodeScalar(65 + i)!), size: barH * 0.42, weight: .heavy, color: .white,
                     in: CGRect(x: rx, y: yy, width: barH, height: barH), center: true)
                let bx = rx + barH + px(12), bw = rw - barH - px(12)
                NSColor(white: 1, alpha: 0.14).setFill()
                NSRect(x: bx, y: yy, width: bw, height: barH).fill()
                if reveal {
                    let share = total > 0 ? CGFloat(counts[min(i, counts.count - 1)]) / CGFloat(total) : 0
                    let right = correct == i
                    (right ? NSColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1)
                           : color.withAlphaComponent(correct >= 0 ? 0.35 : 0.9)).setFill()
                    NSRect(x: bx, y: yy, width: max(px(4), bw * share), height: barH).fill()
                }
                var label = i < options.count ? options[i] : ""
                if reveal {
                    let c = counts.count > i ? counts[i] : 0
                    let pct = total > 0 ? Int((Double(c) * 100 / Double(total)).rounded()) : 0
                    label += "   \(c) · \(pct)%" + (correct == i ? "  ✓" : "")
                }
                draw(label, size: barH * 0.30, weight: .bold, color: .white,
                     in: CGRect(x: bx + px(16), y: yy, width: bw - px(24), height: barH), center: false, middle: true)
            }
        }

        private func drawScores() {
            draw("🏆  Scores", size: px(58), weight: .heavy, color: .white,
                 in: CGRect(x: 0, y: px(50), width: bounds.width, height: px(90)), center: true)
            if top.isEmpty {
                draw("No answers yet", size: px(28), weight: .regular, color: NSColor(white: 0.7, alpha: 1),
                     in: CGRect(x: 0, y: bounds.midY, width: bounds.width, height: px(40)), center: true)
                return
            }
            let medals = ["🥇", "🥈", "🥉"]
            let rowH = min(px(96), (bounds.height - px(220)) / CGFloat(top.count))
            for (i, t) in top.enumerated() {
                let box = CGRect(x: bounds.width * 0.18, y: px(180) + CGFloat(i) * rowH,
                                 width: bounds.width * 0.64, height: rowH - px(10))
                NSColor(white: 1, alpha: i == 0 ? 0.22 : 0.10).setFill()
                box.fill()
                draw((i < 3 ? medals[i] + "  " : "\(i + 1).  ") + t.name, size: rowH * 0.42, weight: .bold,
                     color: .white, in: box.insetBy(dx: px(20), dy: 0), center: false, middle: true)
                draw("\(t.score)", size: rowH * 0.42, weight: .heavy,
                     color: i == 0 ? NSColor(red: 0.98, green: 0.75, blue: 0.14, alpha: 1) : .white,
                     in: box.insetBy(dx: px(20), dy: 0), center: false, middle: true, right: true)
            }
        }

        private func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor,
                          in rect: CGRect, center: Bool, middle: Bool = false, right: Bool = false) {
            let style = NSMutableParagraphStyle()
            style.alignment = right ? .right : (center ? .center : .natural)
            style.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color, .paragraphStyle: style]
            let s = NSAttributedString(string: text, attributes: attrs)
            var r = rect
            if middle || center { r.origin.y += (rect.height - s.size().height) / 2 }
            s.draw(in: r)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────
//  📷 Document camera (live from the phone) · 📸 Group photos
// ─────────────────────────────────────────────────────────────────────
final class CameraWindow: FullScreen {
    private let imageView = NSImageView()
    init() {
        super.init(frame: .zero)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.autoresizingMask = [.width, .height]
        let host = NSView()
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        host.addSubview(imageView)
        contentView = host
    }
    func show(_ image: NSImage, rotation: Int, fill: Bool) {
        imageView.frame = contentView?.bounds ?? .zero
        imageView.imageScaling = fill ? .scaleProportionallyUpOrDown : .scaleProportionallyDown
        imageView.image = rotation == 0 ? image : CameraWindow.rotate(image, degrees: rotation)
        orderFrontRegardless()
    }
    static func rotate(_ image: NSImage, degrees: Int) -> NSImage {
        let radians = CGFloat(degrees) * .pi / 180
        let swap = degrees == 90 || degrees == 270
        let size = swap ? NSSize(width: image.size.height, height: image.size.width) : image.size
        let out = NSImage(size: size)
        out.lockFocus()
        let t = NSAffineTransform()
        t.translateX(by: size.width / 2, yBy: size.height / 2)
        t.rotate(byRadians: radians)
        t.translateX(by: -image.size.width / 2, yBy: -image.size.height / 2)
        t.concat()
        image.draw(at: .zero, from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1)
        out.unlockFocus()
        return out
    }
}

/// 📸 All the group photos together, or one at a time.
final class GalleryWindow: FullScreen {
    private let view = GalleryView()
    init() { super.init(frame: .zero); contentView = view }
    var count: Int { view.shots.count }
    var index: Int { get { view.index } set { view.index = newValue; view.needsDisplay = true } }
    var single: Bool { get { view.single } set { view.single = newValue; view.needsDisplay = true } }
    var key: String { view.single ? "shot:\(view.index)" : "shots" }
    func add(_ image: NSImage, caption: String) {
        view.shots.append((image, caption)); view.index = view.shots.count - 1; view.needsDisplay = true
    }
    func clear() { view.shots.removeAll(); view.index = 0; view.needsDisplay = true }
    func next() { guard !view.shots.isEmpty else { return }; view.index = (view.index + 1) % view.shots.count; view.needsDisplay = true }
    func prev() { guard !view.shots.isEmpty else { return }; view.index = (view.index - 1 + view.shots.count) % view.shots.count; view.needsDisplay = true }

    final class GalleryView: NSView {
        var shots: [(image: NSImage, caption: String)] = []
        var index = 0
        var single = true
        override var isFlipped: Bool { true }
        override func draw(_ r: NSRect) {
            NSColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1).setFill(); bounds.fill()
            guard !shots.isEmpty else {
                let s = NSAttributedString(string: "📸  Take photos with the phone camera", attributes: [
                    .font: NSFont.systemFont(ofSize: bounds.height / 28),
                    .foregroundColor: NSColor(white: 0.6, alpha: 1)])
                s.draw(at: CGPoint(x: (bounds.width - s.size().width) / 2, y: bounds.midY))
                return
            }
            if single {
                draw(shots[min(index, shots.count - 1)], in: bounds.insetBy(dx: bounds.width * 0.03, dy: bounds.height * 0.04), marked: false)
                return
            }
            let n = shots.count
            let cols = n <= 1 ? 1 : n <= 4 ? 2 : n <= 9 ? 3 : 4
            let rows = Int(ceil(Double(n) / Double(cols)))
            let gap = bounds.height / 60, m = bounds.height / 45
            let cw = (bounds.width - 2 * m - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let ch = (bounds.height - 2 * m - gap * CGFloat(rows - 1)) / CGFloat(rows)
            for (i, shot) in shots.enumerated() {
                let cell = CGRect(x: m + CGFloat(i % cols) * (cw + gap), y: m + CGFloat(i / cols) * (ch + gap), width: cw, height: ch)
                draw(shot, in: cell, marked: i == index)
            }
        }
        private func draw(_ shot: (image: NSImage, caption: String), in area: CGRect, marked: Bool) {
            let capH = shot.caption.isEmpty ? 0 : area.height * 0.11
            let pic = CGRect(x: area.minX, y: area.minY, width: area.width, height: area.height - capH)
            let s = min(pic.width / max(1, shot.image.size.width), pic.height / max(1, shot.image.size.height))
            let w = shot.image.size.width * s, h = shot.image.size.height * s
            let r = CGRect(x: pic.midX - w / 2, y: pic.midY - h / 2, width: w, height: h)
            shot.image.draw(in: r)
            if marked {
                NSColor(red: 0.31, green: 0.49, blue: 1, alpha: 1).setStroke()
                let p = NSBezierPath(rect: r); p.lineWidth = area.height / 120; p.stroke()
            }
            guard !shot.caption.isEmpty else { return }
            let f = NSFont.systemFont(ofSize: max(11, capH * 0.5), weight: .bold)
            let t = NSAttributedString(string: shot.caption, attributes: [.font: f, .foregroundColor: NSColor.white])
            t.draw(at: CGPoint(x: area.midX - t.size().width / 2, y: area.maxY - capH + capH * 0.2))
        }
    }
}
