//
//  LabelTests.swift
//  ShutterManagerTests
//
//  QR labels: the code itself, what a label says, the sheet's layout, and opening a label's link.
//

import CoreImage
import Foundation
import PDFKit
import SwiftData
import UIKit
import Testing
@testable import ShutterManager

@MainActor
struct LabelTests {
    private let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

    // MARK: - The code

    /// Whether the 7 × 7 block at (row, column) is a finder pattern: a dark ring, a light ring
    /// and a dark 3 × 3 middle.
    private func hasFinder(_ code: QRCode, row: Int, column: Int) -> Bool {
        for y in 0..<7 {
            for x in 0..<7 {
                let ring = max(abs(y - 3), abs(x - 3))
                if code.isDark(row: row + y, column: column + x) != (ring != 2) { return false }
            }
        }
        return true
    }

    @Test func aCodeHasItsFindersInThreeCorners() throws {
        let code = try #require(QRCode(LabelLink.kit(id).text))
        // Version 1 is 21 modules a side and each version adds 4.
        #expect(code.size >= 21 && (code.size - 21) % 4 == 0)
        #expect(code.size <= 33, "A label's link fits a version 4 code")
        let far = code.size - 7
        #expect(hasFinder(code, row: 0, column: 0))
        #expect(hasFinder(code, row: 0, column: far))
        #expect(hasFinder(code, row: far, column: 0))
        #expect(!hasFinder(code, row: far, column: far), "Upside down or mirrored, the empty corner would move")
    }

    @Test func aPrintedCodeReadsBackAsItsLink() throws {
        let link = LabelLink.gear(id)
        let image = try #require(QRCode(link.text)).image(side: 300)
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                               options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let features = detector.features(in: try #require(CIImage(image: image)))
        let message = try #require((features.first as? CIQRCodeFeature)?.messageString)
        #expect(LabelLink(text: message) == link)
    }

    @Test func theCodeKeepsItsQuietZone() throws {
        let code = try #require(QRCode("shuttermanager://kit/\(id.uuidString)"))
        let frame = CGRect(x: 10, y: 20, width: 82, height: 82)
        let bounds = code.path(in: frame).boundingBoxOfPath
        let module = frame.width / CGFloat(code.size + 2 * QRCode.quietZone)
        #expect(abs(bounds.minX - (frame.minX + 4 * module)) < 0.001)
        #expect(abs(bounds.minY - (frame.minY + 4 * module)) < 0.001)
        #expect(abs(bounds.width - CGFloat(code.size) * module) < 0.001)
        #expect(abs(bounds.height - bounds.width) < 0.001)
    }

    @Test func differentLinksMakeDifferentCodes() throws {
        let kitCode = try #require(QRCode(LabelLink.kit(id).text))
        let gearCode = try #require(QRCode(LabelLink.gear(id).text))
        #expect(kitCode != gearCode)
        #expect(kitCode == QRCode(LabelLink.kit(id).text), "The same link always makes the same code")
    }

    // MARK: - What a label says

    @Test func aKitsLabelListsItsGear() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let body = TestSupport.insertSampleBody(into: context)
        let lens = TestSupport.insertSampleLens(into: context)
        let kit = Kit(name: " Wedding ")
        context.insert(kit)
        kit.gear = [lens, body]

        let label = GearLabel(kit: kit)
        #expect(label.link == .kit(kit.id))
        #expect(label.title == "Wedding")
        #expect(label.subtitle == "Kit · 2 items")
        #expect(label.contents == ["Nikon Z6 III", "Nikon Z 24-70mm f/2.8 S"], "Bodies before lenses, as the kit lists them")

        kit.gear = [body]
        #expect(GearLabel(kit: kit).subtitle == "Kit · 1 item")
    }

    @Test func anItemsLabelNamesItAndItsKind() throws {
        let container = try TestSupport.makeContainer()
        let body = TestSupport.insertSampleBody(into: container.mainContext)
        let label = GearLabel(item: body)
        #expect(label.link == .gear(body.id))
        #expect(label.title == "Nikon Z6 III")
        #expect(label.subtitle == "Camera Body")
        #expect(label.contents.isEmpty)
        #expect(!label.title.contains("3000123"), "The serial number stays off the label")
    }

    @Test func contentsThatDontFitSayHowManyMore() {
        let items = ["A", "B", "C", "D", "E"]
        #expect(LabelSheetRenderer.contentLines(items, limit: 5) == items)
        #expect(LabelSheetRenderer.contentLines(items, limit: 8) == items)
        #expect(LabelSheetRenderer.contentLines(items, limit: 3) == ["A", "B", "+ 3 more"])
        #expect(LabelSheetRenderer.contentLines(items, limit: 1) == ["+ 5 more"])
        #expect(LabelSheetRenderer.contentLines(items, limit: 0).isEmpty)
    }

    // MARK: - The sheet

    private func labels(_ count: Int) -> [GearLabel] {
        (0..<count).map { index in
            GearLabel(link: index % 2 == 0 ? .kit(UUID()) : .gear(UUID()),
                      title: index % 3 == 0 ? "A kit with a long name that has to wrap or be cut short \(index)" : "Label \(index)",
                      subtitle: "Kit · \(index) items",
                      contents: (0..<index).map { "Item \($0) with a fairly long name to cut short" })
        }
    }

    @Test(arguments: [LabelSheet.Size.large, .small], [PrintPaper.letter, PrintPaper.a4])
    func labelsFillThePageInAGrid(size: LabelSheet.Size, paper: CGSize) {
        let renderer = LabelSheetRenderer(pageSize: paper)
        let sheet = LabelSheet(labels: labels(size.perPage + 3), size: size, contactLine: "If found: 555-0100")
        let pages = renderer.pages(for: sheet)
        #expect(pages.count == 2)
        #expect(sheet.pageCount == 2)

        func cutLines(_ page: [PrintElement]) -> [CGRect] {
            page.compactMap { element -> CGRect? in
                if case .cutLine(let frame) = element { return frame }
                return nil
            }
        }
        #expect(cutLines(pages[0]).count == size.perPage)
        #expect(cutLines(pages[1]).count == 3)

        let allowed = renderer.contentFrame.insetBy(dx: -0.01, dy: -0.01)
        for page in pages {
            let cells = cutLines(page)
            for (index, cell) in cells.enumerated() {
                #expect(allowed.contains(cell))
                for other in cells[(index + 1)...] {
                    #expect(cell.insetBy(dx: 0.01, dy: 0.01).intersection(other).isEmpty, "Labels don't overlap")
                }
            }
            // Everything on a label stays inside one of the page's cells.
            for element in page {
                #expect(cells.contains { $0.insetBy(dx: -0.01, dy: -0.01).contains(element.frame) },
                        "\(element.frame) crosses a cut line")
            }
        }
        // The first label is top-left; the next is to its right.
        let first = cutLines(pages[0])
        #expect(first[0].minX == renderer.contentFrame.minX && first[0].minY == renderer.contentFrame.minY)
        #expect(first[1].minY == first[0].minY && first[1].minX > first[0].minX)
    }

    @Test func everyLabelHasACodeBigEnoughToScan() {
        let renderer = LabelSheetRenderer(pageSize: PrintPaper.a4)
        for size in LabelSheet.Size.allCases {
            let page = renderer.pages(for: LabelSheet(labels: labels(4), size: size))[0]
            let codes = page.compactMap { element -> (QRCode, CGRect)? in
                if case .code(let code, let frame) = element { return (code, frame) }
                return nil
            }
            #expect(codes.count == 4)
            for (code, frame) in codes {
                #expect(abs(frame.width - frame.height) < 0.001)
                // A module of at least half a millimetre (1.4 points) reads at arm's length.
                let module = frame.width / CGFloat(code.size + 2 * QRCode.quietZone)
                #expect(module >= 1.4, "\(size): a \(module)-point module is too fine to scan")
            }
        }
    }

    @Test func aSheetWithNothingOnItHasNoPages() {
        let sheet = LabelSheet(labels: [])
        #expect(sheet.pageCount == 0)
        #expect(LabelSheetRenderer(pageSize: PrintPaper.letter).pages(for: sheet).isEmpty)
    }

    @Test func thePDFCarriesTheLabelsText() throws {
        let sheet = LabelSheet(labels: [
            GearLabel(link: .kit(id), title: "Wedding", subtitle: "Kit · 2 items", contents: ["Nikon Z6 III", "Speedlight"])
        ], size: .large, contactLine: "If found: 555-0100")
        let document = try #require(PDFDocument(data: LabelSheetRenderer(pageSize: PrintPaper.letter).pdfData(for: sheet)))
        #expect(document.pageCount == 1)
        let text = try #require(document.string)
        #expect(text.contains("Wedding"))
        #expect(text.contains("Kit · 2 items"))
        #expect(text.contains("Speedlight"))
        #expect(text.contains("If found: 555-0100"))
        #expect(!text.contains(id.uuidString), "The ID is in the code, not in print")
    }

    // MARK: - Opening a label

    @Test func aLabelsLinkOpensItAndOtherLinksDont() throws {
        let navigation = AppNavigation()
        #expect(navigation.open(try #require(LabelLink.kit(id).url)))
        #expect(navigation.openedLabel == .kit(id))

        navigation.openedLabel = nil
        #expect(!navigation.open(try #require(URL(string: "shuttermanager://settings"))))
        #expect(!navigation.open(try #require(URL(string: "https://example.com/kit/\(id.uuidString)"))))
        #expect(navigation.openedLabel == nil)
    }

    @Test func theAppRegistersTheLabelScheme() throws {
        let types = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains(LabelLink.scheme), "The Camera app can't open a label unless the app claims its scheme")
    }
}
