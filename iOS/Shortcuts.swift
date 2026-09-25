import AppIntents

/// 🗣 Siri and the Shortcuts app: "Hey Siri, next slide".
@available(iOS 16.0, *)
struct NextSlideIntent: AppIntent {
    static var title: LocalizedStringResource = "Next slide"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        RemoteBridge.shared.send(["c": "next"])
        return .result()
    }
}

@available(iOS 16.0, *)
struct PreviousSlideIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous slide"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        RemoteBridge.shared.send(["c": "prev"])
        return .result()
    }
}

/// Lets Siri reach the running connection.
final class RemoteBridge {
    static let shared = RemoteBridge()
    weak var link: Link?
    func send(_ o: [String: Any]) { link?.send(o) }
}
