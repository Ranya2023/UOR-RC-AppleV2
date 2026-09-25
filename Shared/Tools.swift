import Foundation

/// The drawing tools, shared by the Mac host and the iPhone remote.
public enum Tool: String, CaseIterable, Codable {
    case mouse, laser, spotlight, lens, pen, highlighter, eraser, number, text

    public var label: String {
        switch self {
        case .mouse: return "🖱 Mouse"
        case .laser: return "🔴 Laser"
        case .spotlight: return "🔦 Spotlight"
        case .lens: return "🔎 Lens"
        case .pen: return "✏️ Pen"
        case .highlighter: return "🖍 Highlight"
        case .eraser: return "🧽 Eraser"
        case .number: return "🔢 Numbers"
        case .text: return "📍 Text"
        }
    }

    public var labelKu: String {
        switch self {
        case .mouse: return "🖱 ماوس"
        case .laser: return "🔴 لێزەر"
        case .spotlight: return "🔦 تیشک"
        case .lens: return "🔎 گەورەبین"
        case .pen: return "✏️ پێنووس"
        case .highlighter: return "🖍 هایلایت"
        case .eraser: return "🧽 پاکەرەوە"
        case .number: return "🔢 ژمارە"
        case .text: return "📍 دەق"
        }
    }

    /// Tools that work on a 1:1 frame of the slide instead of as a trackpad.
    public var isFramed: Bool { self != .mouse }
}

public enum SpotStyle: String, CaseIterable {
    case classic, theater, minimal, glass, stage, neon, celebration, colorful
    public var label: String {
        switch self {
        case .classic: return "🎴 Classic"; case .theater: return "🎭 Theater"
        case .minimal: return "⚪ Minimal"; case .glass: return "🧊 Glass"
        case .stage: return "🔦 Stage"; case .neon: return "💫 Neon"
        case .celebration: return "🎉 Celebrate"; case .colorful: return "🫟 Colorful"
        }
    }
}
