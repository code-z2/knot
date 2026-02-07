import CoreImage.CIFilterBuiltins
import SwiftUI

struct StylizedQRCodeView: View {
  let content: String
  var size: CGFloat = 217
  var foreground: Color = .white
  var background: Color = .clear
  var logo: String? = nil

  @State private var qrMatrix: [[Bool]]?

  var body: some View {
    ZStack {
      background

      if let matrix = qrMatrix {
        Canvas { context, size in
          let moduleSize = size.width / CGFloat(matrix.count)
          let radius = moduleSize / 2.0

          // Draw Data Modules (Liquid Style)
          context.fill(
            Path { path in
              for row in 0..<matrix.count {
                for col in 0..<matrix.count {
                  if matrix[row][col] {
                    // Skip if part of the 3 position patterns (eyes)
                    if isEye(row: row, col: col, count: matrix.count) {
                      continue
                    }

                    // Skip if inside logo area (creating transparent "quiet zone")
                    if isLogoArea(row: row, col: col, count: matrix.count, logoPresent: logo != nil)
                    {
                      continue
                    }

                    let x = CGFloat(col) * moduleSize + radius
                    let y = CGFloat(row) * moduleSize + radius
                    let center = CGPoint(x: x, y: y)

                    // Draw the module itself (circle)
                    path.addArc(
                      center: center, radius: radius, startAngle: .zero, endAngle: .degrees(360),
                      clockwise: false)

                    // Bridge to Right Neighbor
                    if col + 1 < matrix.count && matrix[row][col + 1]
                      && !isEye(row: row, col: col + 1, count: matrix.count)
                      && !isLogoArea(
                        row: row, col: col + 1, count: matrix.count, logoPresent: logo != nil)
                    {
                      let nextX = CGFloat(col + 1) * moduleSize + radius
                      let rect = CGRect(x: x, y: y - radius, width: nextX - x, height: moduleSize)
                      path.addRect(rect)
                    }

                    // Bridge to Bottom Neighbor
                    if row + 1 < matrix.count && matrix[row + 1][col]
                      && !isEye(row: row + 1, col: col, count: matrix.count)
                      && !isLogoArea(
                        row: row + 1, col: col, count: matrix.count, logoPresent: logo != nil)
                    {
                      let nextY = CGFloat(row + 1) * moduleSize + radius
                      let rect = CGRect(x: x - radius, y: y, width: moduleSize, height: nextY - y)
                      path.addRect(rect)
                    }
                  }
                }
              }
            },
            with: .color(foreground)
          )

          // Draw Custom Eyes
          drawEye(context: context, x: 0, y: 0, moduleSize: moduleSize, color: foreground)
          drawEye(
            context: context, x: CGFloat(matrix.count - 7) * moduleSize, y: 0,
            moduleSize: moduleSize, color: foreground)
          drawEye(
            context: context, x: 0, y: CGFloat(matrix.count - 7) * moduleSize,
            moduleSize: moduleSize, color: foreground)

        }
        .frame(width: size, height: size)
      }

      if let logo = logo {
        Image(logo)
          .resizable()
          .scaledToFit()
          .frame(width: size * 0.17, height: size * 0.17)
          .clipShape(Circle())
      }
    }
    .frame(width: size, height: size)
    .task(id: content) {
      qrMatrix = generateQRMatrix(from: content)
    }
  }

  private func isLogoArea(row: Int, col: Int, count: Int, logoPresent: Bool) -> Bool {
    guard logoPresent else { return false }
    // Center of the grid
    let center = CGFloat(count) / 2.0
    // Module center coordinates
    let r = CGFloat(row) + 0.5
    let c = CGFloat(col) + 0.5

    let dist = sqrt(pow(center - r, 2) + pow(center - c, 2))

    // Logo size is 0.17 * total size
    // Radius is 0.085 * count
    // We want a quiet zone around it. Let's add ~10% padding to the radius?
    // Or roughly equivalent to the stroke width we had (3pts).
    // Let's assume a cutout radius of ~0.105 * count (diameter 0.21)

    return dist < (Double(count) * 0.105)
  }

  private func isEye(row: Int, col: Int, count: Int) -> Bool {
    // Top-Left Eye
    if row < 7 && col < 7 { return true }
    // Top-Right Eye
    if row < 7 && col >= count - 7 { return true }
    // Bottom-Left Eye
    if row >= count - 7 && col < 7 { return true }
    return false
  }

  private func drawEye(
    context: GraphicsContext, x: CGFloat, y: CGFloat, moduleSize: CGFloat, color: Color
  ) {
    let eyeSize = moduleSize * 7
    let outerRect = CGRect(x: x, y: y, width: eyeSize, height: eyeSize)

    // Outer Box (Rounded Square)
      _ = Path { path in
      path.addRoundedRect(
        in: outerRect, cornerSize: CGSize(width: moduleSize * 2, height: moduleSize * 2))
    }

    // Inner Cutout
    let innerCutoutSize = moduleSize * 5
    let innerCutoutRect = CGRect(
      x: x + moduleSize, y: y + moduleSize, width: innerCutoutSize, height: innerCutoutSize)
      _ = Path { path in
      path.addRoundedRect(
        in: innerCutoutRect, cornerSize: CGSize(width: moduleSize * 1.5, height: moduleSize * 1.5))
    }

    // Combine Outer - Inner (Stroke Effect)
    // Since SwiftUI canvas doesn't support easy boolean path ops like 'difference' in this context directly without CGPath heavy lifting,
    // we can just stroke the path, or draw the outer filled and fill the inner with background (if solid), or use evenOdd fill rule.
    // A simple centered stroke is easier for "Ring" look.

    // Alternative: Draw stroke
    let strokeWidth = moduleSize
    let ringRect = outerRect.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2)
    context.stroke(
      Path(roundedRect: ringRect, cornerRadius: moduleSize * 2),
      with: .color(color),
      lineWidth: strokeWidth
    )

    // Center Dot
    let dotSize = moduleSize * 3
    let dotRect = CGRect(
      x: x + moduleSize * 2, y: y + moduleSize * 2, width: dotSize, height: dotSize)
    context.fill(
      Path(roundedRect: dotRect, cornerRadius: moduleSize),
      with: .color(color)
    )
  }

  private func generateQRMatrix(from string: String) -> [[Bool]]? {
    let context = CIContext()
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    filter.correctionLevel = "H"  // High error correction for logo

    guard let outputImage = filter.outputImage else { return nil }

    // Scale to a reasonable size to efficiently sample, but strict module mapping is better
    // The outputImage from CIQRCodeGenerator IS 1 unit per module implicitly.
    // We just need to read it.

    let cgImage = context.createCGImage(outputImage, from: outputImage.extent)
    guard let image = cgImage else { return nil }

    let width = image.width
    let height = image.height

    // We need to read the raw pixel data
    // CIQRCodeGenerator output is grayscale.
    // 0 (black) is set, 1 (white) is empty. (Wait, usually it's black on white)
    // Standard standard: Black modules are 'true', White are 'false'.

    guard let dataProvider = image.dataProvider,
      let data = dataProvider.data,
      let ptr = CFDataGetBytePtr(data)
    else {
      return nil
    }

    var matrix = Array(repeating: Array(repeating: false, count: width), count: height)
    let bytesPerRow = image.bytesPerRow
    let bytesPerPixel = image.bitsPerPixel / 8

    for y in 0..<height {
      for x in 0..<width {
        let offset = y * bytesPerRow + x * bytesPerPixel
        // CIQRCodeGenerator typically outputs 0 for black (active) and 255 for white (inactive)
        let pixelValue = ptr[offset]
        matrix[y][x] = pixelValue < 128  // True if dark (active module)
      }
    }

    return matrix
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    StylizedQRCodeView(content: "0xF5bB7F874D8e3f41821175c0Aa9910d30d10e193", logo: "LogoMark")
  }
}
