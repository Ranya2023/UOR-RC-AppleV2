import ReplayKit
import UIKit
import VideoToolbox

/// 📱 The little program Apple runs while the iPhone shares its screen.
/// It cannot use the app's connection, so it opens its own to the computer,
/// proves the token the app agreed, and sends one picture at a time.
class SampleHandler: RPBroadcastSampleHandler {
    private var fd: Int32 = -1
    private var waiting = false
    private var lastSent = Date.distantPast
    private let context = CIContext()

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        openConnection()
    }

    override func broadcastFinished() {
        if fd >= 0 { Darwin.close(fd); fd = -1 }
    }

    /// Opens the link to the computer (Darwin.* so nothing is confused with our own names).
    private func openConnection() {
        let host = ScreenShare.host
        guard !host.isEmpty else { return }
        let s = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard s >= 0 else { return }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = ScreenShare.port.bigEndian
        addr.sin_addr.s_addr = inet_addr(host)
        let ok = withUnsafePointer(to: &addr) { raw in
            raw.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard ok == 0 else { Darwin.close(s); return }
        fd = s
        write(line: ["t": "hello", "token": ScreenShare.token, "phone": UIDevice.current.name])
        listenForAcks()
    }

    /// The computer says "ready" after each picture, so we never flood the Wi-Fi.
    private func listenForAcks() {
        let handle = fd
        Thread {
            var buf = [UInt8](repeating: 0, count: 1024)
            while handle >= 0 {
                let n = Darwin.recv(handle, &buf, buf.count, 0)
                if n <= 0 { break }
                self.waiting = false
            }
        }.start()
    }

    private func write(line object: [String: Any]) {
        guard fd >= 0, let data = Wire.encode(object) else { return }
        _ = data.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return 0 }
            var sent = 0
            while sent < data.count {
                let n = Darwin.send(fd, base + sent, data.count - sent, 0)
                if n <= 0 { Darwin.close(fd); fd = -1; return sent }
                sent += n
            }
            return sent
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with type: RPSampleBufferType) {
        guard type == .video, fd >= 0 else { return }
        if waiting, Date().timeIntervalSince(lastSent) < 1.5 { return }
        if Date().timeIntervalSince(lastSent) < 0.09 { return }          // about 11 pictures a second
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var image = CIImage(cvPixelBuffer: pixels)
        // make it smaller so it travels quickly over Wi-Fi
        let wanted: CGFloat = 900
        if image.extent.width > wanted {
            let scale = wanted / image.extent.width
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        guard let jpeg = context.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB(),
                                                    options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.5])
        else { return }
        waiting = true
        lastSent = Date()
        write(line: ["img": jpeg.base64EncodedString(), "w": Int(image.extent.width), "h": Int(image.extent.height)])
    }
}
