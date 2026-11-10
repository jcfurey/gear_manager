//
//  PrintDocument.swift
//  ShutterManager
//
//  What the app's printable PDFs share: the paper, the elements a page is made of, and drawing
//  them. A document is laid out first, as a list of placed elements for each page, and drawn
//  second, so page counts are known up front and tests can check a layout without reading a PDF.
//

import UIKit

/// Paper for printable documents: US Letter where it's the norm, A4 everywhere else.
enum PrintPaper {
    static let letter = CGSize(width: 612, height: 792)
    static let a4 = CGSize(width: 595, height: 842)

    /// Regions whose printers are loaded with US Letter.
    private static let letterRegions: Set<String> = ["US", "CA", "MX", "PR", "PH", "CL", "CO", "CR", "GT", "PA", "DO", "VE"]

    static func size(for locale: Locale = .current) -> CGSize {
        letterRegions.contains(locale.region?.identifier ?? "") ? letter : a4
    }
}

/// One thing placed on a page, in points from the page's top-left corner.
enum PrintElement {
    case text(NSAttributedString, CGRect)
    /// A JPEG, drawn to fill its frame.
    case photo(Data, CGRect)
    /// A hairline, filled light gray.
    case rule(CGRect)
    /// A dashed outline to cut along.
    case cutLine(CGRect)
    /// A QR code with its quiet zone, centered in its frame.
    case code(QRCode, CGRect)

    var frame: CGRect {
        switch self {
        case .text(_, let frame), .photo(_, let frame), .rule(let frame), .cutLine(let frame), .code(_, let frame):
            return frame
        }
    }
}

enum PrintDocument {
    static let secondary = UIColor(white: 0.4, alpha: 1)
    static let textOptions: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine]

    /// The pages as a PDF. `footer` gives each page's own elements, from its number and the count.
    static func pdfData(pages: [[PrintElement]], pageSize: CGSize, title: String,
                        footer: ((_ page: Int, _ count: Int) -> [PrintElement])? = nil) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: Constants.App.name,
            kCGPDFContextTitle as String: title
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        return renderer.pdfData { context in
            for (index, page) in pages.enumerated() {
                context.beginPage()
                for element in page + (footer?(index + 1, pages.count) ?? []) {
                    draw(element, in: context.cgContext)
                }
            }
        }
    }

    private static func draw(_ element: PrintElement, in context: CGContext) {
        switch element {
        case .text(let string, let frame):
            string.draw(with: frame, options: textOptions, context: nil)
        case .photo(let jpeg, let frame):
            // From a JPEG data provider, so the PDF keeps the compressed bytes instead of storing
            // the decoded pixels. The page's origin is top-left; images draw bottom-up.
            guard let provider = CGDataProvider(data: jpeg as CFData),
                  let image = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true,
                                      intent: .defaultIntent) else { return }
            context.saveGState()
            context.translateBy(x: frame.minX, y: frame.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(origin: .zero, size: frame.size))
            context.restoreGState()
        case .rule(let frame):
            context.setFillColor(UIColor(white: 0.75, alpha: 1).cgColor)
            context.fill(frame)
        case .cutLine(let frame):
            context.saveGState()
            context.setStrokeColor(UIColor(white: 0.7, alpha: 1).cgColor)
            context.setLineWidth(0.5)
            context.setLineDash(phase: 0, lengths: [3, 3])
            context.stroke(frame)
            context.restoreGState()
        case .code(let code, let frame):
            context.addPath(code.path(in: frame))
            context.setFillColor(UIColor.black.cgColor)
            context.fillPath()
        }
    }

    // MARK: - Text

    /// Text for a page. With `truncatesLines`, each line of `string` stays on one line and is cut
    /// short with an ellipsis instead of wrapping.
    static func text(_ string: String, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor = .black,
                     alignment: NSTextAlignment = .left, lineSpacing: CGFloat = 0,
                     truncatesLines: Bool = false) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineSpacing = lineSpacing
        if truncatesLines { paragraph.lineBreakMode = .byTruncatingTail }
        return NSAttributedString(string: string, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }

    /// The height `text` takes when wrapped to `width`.
    static func height(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        ceil(text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                               options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }

    // MARK: - Files

    /// Documents wait here to be previewed and shared. Emptied before each new one, so they
    /// don't pile up.
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Printable", isDirectory: true)
    }

    /// "2026-11-10", for file names.
    static func dateStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Writes `data` to `directory` under `name`, replacing whatever was there.
    static func write(_ data: Data, named name: String) throws -> URL {
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
