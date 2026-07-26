import CoreText
import SwiftUI

enum PixelTheme {
    static let background = Color(red: 0.020, green: 0.027, blue: 0.043)
    static let surface = Color(red: 0.043, green: 0.063, blue: 0.094)
    static let raised = Color(red: 0.063, green: 0.094, blue: 0.141)
    static let divider = Color(red: 0.094, green: 0.129, blue: 0.180)
    static let text = Color(red: 0.910, green: 0.929, blue: 0.961)
    static let muted = Color(red: 0.498, green: 0.541, blue: 0.604)
    static let cyan = Color(red: 0.369, green: 0.918, blue: 0.831)
    static let violet = Color(red: 0.655, green: 0.545, blue: 0.980)
    static let amber = Color(red: 0.992, green: 0.729, blue: 0.290)
    static let green = Color(red: 0.290, green: 0.871, blue: 0.502)
    static let red = Color(red: 0.984, green: 0.443, blue: 0.522)
}

enum PixelFontRegistry {
    static let postScriptName = "Fusion-Pixel-12px-Prop-zh_hans-Regular"

    static func register() {
        let candidates: [URL?] = [
            Bundle.main.url(
                forResource: "fusion_pixel_12px_zh_hans",
                withExtension: "ttf"
            ),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("../assets/fonts/fusion_pixel_12px_zh_hans.ttf"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("assets/fonts/fusion_pixel_12px_zh_hans.ttf"),
        ]

        guard let url = candidates.compactMap({ $0 }).first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            return
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension Font {
    static func pixel(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .custom(PixelFontRegistry.postScriptName, fixedSize: size).weight(weight)
    }
}

extension Color {
    init(pixelHex: UInt32) {
        self.init(
            red: Double((pixelHex >> 16) & 0xFF) / 255,
            green: Double((pixelHex >> 8) & 0xFF) / 255,
            blue: Double(pixelHex & 0xFF) / 255
        )
    }
}
