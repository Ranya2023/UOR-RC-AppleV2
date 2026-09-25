import AppKit

/// A see-through window over the slide show that draws what Keynote/PowerPoint
/// cannot: the laser, the spotlight, the magnifier and the pen — the Mac twin of
/// the Windows overlay. Clicks pass straight through to the presentation.
final class Overlay {
    private var window: NSWindow?
    private let view = OverlayView()

    func place(on frame: CGRect) {
        if window == nil {
            let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = true                       // click-through
            w.level = .screenSaver                            // above a full-screen slide show
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.contentView = view
            w.orderFrontRegardless()
            window = w
        }
        if window?.frame != frame { window?.setFrame(frame, display: true) }
        view.stage = CGRect(origin: .zero, size: frame.size)
    }

    func hide() { window?.orderOut(nil) }
    func show() { window?.orderFrontRegardless() }
    var state: OverlayView { view }
    func refresh() { view.needsDisplay = true }
}

/// Everything the overlay can draw. Values arrive from the phone, 0…1 across the slide.
final class OverlayView: NSView {
    var stage: CGRect = .zero

    var laserOn = false; var laser = CGPoint(x: 0.5, y: 0.5)
    var laserSize: CGFloat = 16; var laserColor = NSColor.systemRed; var laserLabel = ""
    var spotOn = false; var spot = CGPoint(x: 0.5, y: 0.5)
    var spotRadius: CGFloat = 160; var spotStyle = "stage"
    var lensOn = false; var lens = CGPoint(x: 0.5, y: 0.5)
    var lensRadius: CGFloat = 140; var lensZoom: CGFloat = 2; var lensBright: CGFloat = 0.88; var lensDim = false
    var strokes: [Stroke] = []; var current: Stroke?
    var marks: [Mark] = []            // 🔢 numbers and 📍 text labels

    struct Mark { var kind: String; var x: CGFloat; var y: CGFloat; var text: String; var color: NSColor; var size: CGFloat }
    var timerText: String?; var timerUrgent = false
    var zoom: CGFloat = 1; var zoomX: CGFloat = 0.5; var zoomY: CGFloat = 0.5    // 🔍 projector zoom
    var preview: Mark?                                                          // the mark being placed
    var flash: Date?                                                            // ⏰ time's-up flash

    struct Stroke { var points: [CGPoint]; var color: NSColor; var width: CGFloat; var highlight: Bool }

    override var isFlipped: Bool { true }

    private func px(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * bounds.width, y: p.y * bounds.height) }
    private func css(_ v: CGFloat) -> CGFloat { v * bounds.height / 1080 }

    override func draw(_ dirty: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        // ── 🔍 projector zoom: the screen itself, magnified ──
        if zoom > 1.01, let shot = screenshotBehind() {
            let w = bounds.width / zoom, h = bounds.height / zoom
            let x = (bounds.width - w) * zoomX, y = (bounds.height - h) * zoomY
            let sx = CGFloat(shot.width) / bounds.width, sy = CGFloat(shot.height) / bounds.height
            if let part = shot.cropping(to: CGRect(x: x * sx, y: y * sy, width: w * sx, height: h * sy)) {
                ctx.draw(part, in: bounds)
            }
        }

        // ── ink (under everything else) ──
        for s in strokes + (current.map { [$0] } ?? []) { draw(stroke: s, in: ctx) }

        // ── numbers and text labels ──
        for m in marks { draw(mark: m, in: ctx) }
        if let p = preview {
            ctx.saveGState(); ctx.setAlpha(0.55); draw(mark: p, in: ctx); ctx.restoreGState()
        }

        // ── spotlight ──
        if spotOn {
            let c = px(spot), r = css(spotRadius)
            let outer: CGFloat = spotStyle == "minimal" ? 0.35 : spotStyle == "stage" ? 0.97 : 0.78
            ctx.saveGState()
            ctx.setFillColor(NSColor.black.withAlphaComponent(outer).cgColor)
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.addPath(path)
            ctx.fillPath(using: .evenOdd)
            if spotStyle == "neon" || spotStyle == "colorful" || spotStyle == "celebration" {
                ctx.setStrokeColor((spotStyle == "neon" ? NSColor.systemTeal : NSColor.systemOrange).cgColor)
                ctx.setLineWidth(css(4))
                ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            }
            ctx.restoreGState()
        }

        // ── magnifier ──
        if lensOn, let shot = screenshotBehind() {
            let c = px(lens), r = css(lensRadius)
            let circle = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            if lensDim {
                ctx.saveGState()
                let p = CGMutablePath(); p.addRect(bounds); p.addEllipse(in: circle)
                ctx.addPath(p); ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor); ctx.fillPath(using: .evenOdd)
                ctx.restoreGState()
            }
            ctx.saveGState()
            ctx.addEllipse(in: circle); ctx.clip()
            let side = r * 2 / lensZoom
            let src = CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side)
            if let cropped = shot.cropping(to: CGRect(x: src.minX * scaleX(shot), y: src.minY * scaleY(shot),
                                                      width: src.width * scaleX(shot), height: src.height * scaleY(shot))) {
                ctx.setAlpha(lensBright)
                ctx.draw(cropped, in: circle)
                ctx.setAlpha(1)
            }
            ctx.restoreGState()
            ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(css(4)); ctx.strokeEllipse(in: circle)
        }

        // ── laser ──
        if laserOn {
            let c = px(laser), s = css(laserSize)
            ctx.setShadow(offset: .zero, blur: s * 1.6, color: laserColor.withAlphaComponent(0.9).cgColor)
            ctx.setFillColor(laserColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s))
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
        }
        if !laserLabel.isEmpty {
            let c = px(laser)
            let f = NSFont.systemFont(ofSize: css(26), weight: .bold)
            let text = NSAttributedString(string: laserLabel, attributes: [.font: f, .foregroundColor: NSColor.black])
            let size = text.size()
            let box = CGRect(x: c.x + css(14), y: c.y - size.height / 2 - css(6),
                             width: size.width + css(24), height: size.height + css(12))
            let bg = NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2)
            laserColor.setFill(); bg.fill()
            text.draw(at: CGPoint(x: box.minX + css(12), y: box.minY + css(6)))
        }

        // ── ⏰ the time-is-up flash ──
        if let f = flash, Date().timeIntervalSince(f) < 0.8 {
            ctx.setFillColor(NSColor.systemOrange.withAlphaComponent(0.35).cgColor)
            ctx.fill(bounds)
        }

        // ── timer ──
        if let t = timerText {
            let f = NSFont.monospacedDigitSystemFont(ofSize: css(30), weight: .bold)
            let text = NSAttributedString(string: t, attributes: [.font: f, .foregroundColor: NSColor.white])
            let size = text.size()
            let box = CGRect(x: bounds.maxX - size.width - css(60), y: bounds.maxY - size.height - css(50),
                             width: size.width + css(40), height: size.height + css(20))
            (timerUrgent ? NSColor.systemOrange : NSColor.black.withAlphaComponent(0.7)).setFill()
            NSBezierPath(roundedRect: box, xRadius: css(16), yRadius: css(16)).fill()
            text.draw(at: CGPoint(x: box.minX + css(20), y: box.minY + css(10)))
        }
    }

    private func draw(mark m: Mark, in ctx: CGContext) {
        let p = px(CGPoint(x: m.x, y: m.y))
        if m.kind == "number" {
            let d = css(m.size * 36 / 28)
            let box = CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)
            ctx.setFillColor(m.color.cgColor); ctx.fillEllipse(in: box)
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor); ctx.setLineWidth(css(2)); ctx.strokeEllipse(in: box)
            let f = NSFont.systemFont(ofSize: max(css(12), d * 0.44), weight: .heavy)
            let t = NSAttributedString(string: m.text, attributes: [.font: f, .foregroundColor: NSColor.white])
            t.draw(at: CGPoint(x: p.x - t.size().width / 2, y: p.y - t.size().height / 2))
        } else {
            let f = NSFont.systemFont(ofSize: css(m.size * 36 / 28), weight: .bold)
            let t = NSAttributedString(string: m.text, attributes: [.font: f, .foregroundColor: NSColor.black])
            let size = t.size()
            let box = CGRect(x: p.x - size.width * 0.08 - css(10), y: p.y - size.height * 1.1 - css(6),
                             width: size.width + css(20), height: size.height + css(12))
            m.color.setFill()
            NSBezierPath(roundedRect: box, xRadius: css(8), yRadius: css(8)).fill()
            t.draw(at: CGPoint(x: box.minX + css(10), y: box.minY + css(6)))
        }
    }

    private func draw(stroke s: Stroke, in ctx: CGContext) {
        guard s.points.count > 1 else { return }
        ctx.saveGState()
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.setLineWidth(max(1, css(s.width)))
        ctx.setStrokeColor(s.color.withAlphaComponent(s.highlight ? 0.42 : 1).cgColor)
        ctx.beginPath()
        ctx.move(to: px(s.points[0]))
        for p in s.points.dropFirst() { ctx.addLine(to: px(p)) }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // the magnifier needs a picture of what is under it
    private var cache: CGImage?
    private var cacheAt = Date.distantPast
    private func screenshotBehind() -> CGImage? {
        if Date().timeIntervalSince(cacheAt) < 0.2, let c = cache { return c }
        guard let screen = window?.screen ?? NSScreen.main else { return nil }
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
        cache = CGDisplayCreateImage(id)      // needs the Screen Recording permission, asked once
        cacheAt = Date()
        return cache
    }
    private func scaleX(_ img: CGImage) -> CGFloat { CGFloat(img.width) / max(1, bounds.width) }
    private func scaleY(_ img: CGImage) -> CGFloat { CGFloat(img.height) / max(1, bounds.height) }
}
