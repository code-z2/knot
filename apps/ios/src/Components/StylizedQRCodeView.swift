import CoreImage
import SwiftUI

struct StylizedQRCodeView: View {
  let content: String
  var size: CGFloat = 217
  var foreground: Color = .white

  var body: some View {
    Canvas { context, canvasSize in
      guard let matrix = QRCodeMatrix(content: content) else { return }
      drawQRCode(matrix: matrix, in: canvasSize, context: &context)
    }
    .frame(width: size, height: size)
    .drawingGroup()
  }

  private func drawQRCode(matrix: QRCodeMatrix, in size: CGSize, context: inout GraphicsContext) {
    let dimension = matrix.dimension
    guard dimension > 0 else { return }

    let module = min(size.width, size.height) / CGFloat(dimension)
    let inset = module * 0.12
    let corner = max(1, (module - 2 * inset) * 0.35)
    let eyeSize = 7

    func inEye(_ x: Int, _ y: Int) -> Bool {
      let topLeft = x < eyeSize && y < eyeSize
      let topRight = x >= dimension - eyeSize && y < eyeSize
      let bottomLeft = x < eyeSize && y >= dimension - eyeSize
      return topLeft || topRight || bottomLeft
    }

    for y in 0..<dimension {
      for x in 0..<dimension where matrix.bits[y][x] && !inEye(x, y) {
        let rect = CGRect(
          x: CGFloat(x) * module + inset,
          y: CGFloat(y) * module + inset,
          width: module - (2 * inset),
          height: module - (2 * inset)
        )
        context.fill(Path(roundedRect: rect, cornerRadius: corner), with: .color(foreground))
      }
    }

    drawEye(atX: 0, atY: 0, module: module, in: &context)
    drawEye(atX: CGFloat(dimension - eyeSize) * module, atY: 0, module: module, in: &context)
    drawEye(atX: 0, atY: CGFloat(dimension - eyeSize) * module, module: module, in: &context)
  }

  private func drawEye(atX x: CGFloat, atY y: CGFloat, module: CGFloat, in context: inout GraphicsContext) {
    let outerSize = module * 7
    let middleInset = module * 1.2
    let centerSize = module * 1.3

    let outerRect = CGRect(x: x, y: y, width: outerSize, height: outerSize)
    context.fill(Path(roundedRect: outerRect, cornerRadius: module * 1.0), with: .color(.white))

    let middleRect = outerRect.insetBy(dx: middleInset, dy: middleInset)
    context.fill(Path(roundedRect: middleRect, cornerRadius: module * 0.9), with: .color(.black))

    let centerRect = CGRect(
      x: outerRect.midX - centerSize / 2,
      y: outerRect.midY - centerSize / 2,
      width: centerSize,
      height: centerSize
    )
    context.fill(Path(ellipseIn: centerRect), with: .color(.white))
  }
}

private struct QRCodeMatrix {
  let bits: [[Bool]]
  var dimension: Int { bits.count }

  init?(content: String) {
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    filter.setValue(Data(content.utf8), forKey: "inputMessage")
    filter.setValue("H", forKey: "inputCorrectionLevel")

    guard let image = filter.outputImage else { return nil }
    let extent = image.extent.integral
    guard extent.width > 0, extent.height > 0 else { return nil }

    let width = Int(extent.width)
    let height = Int(extent.height)
    guard width == height else { return nil }

    let context = CIContext(options: [.useSoftwareRenderer: false])
    guard let cgImage = context.createCGImage(image, from: extent) else { return nil }

    let bytesPerRow = width
    var pixels = [UInt8](repeating: 0, count: width * height)
    guard let gray = CGContext(
      data: &pixels,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { return nil }

    gray.interpolationQuality = .none
    gray.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    var rows: [[Bool]] = []
    rows.reserveCapacity(height)
    for y in 0..<height {
      var row: [Bool] = []
      row.reserveCapacity(width)
      for x in 0..<width {
        let v = pixels[(y * bytesPerRow) + x]
        row.append(v < 128)
      }
      rows.append(row)
    }

    var minX = width
    var minY = height
    var maxX = -1
    var maxY = -1
    for y in 0..<height {
      for x in 0..<width where rows[y][x] {
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)
      }
    }

    guard maxX >= minX, maxY >= minY else { return nil }

    var cropped: [[Bool]] = []
    cropped.reserveCapacity((maxY - minY) + 1)
    for y in minY...maxY {
      cropped.append(Array(rows[y][minX...maxX]))
    }

    self.bits = cropped
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    StylizedQRCodeView(content: "0xF5bB7F874D8e3f41821175c0Aa9910d30d10e193")
  }
}
