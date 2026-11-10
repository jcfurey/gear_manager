//
//  PhotoUsageTests.swift
//  ShutterManagerTests
//
//  Usage from Photos: counting shots per body and lens, and matching them to the inventory.
//  Foundation-only, so it also runs on Linux.
//

import Foundation
import Testing
@testable import ShutterManager

struct PhotoUsageTests {
    private static let start = Date(timeIntervalSince1970: 1_750_000_000)

    private static func candidate(_ make: String, _ model: String, serial: String = "",
                                  category: GearCategory = .cameraBody) -> PhotoUsageCandidate {
        PhotoUsageCandidate(id: UUID(), make: make, model: model, serialNumber: serial, category: category)
    }

    private static func camera(_ make: String?, _ model: String?, serial: String? = nil) -> PhotoUsageGroup {
        PhotoUsageGroup(kind: .camera, make: make, model: model, serialNumber: serial)
    }

    private static func lens(_ make: String?, _ model: String?, serial: String? = nil) -> PhotoUsageGroup {
        PhotoUsageGroup(kind: .lens, make: make, model: model, serialNumber: serial)
    }

    private static func shot(camera: String? = "Z8", serial: String? = "4000001", lens: String? = "NIKKOR Z 50mm f/1.8 S",
                             count: Int? = nil, minutes: Double? = 0) -> PhotoUsageSample {
        PhotoUsageSample(cameraMake: camera == nil ? nil : "Nikon", cameraModel: camera, bodySerialNumber: serial,
                         lensMake: nil, lensModel: lens, lensSerialNumber: nil, shutterCount: count,
                         dateTaken: minutes.map { start.addingTimeInterval($0 * 60) })
    }

    // MARK: - Names and serial numbers

    @Test func namesCompareWithoutCaseSpacesOrPunctuation() {
        #expect(PhotoUsageMatcher.normalizedName("RF 24-70mm f/2.8L IS USM") == "rf2470mmf28lisusm")
        #expect(PhotoUsageMatcher.normalizedName("RF24-70mm F2.8 L IS USM") == "rf2470mmf28lisusm")
        #expect(PhotoUsageMatcher.normalizedName(nil).isEmpty)
    }

    /// Nikon's files say "Z 6_2" and "Z6_3" for the Z6 II and Z6 III.
    @Test func nikonGenerationSuffixesReadAsNumerals() {
        #expect(PhotoUsageMatcher.normalizedName("Z 6_2") == PhotoUsageMatcher.normalizedName("Z6 II"))
        #expect(PhotoUsageMatcher.normalizedName("Z6_3") == PhotoUsageMatcher.normalizedName("Z6 III"))
        #expect(PhotoUsageMatcher.normalizedName("D850") == "d850")
    }

    @Test func serialNumbersCompareWithoutPaddingOrCase() {
        #expect(PhotoUsageMatcher.normalizedSerial("0003000123") == "3000123")
        #expect(PhotoUsageMatcher.normalizedSerial(" 5ab-12345 ") == "5AB12345")
        #expect(PhotoUsageMatcher.normalizedSerial(nil).isEmpty)
    }

    @Test func makesAgreeWhenOneIsUnknownOrALongerFormOfTheOther() {
        #expect(PhotoUsageMatcher.makesAgree("Nikon", "NIKON CORPORATION"))
        #expect(PhotoUsageMatcher.makesAgree("", "Sony"))
        #expect(PhotoUsageMatcher.makesAgree(nil, nil))
        #expect(!PhotoUsageMatcher.makesAgree("Sigma", "Sony"))
    }

    // MARK: - Matching

    @Test func aSerialNumberSettlesIt() {
        let mine = Self.candidate("Nikon", "Z6 III", serial: "3000123")
        let other = Self.candidate("Nikon", "Z6 III", serial: "3000999")
        let group = Self.camera("Nikon", "Z6_3", serial: "3000123")
        #expect(PhotoUsageMatcher.match(group, among: [other, mine]) == .item(mine.id))
    }

    /// The item is named another way, as a Sony body is ("ILCE-7M4" for an α7 IV), but its serial
    /// number is the photo's.
    @Test func aSerialNumberMatchesAnItemNamedAnotherWay() {
        let body = Self.candidate("Sony", "A7 IV", serial: "1234567")
        #expect(PhotoUsageMatcher.match(Self.camera("Sony", "ILCE-7M4", serial: "01234567"), among: [body]) == .item(body.id))
    }

    @Test func aNameMatchesAnItemWithNoSerialNumber() {
        let body = Self.candidate("Nikon", "Z6 III")
        #expect(PhotoUsageMatcher.match(Self.camera("Nikon", "Z6_3", serial: "3000123"), among: [body]) == .item(body.id))
        #expect(PhotoUsageMatcher.match(Self.camera("Nikon", "Z6_3"), among: [body]) == .item(body.id))
    }

    /// The same model with another serial number is someone else's copy, or one since sold.
    @Test func anotherCopyOfTheModelIsNotAMatch() {
        let body = Self.candidate("Nikon", "Z6 III", serial: "3000999")
        #expect(PhotoUsageMatcher.match(Self.camera("Nikon", "Z6_3", serial: "3000123"), among: [body]) == .unmatched)
    }

    @Test func twoCopiesWithNothingToTellThemApartAreAmbiguous() {
        let first = Self.candidate("Nikon", "Z6 III"), second = Self.candidate("Nikon", "Z6 III")
        let match = PhotoUsageMatcher.match(Self.camera("Nikon", "Z6_3"), among: [first, second])
        #expect(match == .ambiguous([first.id, second.id]))
        // A serial number on one of them leaves the other as the only open choice.
        let known = PhotoUsageCandidate(id: first.id, make: "Nikon", model: "Z6 III", serialNumber: "3000999",
                                        category: .cameraBody)
        #expect(PhotoUsageMatcher.match(Self.camera("Nikon", "Z6_3", serial: "3000123"), among: [known, second])
                == .item(second.id))
    }

    /// A lens's own name starts with its line; the item was typed without it.
    @Test func aLensMatchesWhenOneNameEndsInTheOther() {
        let lens = Self.candidate("Nikon", "Z 24-70mm f/2.8 S", category: .lens)
        #expect(PhotoUsageMatcher.match(Self.lens("Nikon", "NIKKOR Z 24-70mm f/2.8 S"), among: [lens]) == .item(lens.id))
        // An exact name wins over a longer one that merely ends the same way.
        let exact = Self.candidate("Nikon", "NIKKOR Z 24-70mm f/2.8 S", category: .lens)
        #expect(PhotoUsageMatcher.match(Self.lens("Nikon", "NIKKOR Z 24-70mm f/2.8 S"), among: [lens, exact]) == .item(exact.id))
        // Too little to go on: "f/2" ends many names.
        let vague = Self.candidate("", "F2", category: .lens)
        #expect(PhotoUsageMatcher.match(Self.lens(nil, "XF35mmF2"), among: [vague]) == .unmatched)
    }

    @Test func theWholeNameInOneFieldStillMatches() {
        let body = Self.candidate("", "Fujifilm X-T5")
        #expect(PhotoUsageMatcher.match(Self.camera("Fujifilm", "X-T5"), among: [body]) == .item(body.id))
    }

    @Test func aDifferentMakeIsNotAMatch() {
        let lens = Self.candidate("Sigma", "35mm F1.4 DG DN", category: .lens)
        #expect(PhotoUsageMatcher.match(Self.lens("Sony", "35mm F1.4 DG DN"), among: [lens]) == .unmatched)
        #expect(PhotoUsageMatcher.match(Self.lens(nil, "35mm F1.4 DG DN"), among: [lens]) == .item(lens.id))
    }

    /// A lens is never a camera, even with the same serial number; "Other" could be either.
    @Test func camerasAndLensesMatchTheirOwnKind() {
        let lens = Self.candidate("Nikon", "Z8", serial: "4000001", category: .lens)
        let tripod = Self.candidate("Nikon", "Z8", category: .support)
        #expect(PhotoUsageMatcher.match(Self.camera("Nikon", "Z8", serial: "4000001"), among: [lens, tripod]) == .unmatched)
        let other = Self.candidate("Nikon", "Z8", category: .other)
        #expect(PhotoUsageMatcher.match(Self.camera("Nikon", "Z8"), among: [other]) == .item(other.id))
        #expect(PhotoUsageMatcher.match(Self.lens(nil, "Z8"), among: [other]) == .item(other.id))
    }

    @Test func aRememberedChoiceWinsWhileItsItemExists() {
        let named = Self.candidate("Sony", "ILCE-7M4")
        let chosen = Self.candidate("Sony", "A7 IV")
        let group = Self.camera("Sony", "ILCE-7M4")
        #expect(PhotoUsageMatcher.match(group, among: [named, chosen], remembered: [group.key: chosen.id]) == .item(chosen.id))
        // The remembered item is gone: matching goes back to the name.
        #expect(PhotoUsageMatcher.match(group, among: [named], remembered: [group.key: chosen.id]) == .item(named.id))
        // A remembered lens is never taken for a camera.
        let lens = Self.candidate("Sony", "FE 50mm F1.2 GM", category: .lens)
        #expect(PhotoUsageMatcher.match(group, among: [lens], remembered: [group.key: lens.id]) == .unmatched)
    }

    @Test func aGroupsKeyIsTheSameHoweverItsNameIsWritten() {
        #expect(Self.camera("NIKON", "Z 6_2", serial: "0006012345").key == Self.camera("Nikon", "Z6 II", serial: "6012345").key)
        #expect(Self.camera("Nikon", "Z8").key != Self.lens("Nikon", "Z8").key)
        #expect(Self.camera("Nikon", "Z8", serial: "1").key != Self.camera("Nikon", "Z8", serial: "2").key)
    }

    // MARK: - Counting

    @Test func shotsAreCountedPerBodyAndLens() {
        let samples = [
            Self.shot(minutes: 0), Self.shot(minutes: 5), Self.shot(lens: "NIKKOR Z 24-70mm f/2.8 S", minutes: 90),
            Self.shot(camera: "Z6_3", serial: "3000123", minutes: 30),
            Self.shot(camera: nil, serial: nil, lens: nil, minutes: nil)
        ]
        let summary = PhotoUsageSummary(samples: samples, candidates: [])
        #expect(summary.photoCount == 5)
        #expect(summary.unnamedCameraCount == 1)
        #expect(summary.unnamedLensCount == 1)
        #expect(summary.firstDate == Self.start)
        #expect(summary.lastDate == Self.start.addingTimeInterval(90 * 60))

        #expect(summary.cameras.map(\.photoCount) == [3, 1], "Most photos first")
        #expect(summary.cameras.map(\.displayName) == ["Nikon Z8", "Nikon Z6_3"])
        #expect(summary.cameras[0].firstDate == Self.start)
        #expect(summary.cameras[0].lastDate == Self.start.addingTimeInterval(90 * 60))
        #expect(summary.lenses.map(\.photoCount) == [3, 1])
        #expect(summary.lenses[0].displayName == "NIKKOR Z 50mm f/1.8 S")
        #expect(summary.groups.count == 4)
        #expect(summary.groups.allSatisfy { $0.match == .unmatched })
    }

    /// Two bodies of one model are told apart by serial number.
    @Test func twoBodiesOfOneModelAreCountedApart() {
        let first = Self.candidate("Nikon", "Z8", serial: "4000001"), second = Self.candidate("Nikon", "Z8", serial: "4000002")
        let samples = [Self.shot(serial: "4000001"), Self.shot(serial: "4000002"), Self.shot(serial: "4000002")]
        let summary = PhotoUsageSummary(samples: samples, candidates: [first, second])
        #expect(summary.cameras.map(\.photoCount) == [2, 1])
        #expect(summary.cameras.map(\.match) == [.item(second.id), .item(first.id)])
        #expect(summary.lenses.map(\.photoCount) == [3], "One lens went on both")
    }

    @Test func theLatestPhotosShutterCountIsKept() {
        let samples = [
            Self.shot(count: 20_010, minutes: 10), Self.shot(count: 20_030, minutes: 30),
            Self.shot(count: 20_020, minutes: 20), Self.shot(minutes: 40)
        ]
        let body = PhotoUsageSummary(samples: samples, candidates: []).cameras[0]
        #expect(body.shutterCount == 20_030)
        #expect(body.shutterCountDate == Self.start.addingTimeInterval(30 * 60))
    }

    /// After a shutter replacement the count starts again: the later photo still decides.
    @Test func aLaterPhotoWithALowerCountWins() {
        let samples = [Self.shot(count: 180_000, minutes: 0), Self.shot(count: 12, minutes: 600)]
        let body = PhotoUsageSummary(samples: samples, candidates: []).cameras[0]
        #expect(body.shutterCount == 12)
    }

    @Test func undatedPhotosFallBackToTheHigherCount() {
        let samples = [Self.shot(count: 500, minutes: nil), Self.shot(count: 400, minutes: nil), Self.shot(count: 450, minutes: 5)]
        let body = PhotoUsageSummary(samples: samples, candidates: []).cameras[0]
        #expect(body.shutterCount == 500)
        #expect(body.shutterCountDate == nil)
        #expect(body.firstDate == Self.start.addingTimeInterval(300), "Only dated photos set the dates")
    }

    @Test func anEmptyBatchIsEmpty() {
        let summary = PhotoUsageSummary(samples: [], candidates: [Self.candidate("Nikon", "Z8")])
        #expect(summary.photoCount == 0)
        #expect(summary.groups.isEmpty)
        #expect(summary.firstDate == nil)
    }

    @Test func aNamelessBodyIsShownByItsSerialNumber() {
        #expect(Self.camera(nil, nil, serial: "777").displayName == "Serial number 777")
        #expect(Self.lens("Sigma", nil, serial: "9").displayName == "Sigma lens")
    }
}
