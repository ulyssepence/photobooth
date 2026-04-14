import AppKit

enum Printer {
    static let uvPath = "/opt/homebrew/bin/uv"

    static let paperWidth80mm = 576
    static let paperWidth58mm = 480

    static func print(image: NSImage, paperWidth: Int = 576) async -> Result<Void, Error> {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: tmp) }

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return .failure(PrintError.encodingFailed)
        }

        do {
            try png.write(to: tmp)
        } catch {
            return .failure(error)
        }

        let scriptPath = "/Users/ulysse/Source/photobooth/Scripts/print_photo.py"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: uvPath)
        process.arguments = [
            "run",
            "--with", "python-escpos",
            "--with", "pyusb",
            "--with", "Pillow",
            "--with", "numpy",
            "python3", scriptPath, tmp.path, "\(paperWidth)"
        ]
        let stderr = Pipe()
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? "Unknown error"
                return .failure(PrintError.scriptFailed(errStr))
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    static func printFile(path: String, paperWidth: Int = 576) async -> Result<Void, Error> {
        let scriptPath = "/Users/ulysse/Source/photobooth/Scripts/print_photo.py"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: uvPath)
        process.arguments = [
            "run",
            "--with", "python-escpos",
            "--with", "pyusb",
            "--with", "Pillow",
            "--with", "numpy",
            "python3", scriptPath, path, "\(paperWidth)"
        ]
        let stderr = Pipe()
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? "Unknown error"
                return .failure(PrintError.scriptFailed(errStr))
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    enum PrintError: LocalizedError {
        case encodingFailed
        case scriptFailed(String)

        var errorDescription: String? {
            switch self {
            case .encodingFailed: return "Failed to encode image as PNG"
            case .scriptFailed(let msg): return "Print failed: \(msg)"
            }
        }
    }
}
