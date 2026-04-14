import AVFoundation
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal

class Camera: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published var error: String?
    @Published var filteredFrame: CIImage?
    private var captureImage: CIImage?

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

    func captureFrame(save: Bool = true) -> NSImage? {
        guard let ci = captureImage else { return nil }
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        if save { saveToOutput(image) }
        return image
    }

    private var saveIndex = 0

    private func saveToOutput(_ image: NSImage) {
        let dir = URL(fileURLWithPath: NSString("~/Source/photobooth/output").expandingTildeInPath)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        saveIndex += 1
        let path = dir.appendingPathComponent("\(fmt.string(from: Date()))_\(saveIndex).png")
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: path)
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
        let forCapture = image
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
        DispatchQueue.main.async {
            self.captureImage = forCapture
            self.filteredFrame = result
        }
    }
}
