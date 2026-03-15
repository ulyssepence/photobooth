import SwiftUI

struct ContentView: View {
    @StateObject private var camera = Camera()
    @State private var isPrinting = false
    @State private var statusMessage: String?
    @State private var use58mm = false
    @State private var selectedFilterId: String?

    private var filters: [FilterDef] { Filters.all }

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                CameraView(camera: camera)
                    .scaleEffect(x: -1, y: 1)
                    .ignoresSafeArea()

                HStack(spacing: 12) {
                    Toggle("58mm", isOn: $use58mm)
                        .toggleStyle(.switch)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(8)

                    Toggle("B&W", isOn: $camera.printPreview)
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

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 4) {
                        FilterButton(name: "None", isSelected: selectedFilterId == nil) {
                            selectedFilterId = nil
                            camera.activeFilter = nil
                        }
                        ForEach(filters) { filter in
                            FilterButton(name: filter.name, isSelected: selectedFilterId == filter.id) {
                                if selectedFilterId == filter.id {
                                    selectedFilterId = nil
                                    camera.activeFilter = nil
                                } else {
                                    selectedFilterId = filter.id
                                    camera.activeFilter = filter.chain
                                }
                            }
                        }
                    }
                    .padding(8)
                }

                Button(action: printPhoto) {
                    Text(isPrinting ? "Printing..." : "Print")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isPrinting ? Color.gray : Color.white.opacity(0.2))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(isPrinting)
                .padding(8)
            }
            .frame(width: 160)
            .background(Color.black.opacity(0.85))
        }
        .onAppear {
            Filters.loadKernels()
            camera.loadPrintPreviewKernel()
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

struct FilterButton: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: 13, weight: isSelected ? .bold : .regular))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.white.opacity(0.2) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
