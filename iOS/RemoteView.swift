import SwiftUI

@main
struct UORRCRemoteApp: App {
    @StateObject private var link = Link()
    var body: some Scene {
        WindowGroup {
            RemoteView(link: link).onAppear { link.start(); RemoteBridge.shared.link = link }.preferredColorScheme(.dark)
        }
    }
}

struct RemoteView: View {
    @ObservedObject var link: Link
    @State private var tool: Tool = .mouse
    @State private var showConnect = false
    @State private var showNotes = false
    @StateObject private var lang = L.shared
    @State private var showKeyboard = false
    @State private var showTimer = false
    @State private var showGoTo = false
    @State private var labelText = ""

    var body: some View {
        VStack(spacing: 8) {
            // status
            HStack {
                Circle().fill(link.connected ? .green : .orange).frame(width: 9, height: 9)
                Text(link.connected ? link.computerName : "Not connected").lineLimit(1).font(.callout)
                Spacer()
                if !link.timerText.isEmpty {
                    Text(link.timerText).font(.system(.callout, design: .monospaced))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
                Button(lang.t("language")) { lang.toggle() }.buttonStyle(.bordered).font(.caption)
                Button(link.connected ? lang.t("disconnect") : lang.t("connect")) {
                    if link.connected { link.disconnect() } else { showConnect = true }
                }.buttonStyle(.bordered)
            }

            HStack {
                Button {
                    showGoTo = true
                } label: {
                    Text(link.total > 0 ? "\(lang.t("slide")) \(link.slide) / \(link.total)" : "– / –").font(.headline)
                }
                if let img = link.slideImage, link.view.isEmpty {
                    Image(uiImage: img).resizable().scaledToFit().frame(height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Spacer()
                if !link.notes.isEmpty {
                    Button(showNotes ? "📝 Hide notes" : "📝 Notes") { showNotes.toggle() }.font(.caption)
                }
            }

            if showNotes && !link.notes.isEmpty {
                ScrollView { Text(link.notes).frame(maxWidth: .infinity, alignment: .leading).font(.callout) }
                    .frame(height: 110)
                    .padding(8).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }

            // tools
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Tool.allCases, id: \.self) { t in
                        Button(lang.ku ? t.labelKu : t.label) { tool = t; link.send(["c": "tool", "t": t.rawValue]) }
                            .font(.caption).buttonStyle(.bordered)
                            .tint(tool == t ? .blue : .gray)
                    }
                    Button("🗑 " + lang.t("clear")) { link.send(["c": "clear"]) }.font(.caption).buttonStyle(.bordered).tint(.gray)
                    Button("⌨️") { showKeyboard = true }.font(.caption).buttonStyle(.bordered).tint(.gray)
                    Button("⌛") { showTimer = true }.font(.caption).buttonStyle(.bordered).tint(.gray)
                }
            }

            ToolSettings(link: link, tool: tool)

            Touchpad(tool: tool, aspect: link.slideAspect,
                     background: link.mirrorOn ? link.mirrorImage : link.slideImage,
                     mirror: link.mirrorOn) { link.send($0) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ViewBar(link: link)
            ClassToolsBar(link: link)
            if !link.fileStatus.isEmpty {
                Text(link.fileStatus).font(.caption2).foregroundStyle(.secondary)
            }

            // show controls
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button("▶ " + lang.t("start")) { link.send(["c": "start", "from": "begin"]) }
                    Button("▶ " + lang.t("fromHere")) { link.send(["c": "start", "from": "current"]) }
                    Button("■ " + lang.t("end")) { link.send(["c": "end"]) }
                    Button("⬛ " + lang.t("black")) { link.send(["c": "screen", "m": "black"]) }
                    Button("⬜ " + lang.t("white")) { link.send(["c": "screen", "m": "white"]) }
                    Button("🖥 " + lang.t("desktop")) { link.send(["c": "desktop"]) }
                    Button("▶ " + lang.t("backShow")) { link.send(["c": "back_show"]) }
                    Button("📺 " + lang.t("seeScreen")) { link.setMirror(!link.mirrorOn) }
                }.font(.caption).buttonStyle(.bordered).tint(.gray)
            }

            // next / previous
            HStack(spacing: 10) {
                Button("◀") { link.send(["c": "prev"]) }
                    .frame(maxWidth: .infinity, minHeight: 58).buttonStyle(.borderedProminent).tint(.gray)
                Button(lang.t("next") + " ▶") { link.send(["c": "next"]) }
                    .frame(maxWidth: 200, minHeight: 58).buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
        .sheet(isPresented: $showConnect) { ConnectSheet(link: link) }
        .sheet(isPresented: $showKeyboard) { KeyboardSheet(link: link) }
        .sheet(isPresented: $showTimer) { TimerSheet(link: link) }
        .sheet(isPresented: $showGoTo) { GoToSheet(link: link) }
        .alert("📍 " + lang.t("type"), isPresented: Binding(
            get: { link.askText != nil },
            set: { if !$0 { link.askText = nil } })) {
            TextField("…", text: $labelText)
            Button("OK") { link.saveText(labelText); labelText = "" }
            Button(lang.t("clear"), role: .cancel) { link.askText = nil }
        }
        .onChange(of: link.caretSeen) { seen in
            if seen, UserDefaults.standard.bool(forKey: "autoKeyboard") { showKeyboard = true }
        }
        .environment(\.layoutDirection, lang.ku ? .rightToLeft : .leftToRight)
    }
}

/// Pick the computer and type its PIN (the same 4 digits UOR-RC shows).
struct ConnectSheet: View {
    @ObservedObject var link: Link
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var picked: Link.Beacon?

    var body: some View {
        NavigationStack {
            List {
                Section("Computers on this Wi-Fi") {
                    if link.found.isEmpty { Text("Looking…").foregroundStyle(.secondary) }
                    ForEach(Array(link.found.values), id: \.id) { b in
                        Button {
                            picked = b
                            pin = link.pins[b.id] ?? ""
                        } label: {
                            HStack {
                                Text("💻 " + b.name)
                                Spacer()
                                if picked?.id == b.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
                if picked != nil {
                    Section("PIN shown on the computer") {
                        TextField("0000", text: $pin).keyboardType(.numberPad).font(.title)
                        Button("Connect") {
                            if let b = picked, !pin.isEmpty { link.connect(to: b, pin: pin); dismiss() }
                        }.disabled(pin.isEmpty)
                    }
                }
                Section {
                    Text("Both devices must be on the same Wi-Fi — the laptop hotspot works well. iPhone will ask once for permission to find devices on the local network.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Connect")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
