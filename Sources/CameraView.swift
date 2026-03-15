import SwiftUI
import MetalKit
import CoreImage
import Combine

struct CameraView: NSViewRepresentable {
    @ObservedObject var camera: Camera

    func makeNSView(context: Context) -> FilteredPreviewView {
        let view = FilteredPreviewView(ciContext: camera.ciContext)
        context.coordinator.subscribe(to: camera, view: view)
        return view
    }

    func updateNSView(_ nsView: FilteredPreviewView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        private var cancellable: AnyCancellable?

        func subscribe(to camera: Camera, view: FilteredPreviewView) {
            cancellable = camera.$filteredFrame
                .receive(on: RunLoop.main)
                .sink { [weak view] image in
                    view?.currentImage = image
                    view?.setNeedsDisplay(view?.bounds ?? .zero)
                }
        }
    }
}

class FilteredPreviewView: MTKView, MTKViewDelegate {
    var currentImage: CIImage?
    private let ciContext: CIContext
    private let commandQueue: MTLCommandQueue

    init(ciContext: CIContext) {
        let device = MTLCreateSystemDefaultDevice()!
        self.ciContext = ciContext
        self.commandQueue = device.makeCommandQueue()!
        super.init(frame: .zero, device: device)
        self.delegate = self
        self.framebufferOnly = false
        self.preferredFramesPerSecond = 30
        self.enableSetNeedsDisplay = true
        self.isPaused = true
    }

    required init(coder: NSCoder) { fatalError() }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let image = currentImage,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let drawableSize = view.drawableSize
        let imageSize = image.extent.size

        let scaleX = drawableSize.width / imageSize.width
        let scaleY = drawableSize.height / imageSize.height
        let scale = max(scaleX, scaleY)

        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let offsetX = (drawableSize.width - scaledWidth) / 2
        let offsetY = (drawableSize.height - scaledHeight) / 2

        let scaled = image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))

        let bounds = CGRect(origin: .zero, size: drawableSize)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        ciContext.render(scaled, to: drawable.texture, commandBuffer: commandBuffer, bounds: bounds, colorSpace: colorSpace)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
