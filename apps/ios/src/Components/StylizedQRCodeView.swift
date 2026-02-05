import CoreImage
import SwiftUI
import UIKit

struct StylizedQRCodeView: View {
    let content: String
    var size: CGFloat = 217
    var foreground: Color = .black
    var background: Color = .white

    @State private var renderedImage: Image?

    var body: some View {
        ZStack {
            background

            if let renderedImage {
                renderedImage
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous))
        .task(id: content) {
            await renderQRCode()
        }
    }

    @MainActor
    private func renderQRCode() async {
        let targetSize = CGSize(width: size, height: size)
        let image = await QRCodeRenderer.generate(
            content: content,
            targetSize: targetSize,
            foreground: foreground,
            background: background
        )
        renderedImage = image
    }
}

private enum QRCodeRenderer {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func generate(
        content: String,
        targetSize: CGSize,
        foreground: Color,
        background: Color
    ) async -> Image? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let cgImage = makeCGImage(
                    content: content,
                    targetSize: targetSize,
                    foreground: foreground,
                    background: background
                )
                let image = cgImage.map { Image(decorative: $0, scale: 1.0) }
                continuation.resume(returning: image)
            }
        }
    }

    private static func makeCGImage(
        content: String,
        targetSize: CGSize,
        foreground: Color,
        background: Color
    ) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(content.utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }

        let fg = CIColor(color: UIColor(foreground))
        let bg = CIColor(color: UIColor(background))
        let falseColor = CIFilter(name: "CIFalseColor")
        falseColor?.setValue(outputImage, forKey: kCIInputImageKey)
        falseColor?.setValue(fg, forKey: "inputColor0")
        falseColor?.setValue(bg, forKey: "inputColor1")

        guard let coloredImage = falseColor?.outputImage else { return nil }

        let extent = coloredImage.extent.integral
        let scale = min(targetSize.width / extent.width, targetSize.height / extent.height)
        let integralScale = max(1, floor(scale))
        let transform = CGAffineTransform(scaleX: integralScale, y: integralScale)
        let scaledImage = coloredImage.transformed(by: transform)

        return context.createCGImage(scaledImage, from: scaledImage.extent)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        StylizedQRCodeView(content: "0xF5bB7F874D8e3f41821175c0Aa9910d30d10e193")
    }
}
