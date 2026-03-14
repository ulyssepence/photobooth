import AVFoundation
import AppKit

class Camera: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published var error: String?

    private let sessionQueue = DispatchQueue(label: "camera-session-queue")
    private let output = AVCaptureVideoDataOutput()
    private var latestBuffer: CMSampleBuffer?
    private let bufferLock = NSLock()

    override init() {
        super.init()
        sessionQueue.async { self.configure() }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        let frontCamera = discovery.devices.first { $0.position == .front }
        guard let device = frontCamera ?? AVCaptureDevice.default(for: .video) else {
            DispatchQueue.main.async { self.error = "No camera found" }
            return
        }

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            DispatchQueue.main.async { self.error = "Cannot access camera" }
            return
        }

        if session.canAddInput(input) { session.addInput(input) }

        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.canAddOutput(output) { session.addOutput(output) }

        session.commitConfiguration()
        session.startRunning()
    }

    func captureFrame() -> NSImage? {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        guard let buffer = latestBuffer,
              let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let rep = NSCIImageRep(ciImage: ciImage)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

extension Camera: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        bufferLock.lock()
        latestBuffer = sampleBuffer
        bufferLock.unlock()
    }
}
