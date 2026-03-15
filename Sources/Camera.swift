import AVFoundation
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal

class Camera: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published var error: String?
    @Published var filteredFrame: CIImage?

    var activeFilter: FilterChain? {
        didSet { filterStartTime = CACurrentMediaTime() }
    }
    var filterStartTime: CFTimeInterval = 0
    @Published var printPreview = false
    private(set) var printPreviewKernel: CIColorKernel?

    let ciContext: CIContext
    private let sessionQueue = DispatchQueue(label: "camera-session-queue")
    private let output = AVCaptureVideoDataOutput()

    override init() {
        let device = MTLCreateSystemDefaultDevice()!
        ciContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
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

    func loadPrintPreviewKernel() {
        guard let url = Bundle.module.url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url) else { return }
        printPreviewKernel = try? CIColorKernel(functionName: "print_preview", fromMetalLibraryData: data)
    }

    func captureFrame() -> NSImage? {
        guard let ci = filteredFrame else { return nil }
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

extension Camera: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var image = CIImage(cvPixelBuffer: pb)
        if let filter = activeFilter {
            let elapsed = CACurrentMediaTime() - filterStartTime
            image = filter(image, elapsed)
        }
        if printPreview, let kernel = printPreviewKernel {
            let ext = image.extent
            let mono = CIFilter.colorControls()
            mono.inputImage = image
            mono.saturation = 0
            let gray = mono.outputImage ?? image
            let clarity = CIFilter.unsharpMask()
            clarity.inputImage = gray
            clarity.radius = 30
            clarity.intensity = 1.5
            let enhanced = clarity.outputImage?.cropped(to: ext) ?? gray
            image = kernel.apply(extent: ext, arguments: [enhanced]) ?? enhanced
        }
        let result = image
        DispatchQueue.main.async { self.filteredFrame = result }
    }
}
