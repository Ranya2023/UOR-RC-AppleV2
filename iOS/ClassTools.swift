import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// 🧑‍🏫 Whiteboard · 🎲 Picker · 🖼 Photos & videos · 📑 Documents — the iPhone side.
struct ClassToolsBar: View {
    @ObservedObject var link: Link
    @State private var showPicker = false
    @State private var showQuiz = false
    @State private var showCamera = false
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var photoItems: [PhotosPickerItem] = []

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button("▶ PowerPoint") { link.send(["c": "back_show"]); link.view = "" }
                    .tint(link.view.isEmpty ? .blue : .gray)
                Button("🧑‍🏫 Whiteboard") {
                    link.send(["c": "board", "a": "open", "v": UserDefaults.standard.string(forKey: "boardBg") ?? "white"])
                }.tint(link.view == "board" ? .blue : .gray)
                Button("🖼 Photos") { showPhotos = true }.tint(link.view == "media" ? .blue : .gray)
                Button("📑 Document") { showFiles = true }.tint(link.view == "doc" ? .blue : .gray)
                Button("🎲 Picker") { showPicker = true }.tint(link.view == "picker" ? .blue : .gray)
                Button("🗳️ Quiz") { showQuiz = true }.tint(link.view == "quiz" ? .blue : .gray)
                Button("📷 Camera") { showCamera = true }.tint(link.view == "phone" ? .blue : .gray)
                HStack(spacing: 2) {
                    Text("📱").font(.caption)
                    BroadcastButton().frame(width: 34, height: 30)
                }
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            .font(.caption).buttonStyle(.bordered)
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: 12)
        .onChange(of: photoItems) { items in
            Task {
                for (i, item) in items.enumerated() {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                        link.sendFile(data: data, name: "photo-\(Int(Date().timeIntervalSince1970))-\(i).\(ext)",
                                      present: true, kind: "", index: i)
                    }
                }
                photoItems = []
            }
        }
        .fileImporter(isPresented: $showFiles,
                      allowedContentTypes: [.pdf, .presentation, UTType("com.microsoft.word.doc") ?? .data, .plainText],
                      allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url) {
                    link.sendFile(data: data, name: url.lastPathComponent, present: true, kind: "doc", index: 0)
                }
            }
        }
        .sheet(isPresented: $showPicker) { PickerSheet(link: link) }
        .sheet(isPresented: $showQuiz) { QuizSheet(link: link) }
        .fullScreenCover(isPresented: $showCamera) { CameraSheet(link: link) }
    }
}

/// The bar that appears while the computer is showing a whiteboard, a document,
/// photos or the picker.
struct ViewBar: View {
    @ObservedObject var link: Link

    var body: some View {
        switch link.view {
        case "board":
            HStack(spacing: 6) {
                Button("◀") { link.send(["c": "prev"]) }
                Button(link.page >= link.pages ? "➕ New page" : "▶") { link.send(["c": "next"]) }
                ForEach(["white", "grid", "black", "green"], id: \.self) { bg in
                    Button(label(bg)) {
                        UserDefaults.standard.set(bg, forKey: "boardBg")
                        link.send(["c": "board", "a": "bg", "v": bg])
                    }.tint(link.boardBg == bg ? .blue : .gray)
                }
                Button("💾") { link.send(["c": "board", "a": "save"]) }
                Button("✕") { link.send(["c": "board", "a": "close"]) }
            }.font(.caption).buttonStyle(.bordered)
        case "doc":
            HStack(spacing: 6) {
                Button("◀") { link.send(["c": "prev"]) }
                Button("▶") { link.send(["c": "next"]) }
                Text("\(link.page) / \(link.pages)").font(.caption)
                Button("✕") { link.send(["c": "doc", "a": "close"]) }
            }.font(.caption).buttonStyle(.bordered)
        case "media":
            HStack(spacing: 6) {
                Button("⏮") { link.send(["c": "media", "a": "prev"]) }
                Button("⏪") { link.send(["c": "media", "a": "rel", "v": -10]) }
                Button("⏯") { link.send(["c": "media", "a": "toggle"]) }
                Button("⏩") { link.send(["c": "media", "a": "rel", "v": 10]) }
                Button("⏭") { link.send(["c": "media", "a": "next"]) }
                Button("🔉") { link.send(["c": "media", "a": "vol", "v": -0.1]) }
                Button("🔊") { link.send(["c": "media", "a": "vol", "v": 0.1]) }
                Button("⛶") { link.send(["c": "media", "a": "fill"]) }
                Button("✕") { link.send(["c": "media", "a": "close"]) }
            }.font(.caption).buttonStyle(.bordered)
        case "quiz":
            QuizBar(link: link)
        case "gallery":
            HStack(spacing: 6) {
                Button("◀") { link.send(["c": "prev"]) }
                Button("▶") { link.send(["c": "next"]) }
                Button("⊞ All") { link.send(["c": "gallery", "a": "grid"]) }
                Button("🔍 One") { link.send(["c": "gallery", "a": "single"]) }
                Button("🗑") { link.send(["c": "gallery", "a": "clear"]) }
                Button("✕") { link.send(["c": "gallery", "a": "close"]) }
            }.font(.caption).buttonStyle(.bordered)
        case "picker":
            HStack(spacing: 6) {
                Text(link.picked.isEmpty ? "🎲 …" : "🎲 " + link.picked).font(.headline)
                Spacer()
                Button("✕") { link.send(["c": "picker", "a": "close"]) }.font(.caption).buttonStyle(.bordered)
            }
        default:
            EmptyView()
        }
    }

    private func label(_ bg: String) -> String {
        switch bg { case "grid": return "▦"; case "black": return "⬛"; case "green": return "🟩"; default: return "⬜" }
    }
}

/// 🎲 Class lists, "no repeats", and the spinning wheel.
struct PickerSheet: View {
    @ObservedObject var link: Link
    @Environment(\.dismiss) private var dismiss
    @AppStorage("pickNames") private var names = ""
    @AppStorage("pickNoRepeat") private var noRepeat = true
    @AppStorage("pickWheel") private var wheel = false
    @State private var pool: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Names — one per line, or type 1-30 for numbers") {
                    TextEditor(text: $names).frame(minHeight: 180)
                }
                Section {
                    Toggle("Don't pick the same student twice", isOn: $noRepeat)
                    Toggle("🎡 Spin a wheel instead of showing names", isOn: $wheel)
                }
                Section {
                    Button("🎲 Pick") { pick() }.disabled(parsed.isEmpty)
                }
            }
            .navigationTitle("🎲 Random picker")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private var parsed: [String] { PickerNames.parse(names) }

    private func pick() {
        let all = parsed
        guard !all.isEmpty else { return }
        var left = pool.filter { all.contains($0) }
        if !noRepeat { left = all } else if left.isEmpty { left = all }
        let winner = left.randomElement() ?? all[0]
        if noRepeat { left.removeAll { $0 == winner }; pool = left }
        link.send(["c": "picker", "a": "pick", "names": all,
                   "winner": all.firstIndex(of: winner) ?? 0,
                   "title": "", "remaining": noRepeat ? left.count : -1,
                   "style": wheel ? "wheel" : "names"])
        dismiss()
    }
}

/// Shared with the Android app: "1-30" → numbers, otherwise one name per line.
enum PickerNames {
    static func parse(_ text: String) -> [String] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let m = t.range(of: "^([0-9]{1,3}) *[-–] *([0-9]{1,3})$", options: .regularExpression), m == t.startIndex..<t.endIndex {
            let parts = t.split(whereSeparator: { "-–".contains($0) }).map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
            if parts.count == 2, parts[1] >= parts[0], parts[1] - parts[0] < 500 {
                return (parts[0]...parts[1]).map(String.init)
            }
        }
        return t.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
