//
//  QRCode.swift
//  ShutterManager
//
//  A QR code as its grid of modules, so labels can draw it as sharp vector squares at any print
//  size instead of a scaled-up bitmap.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

struct QRCode: Equatable, Sendable {
    /// Modules along each side, without the quiet zone.
    let size: Int
    /// Row by row from the top-left; true is a dark module.
    private let modules: [Bool]

    /// The blank margin a reader needs around the code, in modules.
    static let quietZone = 4

    func isDark(row: Int, column: Int) -> Bool {
        modules[row * size + column]
    }

    /// The code for `text` at medium error correction, which reads through a scuffed sticker.
    /// Nil when the text is too long for a QR code.
    init?(_ text: String) {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let extent = output.extent.integral
        let width = Int(extent.width), height = Int(extent.height)
        // The generator makes one pixel per module. Drawn into a gray bitmap, whose first byte is
        // the top-left pixel, the rows come out top to bottom.
        guard width > 0, height > 0,
              let image = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(output, from: extent),
              let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                     space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return nil
        }
        bitmap.interpolationQuality = .none
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = bitmap.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)
        func dark(_ row: Int, _ column: Int) -> Bool { pixels[row * width + column] < 128 }

        // Trim the generator's own margin: the finder patterns reach three corners of the code,
        // so the dark pixels' bounding box is exactly the code.
        let darkRows = (0..<height).filter { row in (0..<width).contains { dark(row, $0) } }
        let darkColumns = (0..<width).filter { column in (0..<height).contains { dark($0, column) } }
        guard let top = darkRows.first, let bottom = darkRows.last,
              let left = darkColumns.first, let right = darkColumns.last,
              bottom - top == right - left else { return nil }
        size = bottom - top + 1
        modules = (top...bottom).flatMap { row in (left...right).map { dark(row, $0) } }
    }

    /// A path of the dark modules scaled to fill `rect`, quiet zone included. One path, so
    /// neighboring modules print without hairline seams between them.
    func path(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let module = min(rect.width, rect.height) / CGFloat(size + 2 * Self.quietZone)
        let origin = CGPoint(x: rect.midX - module * CGFloat(size) / 2, y: rect.midY - module * CGFloat(size) / 2)
        for row in 0..<size {
            var column = 0
            while column < size {
                guard isDark(row: row, column: column) else {
                    column += 1
                    continue
                }
                // A run of dark modules becomes one rectangle.
                var end = column
                while end + 1 < size, isDark(row: row, column: end + 1) { end += 1 }
                path.addRect(CGRect(x: origin.x + CGFloat(column) * module, y: origin.y + CGFloat(row) * module,
                                    width: CGFloat(end - column + 1) * module, height: module))
                column = end + 1
            }
        }
        return path
    }

    /// The code as an image `side` points across, black on white, for showing on screen.
    func image(side: CGFloat) -> UIImage {
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        return UIGraphicsImageRenderer(bounds: bounds).image { context in
            UIColor.white.setFill()
            context.fill(bounds)
            context.cgContext.addPath(path(in: bounds))
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fillPath()
        }
    }
}
