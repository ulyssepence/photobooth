import CoreImage
import Foundation

typealias FilterChain = (CIImage, Double) -> CIImage

struct FilterDef: Identifiable {
    let id: String
    let name: String
    let chain: FilterChain
}

enum Filters {
    private static var kernels: [String: CIKernel] = [:]

    private static let disabled: Set<String> = [
        "puppet_show", "color_wheel", "water_color", "dizzy", "another_world", "mandala",
    ]

    private static let comboNames: [(id: String, name: String, fn: String, animated: Bool)] = [
        ("the_bit",              "The Bit",              "combo_the_bit",              false),
        ("it_can_feel_that_way", "It Can Feel That Way", "combo_it_can_feel_that_way", false),
        ("puppet_show",          "Puppet Show",          "combo_puppet_show",          true),
        ("color_wheel",          "Color Wheel",          "combo_color_wheel",          true),
        ("gnome",                "Gnome",                "combo_gnome",                true),
        ("us",                   "Us",                   "combo_us",                   true),
        ("the_matrix",           "The Matrix",           "combo_the_matrix",           true),
        ("water_color",          "Water Color",          "combo_water_color",          true),
        ("who_is_that",          "Who Is That?",         "combo_who_is_that",          true),
        ("dizzy",                "Dizzy",                "combo_dizzy",                true),
        ("potion_seller",        "Potion Seller",        "combo_potion_seller",        false),
        ("another_world",        "Another World",        "combo_another_world",        true),
        ("compression",          "Compression",          "combo_compression",          true),
        ("mandala",              "Mandala",              "combo_mandala",              true),
        ("mirror_world",         "Mirror World",         "combo_mirror_world",         false),
        ("knights",              "Knights",              "combo_knights",              true),
    ]

    static func loadKernels() {
        guard let url = Bundle.module.url(forResource: "default", withExtension: "metallib") else {
            print("Warning: metallib not found")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            for combo in comboNames {
                do {
                    kernels[combo.fn] = try CIKernel(functionName: combo.fn, fromMetalLibraryData: data)
                } catch {
                    print("Warning: failed to load kernel \(combo.fn): \(error)")
                }
            }
        } catch {
            print("Warning: failed to read metallib: \(error)")
        }
    }

    static var all: [FilterDef] {
        comboNames.compactMap { combo in
            guard !disabled.contains(combo.id) else { return nil }
            guard let kernel = kernels[combo.fn] else { return nil }
            let animated = combo.animated
            return FilterDef(id: combo.id, name: combo.name) { image, time in
                let ext = image.extent
                let w = Float(ext.width)
                let h = Float(ext.height)
                var args: [Any] = [image]
                if animated { args.append(Float(time)) }
                args.append(w)
                args.append(h)
                return kernel.apply(
                    extent: ext,
                    roiCallback: { _, _ in ext },
                    arguments: args
                ) ?? image
            }
        }
    }
}
