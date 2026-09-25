import SwiftUI
import ReplayKit

/// 📱 The Apple button that starts and stops sharing the whole phone screen.
struct BroadcastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let v = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 52, height: 52))
        v.preferredExtension = "iq.uor.rc.remote.broadcast"
        v.showsMicrophoneButton = false
        for sub in v.subviews {
            if let button = sub as? UIButton {
                button.setImage(UIImage(systemName: "iphone.gen3.radiowaves.left.and.right"), for: .normal)
                button.tintColor = .white
            }
        }
        return v
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
