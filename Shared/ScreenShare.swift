import Foundation

/// Settings shared between the iPhone app and its little screen-sharing program.
/// Apple runs screen sharing in a separate process, so the two talk through this
/// shared box: the app writes where the computer is, the extension reads it.
public enum ScreenShare {
    public static let appGroup = "group.iq.uor.rc"
    public static let port: UInt16 = 47803

    public static var store: UserDefaults? { UserDefaults(suiteName: appGroup) }

    public static func remember(host: String, token: String) {
        store?.set(host, forKey: "host")
        store?.set(token, forKey: "token")
    }

    public static var host: String { store?.string(forKey: "host") ?? "" }
    public static var token: String { store?.string(forKey: "token") ?? "" }
}
