import Foundation
import AppKit

/// Drives PowerPoint (or Keynote) on the Mac through AppleScript, and moves the
/// real mouse and keyboard — the Mac twin of the Windows COM + SendInput code.
final class Presenter {
    enum App: String { case powerPoint = "Microsoft PowerPoint", keynote = "Keynote", none = "" }

    private(set) var app: App = .none
    private(set) var slide = 0
    private(set) var total = 0
    private(set) var presenting = false
    private(set) var docName = ""
    private(set) var notes = ""

    // ── AppleScript ────────────────────────────────────────────────────
    @discardableResult
    private func run(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if error != nil { return nil }
        return result?.stringValue
    }

    private func isRunning(_ name: String) -> Bool {
        !NSWorkspace.shared.runningApplications.filter { $0.localizedName == name }.isEmpty
    }

    /// Which presentation app to talk to right now.
    private func pick() -> App {
        if isRunning(App.powerPoint.rawValue) { return .powerPoint }
        if isRunning(App.keynote.rawValue) { return .keynote }
        return .none
    }

    // ── the slide show ─────────────────────────────────────────────────
    func next() {
        switch pick() {
        case .powerPoint:
            run("""
            tell application "Microsoft PowerPoint"
              if (count of slide show windows) > 0 then
                go to next slide slide show view of slide show window 1
              else
                tell application "System Events" to key code 124
              end if
            end tell
            """)
        case .keynote:
            run("tell application \"Keynote\" to show next")
        case .none:
            Input.key(0x7C)   // right arrow — works for PDFs, browsers…
        }
    }

    func previous() {
        switch pick() {
        case .powerPoint:
            run("""
            tell application "Microsoft PowerPoint"
              if (count of slide show windows) > 0 then
                go to previous slide slide show view of slide show window 1
              else
                tell application "System Events" to key code 123
              end if
            end tell
            """)
        case .keynote:
            run("tell application \"Keynote\" to show previous")
        case .none:
            Input.key(0x7B)   // left arrow
        }
    }

    func goTo(_ n: Int) {
        switch pick() {
        case .powerPoint:
            run("tell application \"Microsoft PowerPoint\" to go to slide (slide show view of slide show window 1) number \(n)")
        case .keynote:
            run("tell application \"Keynote\" to tell front document to show slide \(n)")
        case .none: break
        }
    }

    func start(fromCurrent: Bool) {
        switch pick() {
        case .powerPoint:
            run("""
            tell application "Microsoft PowerPoint"
              activate
              if (count of slide show windows) = 0 then run slide show slide show settings of active presentation
            end tell
            """)
        case .keynote:
            run("tell application \"Keynote\" to start front document" + (fromCurrent ? " from current slide" : ""))
        case .none: break
        }
    }

    func end() {
        switch pick() {
        case .powerPoint: run("tell application \"Microsoft PowerPoint\" to exit slide show slide show view of slide show window 1")
        case .keynote: run("tell application \"Keynote\" to stop front document")
        case .none: Input.key(0x35)   // esc
        }
    }

    /// Black or white screen (PowerPoint's own B / W keys).
    func screen(_ mode: String) {
        NSWorkspace.shared.runningApplications.first { $0.localizedName == pick().rawValue }?
            .activate(options: [])
        Input.key(mode == "white" ? 0x0D : 0x0B)   // W : B
    }

    /// Where the slide show is on screen (for the laser, spotlight and pen).
    var showFrame: CGRect {
        NSScreen.screens.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })?.frame
            ?? NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    /// Reads where we are in the deck (slide number, total, notes).
    func refresh() {
        app = pick()
        switch app {
        case .powerPoint:
            presenting = (run("tell application \"Microsoft PowerPoint\" to return (count of slide show windows)") ?? "0") != "0"
            slide = Int(run("""
              tell application "Microsoft PowerPoint"
                if (count of slide show windows) > 0 then
                  return slide index of slide of slide show view of slide show window 1
                else
                  return slide index of slide of view of document window 1
                end if
              end tell
              """) ?? "0") ?? 0
            total = Int(run("tell application \"Microsoft PowerPoint\" to return count of slides of active presentation") ?? "0") ?? 0
            docName = run("tell application \"Microsoft PowerPoint\" to return name of active presentation") ?? ""
            notes = run("""
              tell application "Microsoft PowerPoint"
                try
                  return content of text range of text frame of notes placeholder of notes page of slide \(max(1, slide)) of active presentation
                on error
                  return ""
                end try
              end tell
              """) ?? ""
        case .keynote:
            presenting = (run("tell application \"Keynote\" to return playing") ?? "false") == "true"
            slide = Int(run("tell application \"Keynote\" to return slide number of current slide of front document") ?? "0") ?? 0
            total = Int(run("tell application \"Keynote\" to return count of slides of front document") ?? "0") ?? 0
            docName = run("tell application \"Keynote\" to return name of front document") ?? ""
            notes = run("tell application \"Keynote\" to return presenter notes of current slide of front document") ?? ""
        case .none:
            presenting = false; slide = 0; total = 0; docName = ""; notes = ""
        }
    }

    var statusLine: String {
        switch app {
        case .none: return "No presentation app running"
        case .powerPoint, .keynote:
            return presenting ? "Presenting “\(docName)” — slide \(slide) of \(total)"
                              : "Open: “\(docName)” (not presenting)"
        }
    }
}
