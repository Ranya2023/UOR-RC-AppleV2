import SwiftUI
import UIKit

/// The touchpad, with the same feel as the Android app:
///  • Mouse: drag = move, tap = click, two-finger tap = right-click, two-finger drag = scroll
///  • Laser / Spotlight / Lens: a 16:9 frame that maps 1:1 onto the slide
///  • Pen / Highlighter / Eraser: draw inside that frame
struct Touchpad: UIViewRepresentable {
    let tool: Tool
    let aspect: CGFloat
    var background: UIImage? = nil
    var mirror: Bool = false
    let onEvent: ([String: Any]) -> Void

    func makeUIView(context: Context) -> PadView {
        let v = PadView()
        v.onEvent = onEvent
        return v
    }

    func updateUIView(_ v: PadView, context: Context) {
        v.tool = tool
        v.aspect = aspect
        v.picture = background
        v.mirror = mirror
        v.pencilOnly = UserDefaults.standard.bool(forKey: "pencilOnly")
        v.setNeedsDisplay()
    }
}

final class PadView: UIView {
    var tool: Tool = .mouse { didSet { setNeedsDisplay() } }
    var aspect: CGFloat = 16.0 / 9.0
    var onEvent: (([String: Any]) -> Void)?
    var picture: UIImage?          // the slide, or the computer's screen
    var mirror = false             // tapping the mirrored screen moves the real mouse
    var pencilOnly = false         // ✏️ iPad: ignore fingers while drawing

    private var last = CGPoint.zero
    private var down = CGPoint.zero
    private var downAt = Date()
    private var moved = false
    private var maxTouches = 0
    private var scrollAcc: CGFloat = 0
    private var trail: [CGPoint] = []
    private var pending: [String: Any]?
    private var flushTimer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.08, green: 0.09, blue: 0.14, alpha: 1)
        layer.cornerRadius = 18
        isMultipleTouchEnabled = true
    }
    required init?(coder: NSCoder) { fatalError() }

    // the slide-shaped frame inside the pad
    private var frameRect: CGRect {
        let pad: CGFloat = 8
        var w = bounds.width - pad * 2, h = w / aspect
        if h > bounds.height - pad * 2 { h = bounds.height - pad * 2; w = h * aspect }
        return CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }
    private func nx(_ p: CGPoint) -> Double { Double(min(max((p.x - frameRect.minX) / frameRect.width, 0), 1)) }
    private func ny(_ p: CGPoint) -> Double { Double(min(max((p.y - frameRect.minY) / frameRect.height, 0), 1)) }

    // send at most one move message every 16 ms
    private func queue(_ m: [String: Any]) {
        pending = m
        if flushTimer == nil {
            flushTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.flushTimer = nil
                if let p = self.pending { self.onEvent?(p); self.pending = nil }
            }
        }
    }
    private func flush() {
        flushTimer?.invalidate(); flushTimer = nil
        if let p = pending { onEvent?(p); pending = nil }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        if pencilOnly, tool == .pen || tool == .highlighter, t.type != .pencil { return }
        if mirror { onEvent?(["c": "sabs", "x": nx(t.location(in: self)), "y": ny(t.location(in: self)), "a": "down"]); return }
        let p = t.location(in: self)
        down = p; last = p; downAt = Date(); moved = false
        maxTouches = max(maxTouches, event?.allTouches?.count ?? 1)
        trail = [p]
        switch tool {
        case .laser, .spotlight, .lens: queue(pointer(p, phase: "start"))
        case .pen, .highlighter:
            flush()
            onEvent?(["c": "ink_start", "x": nx(p), "y": ny(p), "hl": tool == .highlighter])
        case .eraser: onEvent?(["c": "ink_erase", "x": nx(p), "y": ny(p)])
        case .number, .text:
            onEvent?(["c": "ann_tap", "kind": tool == .number ? "number" : "text",
                      "x": nx(p), "y": ny(p), "size": 28])
        case .mouse: break
        }
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let all = event?.allTouches?.count ?? 1
        maxTouches = max(maxTouches, all)
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        if mirror { queue(["c": "sabs", "x": nx(p), "y": ny(p), "a": "move"]); last = p; return }
        if hypot(p.x - down.x, p.y - down.y) > 8 { moved = true }
        defer { last = p; setNeedsDisplay() }

        if tool == .mouse {
            if all >= 2 {
                scrollAcc += p.y - last.y
                let step: CGFloat = 36
                if abs(scrollAcc) >= step {
                    let steps = Int(scrollAcc / step)
                    scrollAcc -= CGFloat(steps) * step
                    onEvent?(["c": "scroll", "d": steps])
                }
            } else {
                let k = 2.2
                queue(["c": "rel", "dx": Double(p.x - last.x) * k, "dy": Double(p.y - last.y) * k])
            }
            return
        }
        switch tool {
        case .laser, .spotlight, .lens: queue(pointer(p, phase: "move"))
        case .pen, .highlighter:
            trail.append(p)
            queue(["c": "ink_pts", "p": [nx(p), ny(p)]])
        case .eraser: queue(["c": "ink_erase", "x": nx(p), "y": ny(p)])
        case .number, .text, .mouse: break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let p = touches.first?.location(in: self) ?? last
        flush()
        if mirror { onEvent?(["c": "sabs", "x": nx(p), "y": ny(p), "a": "up"]); return }
        switch tool {
        case .mouse:
            if !moved && Date().timeIntervalSince(downAt) < 0.3 {
                onEvent?(["c": "btn", "b": maxTouches >= 2 ? "right" : "left", "a": "click"])
            }
        case .laser, .spotlight, .lens: onEvent?(pointer(p, phase: "end"))
        case .pen, .highlighter: onEvent?(["c": "ink_end"])
        case .eraser: onEvent?(["c": "ink_erase_end"])
        case .number, .text: break
        }
        maxTouches = 0; scrollAcc = 0
        trail.removeAll()
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    private func pointer(_ p: CGPoint, phase: String) -> [String: Any] {
        let name = tool == .spotlight ? "spot" : tool == .lens ? "lens" : "laser"
        return ["c": name, "x": nx(p), "y": ny(p), "active": phase != "end"]
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        if let img = picture {
            let area = mirror ? bounds : frameRect
            img.draw(in: area, blendMode: .normal, alpha: mirror ? 1 : 0.85)
        }
        ctx.setStrokeColor(UIColor(white: 1, alpha: 0.06).cgColor)
        ctx.setLineWidth(1)
        var x: CGFloat = 28
        while x < bounds.width { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: bounds.height)); x += 28 }
        var y: CGFloat = 28
        while y < bounds.height { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: bounds.width, y: y)); y += 28 }
        ctx.strokePath()
        guard tool.isFramed else { return }
        ctx.setStrokeColor(UIColor(red: 0.31, green: 0.55, blue: 1, alpha: 1).cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(frameRect)
        if trail.count > 1 {
            ctx.setStrokeColor(UIColor.systemRed.cgColor)
            ctx.setLineWidth(3); ctx.setLineCap(.round)
            ctx.move(to: trail[0])
            for p in trail.dropFirst() { ctx.addLine(to: p) }
            ctx.strokePath()
        }
    }
}
