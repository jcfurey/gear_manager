//
//  LabelSheetRenderer.swift
//  ShutterManager
//
//  Lays a `LabelSheet` out as a grid of labels to cut apart, for `PrintDocument` to draw as a PDF.
//

import UIKit

struct LabelSheetRenderer: Sendable {
    let pageSize: CGSize

    init(pageSize: CGSize = PrintPaper.size()) {
        self.pageSize = pageSize
    }

    static let title = "Gear Labels"

    private let margin: CGFloat = 36

    /// The area the grid of labels fills.
    var contentFrame: CGRect {
        CGRect(x: margin, y: margin, width: pageSize.width - 2 * margin, height: pageSize.height - 2 * margin)
    }

    /// Where label `index` of a page goes: left to right, then down.
    func cell(_ index: Int, size: LabelSheet.Size) -> CGRect {
        let width = contentFrame.width / CGFloat(size.columns)
        let height = contentFrame.height / CGFloat(size.rows)
        return CGRect(x: contentFrame.minX + CGFloat(index % size.columns) * width,
                      y: contentFrame.minY + CGFloat(index / size.columns) * height,
                      width: width, height: height)
    }

    // MARK: - PDF

    func pdfData(for sheet: LabelSheet) -> Data {
        PrintDocument.pdfData(pages: pages(for: sheet), pageSize: pageSize, title: Self.title)
    }

    static func fileName(for date: Date) -> String {
        "\(title) \(PrintDocument.dateStamp(date)).pdf"
    }

    /// Draws the labels off the main actor and writes them where the preview finds them.
    static func writeFile(for sheet: LabelSheet, date: Date = Date(), pageSize: CGSize = PrintPaper.size()) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let data = LabelSheetRenderer(pageSize: pageSize).pdfData(for: sheet)
            return try PrintDocument.write(data, named: fileName(for: date))
        }.value
    }

    // MARK: - Layout

    /// The sheet's pages, each a list of placed elements.
    func pages(for sheet: LabelSheet) -> [[PrintElement]] {
        let contact = sheet.contactLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return stride(from: 0, to: sheet.labels.count, by: sheet.size.perPage).map { start in
            let page = sheet.labels[start..<min(start + sheet.size.perPage, sheet.labels.count)]
            return page.enumerated().flatMap { index, label in
                elements(for: label, in: cell(index, size: sheet.size), size: sheet.size, contact: contact)
            }
        }
    }

    /// One label: its cut line, its code on the left, and its name, kind, contents and the
    /// contact line stacked on the right.
    private func elements(for label: GearLabel, in cell: CGRect, size: LabelSheet.Size, contact: String) -> [PrintElement] {
        let large = size == .large
        let inner = cell.insetBy(dx: large ? 10 : 7, dy: large ? 10 : 7)
        var elements: [PrintElement] = [.cutLine(cell)]

        let codeSide = min(inner.height, inner.width * 0.45)
        if let code = QRCode(label.link.text) {
            elements.append(.code(code, CGRect(x: inner.minX, y: inner.minY, width: codeSide, height: codeSide)))
        }

        let x = inner.minX + codeSide + (large ? 8 : 5)
        let width = inner.maxX - x
        var y = inner.minY + (large ? 4 : 2)

        // The contact line sits at the foot; everything else stacks from the top above it.
        var bottom = inner.maxY
        if !contact.isEmpty {
            let text = PrintDocument.text(contact, size: large ? 7.5 : 6.5, color: PrintDocument.secondary)
            let height = min(PrintDocument.height(of: text, width: width), Self.lineHeight(large ? 7.5 : 6.5) * 2)
            bottom -= height
            elements.append(.text(text, CGRect(x: x, y: bottom, width: width, height: height)))
            bottom -= 3
        }

        let title = PrintDocument.text(label.title, size: large ? 12 : 9.5, weight: .semibold)
        let titleHeight = min(PrintDocument.height(of: title, width: width), Self.lineHeight(large ? 12 : 9.5) * 2, bottom - y)
        elements.append(.text(title, CGRect(x: x, y: y, width: width, height: titleHeight)))
        y += titleHeight + 2

        let subtitle = PrintDocument.text(label.subtitle, size: large ? 9 : 7.5, color: PrintDocument.secondary,
                                          truncatesLines: true)
        let subtitleHeight = Self.lineHeight(large ? 9 : 7.5)
        if y + subtitleHeight <= bottom {
            elements.append(.text(subtitle, CGRect(x: x, y: y, width: width, height: subtitleHeight)))
            y += subtitleHeight + 4
        }

        // As many of a kit's items as there are lines for, the last line saying how many more.
        let contentSize: CGFloat = large ? 8 : 6.5
        let lines = Int((bottom - y) / Self.lineHeight(contentSize))
        if !label.contents.isEmpty, lines >= 2 {
            let text = PrintDocument.text(Self.contentLines(label.contents, limit: lines).joined(separator: "\n"),
                                          size: contentSize, color: UIColor(white: 0.2, alpha: 1), truncatesLines: true)
            elements.append(.text(text, CGRect(x: x, y: y, width: width, height: CGFloat(lines) * Self.lineHeight(contentSize))))
        }
        return elements
    }

    /// `items` cut to `limit` lines: when there are more, the last line counts the rest.
    static func contentLines(_ items: [String], limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        guard items.count > limit else { return items }
        return Array(items.prefix(limit - 1)) + ["+ \(items.count - limit + 1) more"]
    }

    private static func lineHeight(_ fontSize: CGFloat) -> CGFloat {
        ceil(UIFont.systemFont(ofSize: fontSize).lineHeight)
    }
}
