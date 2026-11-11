//
//  InsurerReportTests.swift
//  ShutterManagerTests
//
//  The report for the user's insurer: what it lists, its totals, its photos, and that the layout
//  stays on the page and the PDF says what the report says.
//

import Foundation
import PDFKit
import SwiftData
import UIKit
import Testing
@testable import ShutterManager

@MainActor
struct InsurerReportTests {
    private let prepared = Date(timeIntervalSince1970: 1_760_000_000)

    /// A solid-color JPEG of the given size.
    private func jpeg(width: CGFloat, height: CGFloat, color: UIColor = .gray) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try #require(image.jpegData(compressionQuality: 0.8))
    }

    @Test func detailsListWhatIdentifiesAnItem() throws {
        let container = try TestSupport.makeContainer()
        let body = TestSupport.insertSampleBody(into: container.mainContext)
        body.upcCode = "018208994984"
        let details = InsurerReport.details(for: body)
        #expect(details.map(\.label) == ["Serial number", "Year made", "Purchased", "Purchase price", "Current value",
                                         "Shutter count", "Product code"])
        #expect(details.first { $0.label == "Serial number" }?.value == "3000123")
        #expect(details.first { $0.label == "Year made" }?.value == "2024")
        #expect(details.first { $0.label == "Purchase price" }?.value == CurrencyFormatter.formatWithDecimals(Decimal(string: "2499.99")))
        let count = try #require(details.first { $0.label == "Shutter count" }?.value)
        #expect(count.hasPrefix(18_500.formatted()), "The latest reading, not the first")
        #expect(!details.contains { $0.value.contains("Main body") }, "Notes are the owner's own")
    }

    @Test func aLensHasNoShutterCountAndBlanksAreLeftOut() throws {
        let container = try TestSupport.makeContainer()
        let lens = TestSupport.insertSampleLens(into: container.mainContext)
        lens.serialNumber = "  "
        #expect(InsurerReport.details(for: lens).map(\.label) == ["Purchase price"])
    }

    @Test func totalsSayHowManyItemsTheyCover() async throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = TestSupport.insertSampleBody(into: context)
        let lens = TestSupport.insertSampleLens(into: context)
        let strap = GearItem(category: .accessory, make: "Peak", model: "Strap")
        context.insert(strap)

        let report = await InsurerReport.make(items: [strap, lens, body], options: .init(), preparedDate: prepared)
        #expect(report.entries.count == 3)
        // Current value where there is one (the body), else what was paid (the lens).
        #expect(report.totalValue == Decimal(string: "2100.07")! + 1999)
        #expect(report.totalPurchasePrice == Decimal(string: "2499.99")! + 1999)
        #expect(report.entriesWithValue == 2)
        let lines = report.summaryLines
        #expect(lines.first?.value == "3")
        #expect(lines.first { $0.label == "Total value" }?.value.hasSuffix("(2 of 3 items have one)") == true)

        let priced = await InsurerReport.make(items: [lens, body], options: .init(), preparedDate: prepared)
        #expect(priced.summaryLines.first { $0.label == "Total value" }?.value
                == CurrencyFormatter.formatWithDecimals(priced.totalValue), "Nothing to qualify when every item has a value")
    }

    @Test func entriesAreGroupedByCategoryThenName() async throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let zoom = TestSupport.insertSampleLens(into: context)
        let prime = GearItem(category: .lens, make: "Nikon", model: "Z 50mm f/1.8 S")
        context.insert(prime)
        let body = TestSupport.insertSampleBody(into: context)

        let report = await InsurerReport.make(items: [prime, zoom, body], options: .init(), preparedDate: prepared)
        let groups = report.entriesByCategory
        #expect(groups.map(\.category) == [.cameraBody, .lens])
        #expect(groups[1].entries.map(\.name) == ["Nikon Z 24-70mm f/2.8 S", "Nikon Z 50mm f/1.8 S"])
    }

    @Test func photosFollowTheChoiceCoverFirst() async throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = TestSupport.insertSampleBody(into: context)
        let plate = GearPhoto(imageData: try jpeg(width: 1200, height: 900), caption: "Serial plate", order: 0)
        plate.gearItem = body
        context.insert(plate)
        let front = GearPhoto(imageData: try jpeg(width: 600, height: 1200), caption: " ", order: 1, isPrimary: true)
        front.gearItem = body
        context.insert(front)
        let broken = GearPhoto(imageData: Data("not an image".utf8), order: 2)
        broken.gearItem = body
        context.insert(broken)

        var options = InsurerReport.Options()
        options.photos = .none
        #expect(await InsurerReport.make(items: [body], options: options).entries[0].photos.isEmpty)

        options.photos = .cover
        let cover = await InsurerReport.make(items: [body], options: options).entries[0].photos
        #expect(cover.count == 1)
        #expect(cover[0].pixelHeight == Int(InsurerReport.photoPixelSize), "The primary photo, shrunk to the report's size")
        #expect(cover[0].pixelWidth == Int(InsurerReport.photoPixelSize) / 2)
        #expect(cover[0].caption == nil, "A blank caption is no caption")

        options.photos = .all
        let all = await InsurerReport.make(items: [body], options: options).entries[0].photos
        #expect(all.count == 2, "A photo that can't be read is left out")
        #expect(all[1].caption == "Serial plate")
        #expect(all[1].jpeg.count < 40_000)
    }

    @Test func ownerAndReferenceAreTrimmed() async {
        let report = await InsurerReport.make(items: [], options: .init(ownerName: "  Ada Lovelace\n", reference: " P-123 "),
                                              preparedDate: prepared)
        #expect(report.ownerName == "Ada Lovelace")
        #expect(report.reference == "P-123")
    }

    // MARK: - Layout and PDF

    /// A report long enough to break pages, with long names, captions and every photo shape.
    private func longReport() throws -> InsurerReport {
        let wide = InsurerReport.Photo(jpeg: try jpeg(width: 40, height: 30), pixelWidth: 420, pixelHeight: 315, caption: nil)
        let tall = InsurerReport.Photo(jpeg: try jpeg(width: 30, height: 40), pixelWidth: 210, pixelHeight: 420,
                                       caption: "The serial plate, under the battery door, photographed in daylight")
        let entries = (0..<70).map { index -> InsurerReport.Entry in
            let name = index % 9 == 0
                ? "Item \(index) with a very long name that has to wrap onto a second line beside its value on the page"
                : "Item \(index)"
            let photos: [InsurerReport.Photo] = switch index % 4 {
            case 0: []
            case 1: [wide]
            case 2: [tall, wide, tall, wide, tall, wide]
            default: [wide, tall]
            }
            return InsurerReport.Entry(
                id: UUID(), name: name, category: GearCategory.allCases[index % GearCategory.allCases.count],
                details: [.init(label: "Serial number", value: "SN-\(index)"), .init(label: "Purchased", value: "Jan 1, 2024")],
                purchasePrice: index % 5 == 0 ? nil : Decimal(index * 100), currentValue: nil, photos: photos)
        }
        return InsurerReport(preparedDate: prepared, ownerName: "Ada Lovelace", reference: "P-123", entries: entries)
    }

    @Test(arguments: [PrintPaper.letter, PrintPaper.a4])
    func everyElementStaysOnThePage(paper: CGSize) throws {
        let renderer = InsurerReportRenderer(pageSize: paper)
        let pages = renderer.pages(for: try longReport())
        #expect(pages.count > 3)
        // Half a point of slack for a hairline at the foot of a page.
        let allowed = renderer.contentFrame.insetBy(dx: -0.5, dy: -0.5)
        for (index, page) in pages.enumerated() {
            #expect(!page.isEmpty, "Page \(index + 1) is blank")
            for element in page {
                #expect(allowed.contains(element.frame), "Page \(index + 1): \(element.frame) leaves \(allowed)")
            }
        }
        let photos = pages.joined().filter { element in
            if case .photo = element { return true }
            return false
        }
        #expect(photos.count == 18 * 1 + 17 * 6 + 17 * 2, "Every photo is placed once")
    }

    @Test func photosKeepTheirShape() throws {
        let tall = InsurerReport.Photo(jpeg: try jpeg(width: 30, height: 40), pixelWidth: 300, pixelHeight: 400, caption: nil)
        let entry = InsurerReport.Entry(id: UUID(), name: "Body", category: .cameraBody, details: [], purchasePrice: nil,
                                        currentValue: nil, photos: [tall])
        let report = InsurerReport(preparedDate: prepared, ownerName: "", reference: "", entries: [entry])
        let frames = InsurerReportRenderer(pageSize: PrintPaper.letter).pages(for: report).joined()
            .compactMap { element -> CGRect? in
                if case .photo(_, let frame) = element { return frame }
                return nil
            }
        let frame = try #require(frames.first)
        #expect(abs(frame.width / frame.height - 0.75) < 0.01)
    }

    @Test func thePDFSaysWhatTheReportSays() throws {
        let report = try longReport()
        let renderer = InsurerReportRenderer(pageSize: PrintPaper.a4)
        let document = try #require(PDFDocument(data: renderer.pdfData(for: report)))
        #expect(document.pageCount == renderer.pages(for: report).count)
        let first = try #require(document.page(at: 0))
        #expect(first.bounds(for: .mediaBox).size == PrintPaper.a4)
        let text = try #require(document.string)
        #expect(text.contains(InsurerReport.title))
        #expect(text.contains("A report for your insurer"))
        #expect(text.contains("Owner: Ada Lovelace"))
        #expect(text.contains("Reference: P-123"))
        #expect(text.contains("Serial number: SN-69"))
        #expect(text.contains("Page 1 of \(document.pageCount)"))
        #expect(text.contains("not a valuation"))
        #expect(!text.localizedCaseInsensitiveContains("insurance"), "It's a report for your insurer, nothing more")
    }

    @Test func anEmptyReportIsOnePage() throws {
        let report = InsurerReport(preparedDate: prepared, ownerName: "", reference: "", entries: [])
        let renderer = InsurerReportRenderer(pageSize: PrintPaper.letter)
        #expect(renderer.pages(for: report).count == 1)
        let text = try #require(PDFDocument(data: renderer.pdfData(for: report))?.string)
        #expect(text.contains("No gear in this report."))
        #expect(!text.contains("Owner:"))
    }

    @Test func theFileIsNamedForTheInsurersInbox() async throws {
        let report = InsurerReport(preparedDate: prepared, ownerName: "", reference: "", entries: [])
        let first = try await InsurerReportRenderer.writeFile(for: report)
        #expect(first.lastPathComponent.hasPrefix("Gear Inventory 2025-10-"))
        #expect(first.pathExtension == "pdf")
        #expect(FileManager.default.fileExists(atPath: first.path))
        // The next report replaces it, so reports don't pile up in the temporary directory.
        let later = InsurerReport(preparedDate: prepared.addingTimeInterval(40 * 86_400), ownerName: "", reference: "", entries: [])
        let second = try await InsurerReportRenderer.writeFile(for: later)
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(!FileManager.default.fileExists(atPath: first.path))
    }

    @Test func paperFollowsTheRegion() {
        #expect(PrintPaper.size(for: Locale(identifier: "en_US")) == PrintPaper.letter)
        #expect(PrintPaper.size(for: Locale(identifier: "fr_CA")) == PrintPaper.letter)
        #expect(PrintPaper.size(for: Locale(identifier: "en_GB")) == PrintPaper.a4)
        #expect(PrintPaper.size(for: Locale(identifier: "ja_JP")) == PrintPaper.a4)
    }
}
