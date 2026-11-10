//
//  InsurerReportRenderer.swift
//  ShutterManager
//
//  Lays an `InsurerReport` out on pages and draws them as a PDF. Layout comes first, as a list of
//  placed elements for each page, so the page count is known before anything is drawn (for "Page 2
//  of 5") and tests can check the layout without reading a PDF back.
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

struct InsurerReportRenderer: Sendable {
    let pageSize: CGSize

    init(pageSize: CGSize = PrintPaper.size()) {
        self.pageSize = pageSize
    }

    /// One thing placed on a page, in points from the page's top-left corner.
    enum Element {
        case text(NSAttributedString, CGRect)
        case photo(Data, CGRect)
        /// A hairline across the content width.
        case rule(CGRect)

        var frame: CGRect {
            switch self {
            case .text(_, let frame), .photo(_, let frame), .rule(let frame): return frame
            }
        }
    }

    private let margin: CGFloat = 48
    /// Kept clear at the foot of every page for the page number.
    private let footerHeight: CGFloat = 22
    private let coverSize = CGSize(width: 108, height: 81)
    private let photosPerRow = 4
    private let gap: CGFloat = 8

    private var contentWidth: CGFloat { pageSize.width - 2 * margin }
    /// The area elements are laid out in.
    var contentFrame: CGRect {
        CGRect(x: margin, y: margin, width: contentWidth, height: pageSize.height - 2 * margin - footerHeight)
    }

    // MARK: - PDF

    func pdfData(for report: InsurerReport) -> Data {
        let laidOut = pages(for: report)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: Constants.App.name,
            kCGPDFContextTitle as String: InsurerReport.title
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        return renderer.pdfData { context in
            for (index, page) in laidOut.enumerated() {
                context.beginPage()
                for element in page { draw(element, in: context.cgContext) }
                drawFooter(page: index + 1, of: laidOut.count)
            }
        }
    }

    private func draw(_ element: Element, in context: CGContext) {
        switch element {
        case .text(let string, let frame):
            string.draw(with: frame, options: Self.textOptions, context: nil)
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
        }
    }

    /// Drawn into the page that's current.
    private func drawFooter(page: Int, of count: Int) {
        let frame = CGRect(x: margin, y: pageSize.height - margin - 10, width: contentWidth, height: 12)
        Self.text("Prepared with \(Constants.App.name)", size: 8, color: Self.secondary)
            .draw(with: frame, options: Self.textOptions, context: nil)
        Self.text("Page \(page) of \(count)", size: 8, color: Self.secondary, alignment: .right)
            .draw(with: frame, options: Self.textOptions, context: nil)
    }

    // MARK: - File

    /// Reports wait here to be previewed and shared. Emptied before each new one.
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Reports", isDirectory: true)
    }

    /// "Gear Inventory 2026-11-10.pdf": a name that still makes sense in the insurer's inbox.
    static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(InsurerReport.title) \(formatter.string(from: date)).pdf"
    }

    /// Draws the report off the main actor and writes it to `directory`, replacing earlier reports.
    static func writeFile(for report: InsurerReport, pageSize: CGSize = PrintPaper.size()) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let data = InsurerReportRenderer(pageSize: pageSize).pdfData(for: report)
            try? FileManager.default.removeItem(at: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(fileName(for: report.preparedDate))
            try data.write(to: url, options: .atomic)
            return url
        }.value
    }

    // MARK: - Layout

    /// Where the next element goes, starting a new page when one doesn't fit.
    private final class Cursor {
        private(set) var pages: [[Element]] = [[]]
        var y: CGFloat
        private let top: CGFloat
        private let bottom: CGFloat

        init(frame: CGRect) {
            top = frame.minY
            bottom = frame.maxY
            y = frame.minY
        }

        func add(_ element: Element) { pages[pages.count - 1].append(element) }

        /// Moves to a new page when `height` doesn't fit below the cursor. Something taller than a
        /// whole page stays where it is on an empty one.
        func reserve(_ height: CGFloat) {
            guard y + height > bottom, y > top else { return }
            pages.append([])
            y = top
        }
    }

    /// The report's pages, each a list of placed elements.
    func pages(for report: InsurerReport) -> [[Element]] {
        let cursor = Cursor(frame: contentFrame)
        place(Self.text(InsurerReport.title, size: 22, weight: .bold), on: cursor, spacingAfter: 4)
        place(Self.text(report.subtitle, size: 11, color: Self.secondary), on: cursor, spacingAfter: 10)

        var heading = report.summaryLines
        if !report.reference.isEmpty { heading.insert(.init(label: "Reference", value: report.reference), at: 0) }
        if !report.ownerName.isEmpty { heading.insert(.init(label: "Owner", value: report.ownerName), at: 0) }
        place(Self.text(heading.map { "\($0.label): \($0.value)" }.joined(separator: "\n"), size: 11, lineSpacing: 3),
              on: cursor, spacingAfter: 8)
        place(Self.text(InsurerReport.disclaimer, size: 9, color: Self.secondary), on: cursor, spacingAfter: 10)
        placeRule(on: cursor, spacingAfter: 14)

        if report.entries.isEmpty {
            place(Self.text("No gear in this report.", size: 11, color: Self.secondary), on: cursor, spacingAfter: 0)
        }
        for group in report.entriesByCategory {
            let title = Self.text("\(group.category.displayName) (\(group.entries.count))", size: 14, weight: .semibold)
            // The heading stays with its first item.
            let firstHeight = group.entries.first.map { blockHeight(of: $0) } ?? 0
            cursor.reserve(Self.height(of: title, width: contentWidth) + 8 + firstHeight)
            place(title, on: cursor, spacingAfter: 8)
            for entry in group.entries { place(entry, on: cursor) }
            cursor.y += 6
        }
        return cursor.pages
    }

    private func place(_ text: NSAttributedString, on cursor: Cursor, spacingAfter: CGFloat) {
        let height = Self.height(of: text, width: contentWidth)
        cursor.reserve(height)
        cursor.add(.text(text, CGRect(x: margin, y: cursor.y, width: contentWidth, height: height)))
        cursor.y += height + spacingAfter
    }

    private func placeRule(on cursor: Cursor, spacingAfter: CGFloat) {
        cursor.reserve(1)
        cursor.add(.rule(CGRect(x: margin, y: cursor.y, width: contentWidth, height: 0.5)))
        cursor.y += 0.5 + spacingAfter
    }

    // MARK: Entries

    /// An entry's name, value and details, measured for the column beside its cover photo.
    private struct EntryText {
        let name: NSAttributedString
        let nameHeight: CGFloat
        let details: NSAttributedString?
        let detailsHeight: CGFloat
        let x: CGFloat
        let width: CGFloat
        let nameWidth: CGFloat

        var height: CGFloat { nameHeight + (details == nil ? 0 : 3 + detailsHeight) }
    }

    private let valueWidth: CGFloat = 110

    private func entryText(for entry: InsurerReport.Entry) -> EntryText {
        let x = margin + (entry.photos.isEmpty ? 0 : coverSize.width + 12)
        let width = pageSize.width - margin - x
        let nameWidth = width - (entry.value == nil ? 0 : valueWidth + gap)
        let name = Self.text(entry.name, size: 12, weight: .semibold)
        let details = entry.details.isEmpty ? nil : Self.text(
            entry.details.map { "\($0.label): \($0.value)" }.joined(separator: "\n"),
            size: 9.5, color: Self.detail, lineSpacing: 2)
        return EntryText(name: name, nameHeight: Self.height(of: name, width: nameWidth), details: details,
                         detailsHeight: details.map { Self.height(of: $0, width: width) } ?? 0,
                         x: x, width: width, nameWidth: nameWidth)
    }

    /// The height of an entry's first block: its text beside its cover photo.
    private func blockHeight(of entry: InsurerReport.Entry) -> CGFloat {
        max(entryText(for: entry).height, entry.photos.isEmpty ? 0 : coverSize.height)
    }

    private func place(_ entry: InsurerReport.Entry, on cursor: Cursor) {
        let text = entryText(for: entry)
        let height = max(text.height, entry.photos.isEmpty ? 0 : coverSize.height)
        cursor.reserve(height)
        let top = cursor.y
        if let cover = entry.photos.first {
            cursor.add(.photo(cover.jpeg, Self.fit(cover, in: CGRect(origin: CGPoint(x: margin, y: top), size: coverSize))))
        }
        cursor.add(.text(text.name, CGRect(x: text.x, y: top, width: text.nameWidth, height: text.nameHeight)))
        if let value = entry.value {
            let amount = Self.text(CurrencyFormatter.formatWithDecimals(value), size: 12, weight: .semibold, alignment: .right)
            cursor.add(.text(amount, CGRect(x: pageSize.width - margin - valueWidth, y: top, width: valueWidth,
                                            height: Self.height(of: amount, width: valueWidth))))
        }
        if let details = text.details {
            cursor.add(.text(details, CGRect(x: text.x, y: top + text.nameHeight + 3, width: text.width,
                                             height: text.detailsHeight)))
        }
        cursor.y = top + height + 10
        placeRows(of: Array(entry.photos.dropFirst()), on: cursor)
    }

    /// An item's other photos, in rows under its details, each with its caption.
    private func placeRows(of photos: [InsurerReport.Photo], on cursor: Cursor) {
        guard !photos.isEmpty else { return }
        let width = (contentWidth - CGFloat(photosPerRow - 1) * gap) / CGFloat(photosPerRow)
        let box = CGSize(width: width, height: width * 3 / 4)
        let captionLimit: CGFloat = 22
        for start in stride(from: 0, to: photos.count, by: photosPerRow) {
            let row = Array(photos[start..<min(start + photosPerRow, photos.count)])
            let captions = row.map { photo in
                photo.caption.map { Self.text($0, size: 8, color: Self.secondary) }
            }
            let captionHeight = captions.compactMap { $0 }
                .map { min(Self.height(of: $0, width: width), captionLimit) }.max() ?? 0
            let rowHeight = box.height + (captionHeight > 0 ? 3 + captionHeight : 0)
            cursor.reserve(rowHeight)
            for (column, photo) in row.enumerated() {
                let x = margin + CGFloat(column) * (width + gap)
                cursor.add(.photo(photo.jpeg, Self.fit(photo, in: CGRect(origin: CGPoint(x: x, y: cursor.y), size: box))))
                if let caption = captions[column] {
                    cursor.add(.text(caption, CGRect(x: x, y: cursor.y + box.height + 3, width: width, height: captionHeight)))
                }
            }
            cursor.y += rowHeight + 10
        }
    }

    // MARK: - Text and geometry

    private static let secondary = UIColor(white: 0.4, alpha: 1)
    private static let detail = UIColor(white: 0.2, alpha: 1)
    private static let textOptions: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine]

    private static func text(_ string: String, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor = .black,
                             alignment: NSTextAlignment = .left, lineSpacing: CGFloat = 0) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineSpacing = lineSpacing
        return NSAttributedString(string: string, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }

    private static func height(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        ceil(text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                               options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }

    /// The largest rectangle of the photo's shape inside `box`, against its top-left corner.
    private static func fit(_ photo: InsurerReport.Photo, in box: CGRect) -> CGRect {
        guard photo.pixelWidth > 0, photo.pixelHeight > 0 else { return box }
        let scale = min(box.width / CGFloat(photo.pixelWidth), box.height / CGFloat(photo.pixelHeight))
        return CGRect(x: box.minX, y: box.minY, width: CGFloat(photo.pixelWidth) * scale,
                      height: CGFloat(photo.pixelHeight) * scale)
    }
}
