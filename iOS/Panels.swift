import SwiftUI

/// ⌨️ Type on the computer from the phone — any language, including Kurdish.
struct KeyboardSheet: View {
    @ObservedObject var link: Link
    @ObservedObject var lang = L.shared
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                TextField(lang.t("type"), text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder).font(.title3)
                    .focused($focused)
                    .onChange(of: text) { new in
                        // send what changed, so the computer types along with you
                        if new.count > sent.count, new.hasPrefix(sent) {
                            link.send(["c": "type", "text": String(new.dropFirst(sent.count))])
                        } else if new.count < sent.count {
                            link.send(["c": "key", "k": "backspace", "n": sent.count - new.count])
                        }
                        sent = new
                    }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        key("⏎", "enter"); key("⌫", "backspace"); key("Esc", "esc"); key("Tab", "tab")
                        key("←", "left"); key("↑", "up"); key("↓", "down"); key("→", "right")
                        Button("⌘A") { link.send(["c": "key", "k": "a", "win": true]) }
                        Button("⌘C") { link.send(["c": "key", "k": "c", "win": true]) }
                        Button("⌘V") { link.send(["c": "key", "k": "v", "win": true]) }
                        Button("⌘Z") { link.send(["c": "key", "k": "z", "win": true]) }
                    }.font(.callout).buttonStyle(.bordered)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("⌨️ " + lang.t("keyboard"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("✕") { dismiss() } } }
            .onAppear { focused = true }
        }
    }

    @State private var sent = ""
    private func key(_ label: String, _ name: String) -> some View {
        Button(label) { link.send(["c": "key", "k": name]) }
    }
}

/// ⌛ The timer panel: count down or up, and show it on the projector.
struct TimerSheet: View {
    @ObservedObject var link: Link
    @ObservedObject var lang = L.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage("timerMinutes") private var minutes = 10
    @AppStorage("timerUp") private var countUp = false
    @AppStorage("timerOnProjector") private var onProjector = true

    var body: some View {
        NavigationStack {
            Form {
                Picker("", selection: $countUp) {
                    Text(lang.t("countDown")).tag(false)
                    Text(lang.t("countUp")).tag(true)
                }.pickerStyle(.segmented)
                if !countUp {
                    Stepper("\(lang.t("minutes")): \(minutes)", value: $minutes, in: 1...180)
                }
                Toggle(lang.t("onProjector"), isOn: $onProjector)
                HStack {
                    Button(lang.t("startTimer")) { link.startTimer(minutes: countUp ? 0 : minutes, up: countUp, show: onProjector) }
                        .buttonStyle(.borderedProminent)
                    Button(lang.t("pause")) { link.pauseTimer() }.buttonStyle(.bordered)
                    Button(lang.t("reset")) { link.resetTimer() }.buttonStyle(.bordered)
                }
            }
            .navigationTitle("⌛ " + lang.t("timer"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("✕") { dismiss() } } }
        }
    }
}

/// 🎨 How each tool looks: sizes, colours, spotlight styles, lens brightness.
struct ToolSettings: View {
    @ObservedObject var link: Link
    @ObservedObject var lang = L.shared
    let tool: Tool
    @AppStorage("laserSize") private var laserSize = 16.0
    @AppStorage("laserColor") private var laserColor = "#ef4444"
    @AppStorage("spotRadius") private var spotRadius = 160.0
    @AppStorage("spotStyle") private var spotStyle = "stage"
    @AppStorage("lensRadius") private var lensRadius = 140.0
    @AppStorage("lensZoom") private var lensZoom = 2.0
    @AppStorage("lensBright") private var lensBright = 88.0
    @AppStorage("lensDim") private var lensDim = false
    @AppStorage("penSize") private var penSize = 5.0
    @AppStorage("penColor") private var penColor = "#ef4444"
    @AppStorage("markSize") private var markSize = 28.0

    private let palette = ["#ef4444", "#3b82f6", "#22c55e", "#eab308", "#a855f7", "#ffffff", "#111111"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                switch tool {
                case .laser:
                    slider(lang.t("size"), $laserSize, 8...48) { link.send(["c": "laser_style", "size": laserSize]) }
                    colors($laserColor) { link.send(["c": "laser_style", "color": laserColor]) }
                case .spotlight:
                    slider(lang.t("size"), $spotRadius, 60...400) { link.send(["c": "spot_style", "radius": spotRadius]) }
                    ForEach(SpotStyle.allCases, id: \.self) { s in
                        Button(s.label) { spotStyle = s.rawValue; link.send(["c": "spot_style", "style": s.rawValue]) }
                            .tint(spotStyle == s.rawValue ? .blue : .gray)
                    }
                case .lens:
                    slider(lang.t("size"), $lensRadius, 60...400) { link.send(["c": "lens_style", "radius": lensRadius]) }
                    ForEach([1.5, 2.0, 2.5, 3.0, 4.0], id: \.self) { z in
                        Button(String(format: "%.1f×", z)) { lensZoom = z; link.send(["c": "lens_style", "zoom": z]) }
                            .tint(abs(lensZoom - z) < 0.01 ? .blue : .gray)
                    }
                    slider(lang.t("brightness"), $lensBright, 40...100) { link.send(["c": "lens_style", "bright": lensBright]) }
                    Toggle(lang.t("dimAround"), isOn: $lensDim).labelsHidden()
                        .onChange(of: lensDim) { v in link.send(["c": "lens_style", "dim": v]) }
                case .pen, .highlighter:
                    slider(lang.t("size"), $penSize, 1...30) { }
                    colors($penColor) { link.send(["c": "color", "rgb": penColor]) }
                case .number, .text:
                    slider(lang.t("size"), $markSize, 12...64) { }
                default:
                    EmptyView()
                }
            }
            .font(.caption).buttonStyle(.bordered)
        }
    }

    private func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        _ send: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Slider(value: value, in: range) { editing in if !editing { send() } }.frame(width: 120)
        }
    }

    private func colors(_ value: Binding<String>, _ send: @escaping () -> Void) -> some View {
        ForEach(palette, id: \.self) { hex in
            Button {
                value.wrappedValue = hex
                send()
            } label: {
                Circle().fill(Color(hex: hex)).frame(width: 22, height: 22)
                    .overlay(Circle().stroke(.white, lineWidth: value.wrappedValue == hex ? 2 : 0))
            }.buttonStyle(.plain)
        }
    }
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = Int(s, radix: 16) ?? 0
        self.init(.sRGB, red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255,
                  blue: Double(v & 255) / 255, opacity: 1)
    }
}

/// 🔢 Jump straight to a slide.
struct GoToSheet: View {
    @ObservedObject var link: Link
    @Environment(\.dismiss) private var dismiss
    @State private var number = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(L.shared.t("goto")) {
                    TextField("1 … \(max(1, link.total))", text: $number).keyboardType(.numberPad).font(.title2)
                    Button("▶") {
                        if let n = Int(number), n > 0 { link.send(["c": "goto", "n": n]); dismiss() }
                    }
                }
                if !link.slideTitles.isEmpty {
                    Section {
                        ForEach(Array(link.slideTitles.enumerated()), id: \.offset) { i, title in
                            Button("\(i + 1).  \(title)") { link.send(["c": "goto", "n": i + 1]); dismiss() }
                        }
                    }
                } else if link.total > 0 {
                    Section {
                        ForEach(1...max(1, link.total), id: \.self) { n in
                            Button("\(L.shared.t("slide")) \(n)") { link.send(["c": "goto", "n": n]); dismiss() }
                        }
                    }
                }
            }
            .navigationTitle(L.shared.t("goto"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("✕") { dismiss() } } }
        }
    }
}
