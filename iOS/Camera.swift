import SwiftUI
import AVFoundation

/// 📷 Document camera: the phone's back camera live on the projector.
/// Hold the phone over a paper or a book. 📸 takes a photo with a caption for the
/// group gallery, 🎤 sends your voice to the computer (off unless you turn it on).
struct CameraSheet: View {
    @ObservedObject var link: Link
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraModel()
    @State private var caption = ""
    @State private var askCaption = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session).ignoresSafeArea()
            VStack {
                Text(camera.frozen ? "⏸ Frozen" : "📷 Live on the projector")
                    .font(.caption).padding(8)
                    .background(.black.opacity(0.55), in: Capsule()).foregroundStyle(.white)
                Spacer()
                HStack(spacing: 8) {
                    Button(camera.torch ? "⚡️ On" : "⚡ Light") { camera.toggleTorch() }
                    Button(camera.frozen ? "▶ Live" : "⏸ Freeze") { camera.frozen.toggle() }
                    Button("📸") { camera.wantsPhoto = true }
                    Button("🖼") { link.send(["c": "gallery", "a": "show"]) }
                    Button(camera.micOn ? "🎤 On" : "🎤 Mic") { camera.toggleMic(link: link) }
                    Button("🔄") { camera.rotation = (camera.rotation + 90) % 360; camera.sendView(link) }
                    Button("✕") { dismiss() }
                }
                .font(.caption).buttonStyle(.borderedProminent).tint(.black.opacity(0.6))
                .padding(.bottom, 12)
            }
        }
        .onAppear { camera.start(link: link) { data in caption = ""; askCaption = true; camera.pendingPhoto = data } }
        .onDisappear { camera.stop(link: link) }
        .alert("📸 Photo caption", isPresented: $askCaption) {
            TextField("e.g. Group 1", text: $caption)
            Button("Show on projector") { camera.sendPhoto(link: link, caption: caption, show: true) }
            Button("Save only") { camera.sendPhoto(link: link, caption: caption, show: false) }
            Button("Cancel", role: .cancel) { camera.pendingPhoto = nil }
        }
    }
}

/// The camera itself: preview, frames to the computer, photos and the microphone.
final class CameraModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate,
                         AVCaptureAudioDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published var frozen = false
    @Published var torch = false
    @Published var micOn = false
    var rotation = 0
    var wantsPhoto = false
    var pendingPhoto: Data?

    private let queue = DispatchQueue(label: "uorrc.camera")
    private let video = AVCaptureVideoDataOutput()
    private let audio = AVCaptureAudioDataOutput()
    private weak var link: Link?
    private var onPhoto: ((Data) -> Void)?
    private var waiting = false
    private var lastSent = Date.distantPast
    private var device: AVCaptureDevice?

    func start(link: Link, onPhoto: @escaping (Data) -> Void) {
        self.link = link
        self.onPhoto = onPhoto
        link.onAck = { [weak self] in self?.waiting = false }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
            guard ok, let self else { return }
            self.queue.async { self.configure() }
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        if let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: cam), session.canAddInput(input) {
            session.addInput(input)
            device = cam
        }
        video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        video.alwaysDiscardsLateVideoFrames = true
        video.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(video) { session.addOutput(video) }
        session.commitConfiguration()
        session.startRunning()
        DispatchQueue.main.async { self.sendView(self.link) }
    }

    func stop(link: Link?) {
        session.stopRunning()
        micOn = false
        link?.send(["c": "audio_stop"])
        link?.send(["c": "phone_stop"])
        link?.onAck = nil
    }

    func toggleTorch() {
        guard let d = device, d.hasTorch, (try? d.lockForConfiguration()) != nil else { return }
        torch.toggle()
        d.torchMode = torch ? .on : .off
        d.unlockForConfiguration()
    }

    func sendView(_ link: Link?) {
        link?.send(["c": "phone_view", "rot": rotation, "fill": false])
    }

    /// 🎤 the phone's microphone → the computer's speakers
    func toggleMic(link: Link) {
        micOn.toggle()
        if !micOn {
            link.send(["c": "audio_stop"])
            queue.async {
                self.session.beginConfiguration()
                self.session.removeOutput(self.audio)
                for i in self.session.inputs where (i as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true {
                    self.session.removeInput(i)
                }
                self.session.commitConfiguration()
            }
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] ok in
            guard ok, let self else { return }
            self.queue.async {
                self.session.beginConfiguration()
                if let mic = AVCaptureDevice.default(for: .audio),
                   let input = try? AVCaptureDeviceInput(device: mic), self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                self.audio.setSampleBufferDelegate(self, queue: self.queue)
                if self.session.canAddOutput(self.audio) { self.session.addOutput(self.audio) }
                self.session.commitConfiguration()
            }
        }
    }

    func sendPhoto(link: Link, caption: String, show: Bool) {
        guard let data = pendingPhoto else { return }
        pendingPhoto = nil
        link.send(["c": "shot", "img": data.base64EncodedString(), "label": caption,
                   "show": show, "single": true])
    }

    // ── frames ─────────────────────────────────────────────────────────
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if output === audio {
            sendAudio(sampleBuffer)
            return
        }
        guard !frozen || wantsPhoto,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if waiting, Date().timeIntervalSince(lastSent) < 2, !wantsPhoto { return }
        let ci = CIImage(cvPixelBuffer: pixels)
        let context = CIContext()
        guard let jpeg = context.jpegRepresentation(of: ci, colorSpace: CGColorSpaceCreateDeviceRGB(),
                                                    options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.72])
        else { return }
        if wantsPhoto {
            wantsPhoto = false
            DispatchQueue.main.async { self.onPhoto?(jpeg) }
        }
        guard !frozen else { return }
        waiting = true
        lastSent = Date()
        link?.send(["c": "phone_frame", "img": jpeg.base64EncodedString(),
                    "w": Int(ci.extent.width), "h": Int(ci.extent.height)])
    }

    private func sendAudio(_ sample: CMSampleBuffer) {
        guard micOn, let block = CMSampleBufferGetDataBuffer(sample) else { return }
        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: &length, dataPointerOut: &pointer) == noErr,
              let pointer, length > 0 else { return }
        let data = Data(bytes: pointer, count: length)
        let desc = CMSampleBufferGetFormatDescription(sample)
        let asbd = desc.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        link?.send(["c": "audio", "d": data.base64EncodedString(),
                    "r": Int(asbd?.mSampleRate ?? 44100), "ch": Int(asbd?.mChannelsPerFrame ?? 1)])
    }
}

/// The live picture on the phone's own screen.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.layer.session = session
        v.layer.videoGravity = .resizeAspect
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        override var layer: AVCaptureVideoPreviewLayer { super.layer as! AVCaptureVideoPreviewLayer }
    }
}
