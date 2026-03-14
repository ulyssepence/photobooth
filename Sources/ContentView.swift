import SwiftUI

struct ContentView: View {
    @StateObject private var camera = Camera()
    @State private var isPrinting = false
    @State private var statusMessage: String?
    @State private var use58mm = false

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraView(session: camera.session)
                .scaleEffect(x: -1, y: 1)
                .ignoresSafeArea()

            HStack(spacing: 12) {
                Toggle("58mm", isOn: $use58mm)
                    .toggleStyle(.switch)
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(8)

                if use58mm {
                    Button(action: printTestPattern) {
                        Text("Test Pattern")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isPrinting ? Color.gray : Color.black.opacity(0.5))
                            .cornerRadius(8)
                    }
                    .disabled(isPrinting)
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
            .padding(.bottom, 30)

            Button(action: printPhoto) {
                Text(isPrinting ? "Printing..." : "Print")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 14)
                    .background(isPrinting ? Color.gray : Color.black.opacity(0.7))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isPrinting)
            .padding(.bottom, 30)

            if let msg = statusMessage ?? camera.error {
                Text(msg)
                    .foregroundColor(.red)
                    .padding(8)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
                    .padding(.top, 10)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private func printTestPattern() {
        isPrinting = true
        statusMessage = nil
        Task.detached {
            let result = await Printer.printFile(
                path: "/Users/ulysse/Source/photobooth/Scripts/test_pattern_58mm.png",
                paperWidth: Printer.paperWidth58mm
            )
            await MainActor.run {
                isPrinting = false
                if case .failure(let err) = result {
                    statusMessage = err.localizedDescription
                }
            }
        }
    }

    private func printPhoto() {
        guard let image = camera.captureFrame() else {
            statusMessage = "No frame available"
            return
        }
        isPrinting = true
        statusMessage = nil
        let width = use58mm ? Printer.paperWidth58mm : Printer.paperWidth80mm
        Task.detached {
            let result = await Printer.print(image: image, paperWidth: width)
            await MainActor.run {
                isPrinting = false
                if case .failure(let err) = result {
                    statusMessage = err.localizedDescription
                }
            }
        }
    }
}
