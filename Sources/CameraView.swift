import AVFoundation
import SwiftUI

struct CameraView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        PreviewView(session: session)
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        nsView.previewLayer.frame = nsView.bounds
    }
}

class PreviewView: NSView {
    let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        super.init(frame: .zero)
        wantsLayer = true
        layer = previewLayer

    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}
