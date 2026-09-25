import Foundation
import CoreGraphics
import AppKit
import ApplicationServices

/// Mouse and keyboard, the Mac way (needs the one-time Accessibility permission).
enum Input {
    private static var down = false

    static func moveRelative(dx: Double, dy: Double) {
        guard let p = CGEvent(source: nil)?.location else { return }
        moveAbsolute(x: p.x + dx, y: p.y + dy)
    }

    static func moveAbsolute(x: Double, y: Double) {
        let pt = CGPoint(x: x, y: y)
        let type: CGEventType = down ? .leftMouseDragged : .mouseMoved
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    static func button(_ which: String, _ action: String) {
        guard let p = CGEvent(source: nil)?.location else { return }
        let isRight = which == "right"
        let downType: CGEventType = isRight ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = isRight ? .rightMouseUp : .leftMouseUp
        let btn: CGMouseButton = isRight ? .right : .left
        func post(_ t: CGEventType, clicks: Int64 = 1) {
            let e = CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: btn)
            e?.setIntegerValueField(.mouseEventClickState, value: clicks)
            e?.post(tap: .cghidEventTap)
        }
        switch action {
        case "down": down = !isRight; post(downType)
        case "up": down = false; post(upType)
        case "click": post(downType); post(upType)
        case "dblclick": post(downType); post(upType); post(downType, clicks: 2); post(upType, clicks: 2)
        default: break
        }
    }

    static func scroll(_ steps: Int) {
        CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(steps), wheel2: 0, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    static func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
        let d = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
        let u = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
        d?.flags = flags; u?.flags = flags
        d?.post(tap: .cghidEventTap); u?.post(tap: .cghidEventTap)
    }

    /// Types any text — Kurdish, Arabic, English — into whatever is in front.
    static func type(_ text: String) {
        for ch in text.unicodeScalars {
            if ch == "\n" { key(0x24); continue }   // return
            var units = Array(String(ch).utf16)
            let d = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            let u = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            d?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            u?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            d?.post(tap: .cghidEventTap); u?.post(tap: .cghidEventTap)
        }
    }

    /// Named keys from the phone's keyboard bar.
    static func named(_ name: String, ctrl: Bool, shift: Bool, alt: Bool, cmd: Bool, repeatCount: Int) {
        let map: [String: CGKeyCode] = [
            "enter": 0x24, "backspace": 0x33, "tab": 0x30, "esc": 0x35, "space": 0x31,
            "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
            "delete": 0x75, "home": 0x73, "end": 0x77, "pageup": 0x74, "pagedown": 0x79,
            "a": 0x00, "c": 0x08, "v": 0x09, "z": 0x06
        ]
        guard let code = map[name.lowercased()] else { return }
        var flags: CGEventFlags = []
        // on a Mac, Copy / Paste / Undo / Select-all use ⌘, not Ctrl
        if ctrl || cmd { flags.insert(.maskCommand) }
        if shift { flags.insert(.maskShift) }
        if alt { flags.insert(.maskAlternate) }
        for _ in 0..<max(1, min(repeatCount, 200)) { key(code, flags: flags) }
    }

    /// Asks for the Accessibility permission the first time (mouse/keyboard control).
    @discardableResult
    static func ensurePermission() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
