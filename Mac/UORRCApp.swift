import SwiftUI

@main
struct UORRCApp: App {
    @StateObject private var controller = Controller()

    var body: some Scene {
        WindowGroup("UOR-RC") {
            HostView(controller: controller)
                .frame(minWidth: 620, minHeight: 520)
                .onAppear { controller.start() }
        }
        .windowResizability(.contentMinSize)
    }
}

/// The Mac window: the same idea as the Windows one, in native SwiftUI.
struct HostView: View {
    @ObservedObject var controller: Controller

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
                VStack(alignment: .leading) {
                    Text("UOR-RC").font(.title2.bold())
                    Text("Classroom remote · PowerPoint & Keynote").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            GroupBox {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(controller.connected ? "Phone connected: \(controller.phoneName)" : "Waiting for the phone…",
                              systemImage: controller.connected ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right")
                            .foregroundStyle(controller.connected ? .green : .orange)
                        Text(controller.presentationLine).font(.callout).foregroundStyle(.secondary)
                        Text("This Mac: " + controller.addresses.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            GroupBox("Connect your phone") {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PIN").font(.caption).foregroundStyle(.secondary)
                        Text(controller.settings.pin)
                            .font(.system(size: 42, weight: .bold, design: .monospaced))
                            .foregroundStyle(.blue)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1 · Put the phone on the same Wi-Fi as this Mac")
                        Text("2 · Open UOR-RC on the phone and tap Connect")
                        Text("3 · Type this PIN once")
                    }.font(.callout)
                    Spacer()
                }
            }

            GroupBox("Activity") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(controller.log.suffix(100), id: \.self) { line in
                            Text(line).font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.frame(minHeight: 140)
            }

            Text("Allow UOR-RC in System Settings → Privacy & Security → Accessibility (mouse & keyboard), Screen Recording (magnifier) and Automation (PowerPoint / Keynote).")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(18)
    }
}
