//
//  MountCompatibilityTests.swift
//  ShutterManagerTests
//
//  Which lenses go on which bodies: flange distances, adapters' mount names, makers' adapters,
//  the lists a body and a lens show, and the packing check. Foundation-only, so it also runs on
//  Linux.
//

import Foundation
import Testing
@testable import ShutterManager

struct MountCompatibilityTests {
    private static func gear(_ name: String, _ mount: String, _ category: GearCategory = .lens,
                             format: SensorFormat? = nil) -> MountedGear {
        MountedGear(id: UUID(), name: name, mount: mount, category: category, format: format)
    }

    private static func body(_ name: String, _ mount: String, format: SensorFormat? = nil) -> MountedGear {
        gear(name, mount, .cameraBody, format: format)
    }

    // MARK: - The catalog

    @Test func everyMountHasAFlangeDistance() {
        for mount in LensMount.all where !LensMount.isFixedLens(mount) {
            let distance = LensMount.flangeDistance(of: mount)
            #expect(distance != nil, "\(mount) has no flange distance")
            #expect((distance ?? 0) > 5 && (distance ?? 0) < 150, "\(mount): \(distance ?? 0) mm is not a flange distance")
        }
        let known = Set(LensMount.all.map(LensMount.normalized))
        for name in LensMount.flangeDistances.keys {
            #expect(known.contains(name), "\(name) isn't a mount in the catalog")
        }
        #expect(LensMount.flangeDistance(of: LensMount.fixedLens) == nil)
    }

    /// A few distances against their published figures, and one compared across systems.
    @Test func flangeDistancesAreThePublishedOnes() {
        #expect(LensMount.flangeDistance(of: "Nikon Z") == 16)
        #expect(LensMount.flangeDistance(of: " nikon f ") == 46.5)
        #expect(LensMount.flangeDistance(of: "Canon EF") == 44)
        #expect(LensMount.flangeDistance(of: "Leica M") == 27.8)
        #expect(LensMount.flangeDistance(of: "Micro Four Thirds") == 19.25)
        #expect(LensMount.flangeDistance(of: "Some Other Mount") == nil)
        // Every mirrorless mount sits closer to the sensor than every SLR mount.
        let mirrorless = LensMount.groups[0].mounts.compactMap(LensMount.flangeDistance(of:))
        let slr = LensMount.groups[1].mounts.compactMap(LensMount.flangeDistance(of:))
        #expect((mirrorless.max() ?? 0) < (slr.min() ?? 0))
    }

    // MARK: - Adapters' names

    @Test func anAdaptersMountNamesBothSides() {
        let name = LensMount.adapterName(lens: " Canon EF", body: "Canon RF ")
        #expect(name == "Canon EF → Canon RF")
        #expect(LensMount.adapterMounts(in: name) == LensMount.AdapterMounts(lens: "Canon EF", body: "Canon RF"))
        #expect(LensMount.adapterMounts(in: "Nikon F->Nikon Z") == LensMount.AdapterMounts(lens: "Nikon F", body: "Nikon Z"))
        #expect(LensMount.adapterMounts(in: "  M42  →  Sony E ") == LensMount.AdapterMounts(lens: "M42", body: "Sony E"))
        #expect(LensMount.isAdapter(name))
    }

    @Test func anOrdinaryMountIsNotAnAdapter() {
        for mount in LensMount.all + ["", "L-Mount", "Canon EF →", "→ Canon RF", "A → B → C", "Contax/Yashica"] {
            #expect(LensMount.adapterMounts(in: mount) == nil, "\(mount) read as an adapter")
        }
    }

    // MARK: - How a lens fits a body

    @Test func theSameMountFits() {
        #expect(MountCompatibility.fit(lensMount: "Nikon Z", bodyMount: "nikon z ") == .native)
        #expect(MountCompatibility.fit(lensMount: "Homemade", bodyMount: "homemade") == .native,
                "A mount the catalog doesn't know still fits itself")
        #expect(MountCompatibility.fit(lensMount: "Canon EF", bodyMount: "Canon EF-S") == .native,
                "A crop-sensor Canon SLR takes EF lenses")
    }

    @Test func aCropLensDoesNotGoOnAFullFrameCanonSLR() {
        guard case .blocked(let reason) = MountCompatibility.fit(lensMount: "Canon EF-S", bodyMount: "Canon EF") else {
            Issue.record("EF-S on EF should be blocked")
            return
        }
        #expect(reason.contains("EF-S"))
    }

    @Test func missingAndUnknownMountsCannotBeJudged() {
        #expect(MountCompatibility.fit(lensMount: "", bodyMount: "Nikon Z") == .unknown)
        #expect(MountCompatibility.fit(lensMount: "Nikon Z", bodyMount: "  ") == .unknown)
        #expect(MountCompatibility.fit(lensMount: "Homemade", bodyMount: "Nikon Z") == .unknown)
        #expect(MountCompatibility.fit(lensMount: "Nikon Z", bodyMount: "Fixed lens") == .fixedLens)
    }

    /// A lens made to sit further out leaves room for a spacer; one made to sit closer can't be
    /// moved in.
    @Test func roomForAPlainAdapterComesFromTheFlangeDistances() {
        #expect(MountCompatibility.fit(lensMount: "Nikon F", bodyMount: "Canon EF") == .plainAdapter(room: 2.5))
        #expect(MountCompatibility.fit(lensMount: "Canon EF", bodyMount: "Nikon F") == .noPlainAdapter(shortfall: 2.5))
        #expect(MountCompatibility.fit(lensMount: "Canon FD", bodyMount: "Sony E") == .plainAdapter(room: 24))
        #expect(MountCompatibility.fit(lensMount: "Olympus OM", bodyMount: "Fujifilm X") == .plainAdapter(room: 28.3))
        #expect(MountCompatibility.fit(lensMount: "Sony E", bodyMount: "Nikon Z") == .plainAdapter(room: 2))
        // The screw-mount ring for Leica M bodies fills exactly the least room allowed.
        #expect(MountCompatibility.fit(lensMount: "M39", bodyMount: "Leica M") == .plainAdapter(room: 1))
        // Sigma's converters are for Sigma's lenses: a Canon EF lens gets no maker's adapter to L-Mount.
        #expect(MountCompatibility.fit(lensMount: "Canon EF", bodyMount: "L-Mount") == .plainAdapter(room: 24))
        // Half a millimetre is less than any adapter is thick.
        #expect(MountCompatibility.fit(lensMount: "Sony A", bodyMount: "Canon EF") == .noPlainAdapter(shortfall: 0))
        #expect(MountCompatibility.fit(lensMount: "Canon RF", bodyMount: "L-Mount") == .noPlainAdapter(shortfall: 0))
    }

    @Test func makersAdaptersAreNamed() {
        guard case .makerAdapter(let ftz) = MountCompatibility.fit(lensMount: "Nikon F", bodyMount: "Nikon Z") else {
            Issue.record("Nikon F lenses go on Z bodies with Nikon's adapter")
            return
        }
        #expect(ftz.name == "Nikon Mount Adapter FTZ II")
        guard case .makerAdapter(let canon) = MountCompatibility.fit(lensMount: "canon ef-s", bodyMount: "Canon RF") else {
            Issue.record("EF-S lenses go on RF bodies with Canon's adapter")
            return
        }
        #expect(canon.lensMounts.contains("Canon EF"))
        // The other way round there's no such thing: an RF lens sits too close for an EF body.
        #expect(MountCompatibility.fit(lensMount: "Canon RF", bodyMount: "Canon EF") == .noPlainAdapter(shortfall: 24))
    }

    /// Each maker's adapter names catalog mounts, and a plain one has the room the flange
    /// distances say it needs.
    @Test func makersAdaptersAgreeWithTheCatalog() {
        #expect(!MountCompatibility.makerAdapters.isEmpty)
        for adapter in MountCompatibility.makerAdapters {
            #expect(LensMount.all.contains(adapter.bodyMount), "\(adapter.name): \(adapter.bodyMount)")
            #expect(!adapter.lensMounts.isEmpty)
            for lensMount in adapter.lensMounts {
                #expect(LensMount.all.contains(lensMount), "\(adapter.name): \(lensMount)")
                guard let lens = LensMount.flangeDistance(of: lensMount),
                      let body = LensMount.flangeDistance(of: adapter.bodyMount) else { continue }
                #expect(lens >= body, "\(adapter.name) has no glass, so \(lensMount) can't sit closer than \(adapter.bodyMount)")
                guard case .makerAdapter(let found) = MountCompatibility.fit(lensMount: lensMount, bodyMount: adapter.bodyMount) else {
                    Issue.record("\(lensMount) on \(adapter.bodyMount) should name \(adapter.name)")
                    continue
                }
                #expect(found.bodyMount == adapter.bodyMount)
            }
        }
        let names = MountCompatibility.makerAdapters.map(\.name)
        #expect(Set(names).count == names.count, "Each adapter is listed once")
    }

    // MARK: - A lens and a body

    @Test func anAdapterYouOwnCounts() {
        let lens = Self.gear("Canon EF 50mm f/1.8", "Canon EF")
        let body = Self.body("Sony A7 IV", "Sony E")
        let without = LensBodyFit(lens: lens, body: body)
        #expect(without.group == .adapter)
        #expect(without.ownedAdapters.isEmpty)

        let adapter = Self.gear("Metabones EF-E", "Canon EF → Sony E")
        let wrongWay = Self.gear("Backwards", "Sony E → Canon EF")
        let elsewhere = Self.gear("FTZ II", "Nikon F → Nikon Z")
        let with = LensBodyFit(lens: lens, body: body, adapters: [wrongWay, adapter, elsewhere])
        #expect(with.ownedAdapters == ["Metabones EF-E"])
        #expect(with.group == .ownedAdapter)
        #expect(with.explanation == "Goes on with your Metabones EF-E.")
    }

    /// An adapter you own makes a pair work even where the flange distances say a plain one
    /// can't: it may have glass in it.
    @Test func anOwnedAdapterOverridesTheArithmetic() {
        let lens = Self.gear("Canon EF 50mm", "Canon EF")
        let body = Self.body("Nikon F6", "Nikon F")
        #expect(LensBodyFit(lens: lens, body: body).group == .doesNotFit)
        let adapter = Self.gear("EF-F with glass", "Canon EF -> Nikon F")
        #expect(LensBodyFit(lens: lens, body: body, adapters: [adapter]).group == .ownedAdapter)
    }

    /// Canon's adapter takes EF and EF-S lenses, whichever one the user named it by, and an
    /// adapter to EF goes on a crop-sensor EF-S body too.
    @Test func aMakersAdapterTakesItsWholeLensLine() {
        let adapter = LensMount.AdapterMounts(lens: "Canon EF", body: "Canon RF")
        #expect(MountCompatibility.adapter(adapter, joins: "Canon EF", to: "Canon RF"))
        #expect(MountCompatibility.adapter(adapter, joins: "Canon EF-S", to: "canon rf"))
        #expect(!MountCompatibility.adapter(adapter, joins: "Nikon F", to: "Canon RF"))
        #expect(!MountCompatibility.adapter(adapter, joins: "Canon EF", to: "Sony E"))
        let toSLR = LensMount.AdapterMounts(lens: "M42", body: "Canon EF")
        #expect(MountCompatibility.adapter(toSLR, joins: "M42", to: "Canon EF-S"))
    }

    @Test func aLensMadeForASmallerFormatSaysSo() {
        let cropLens = Self.gear("DX 35mm", "Nikon F", format: .apsC)
        let fullFrame = Self.body("D850", "Nikon F", format: .fullFrame)
        let onFullFrame = LensBodyFit(lens: cropLens, body: fullFrame)
        #expect(onFullFrame.group == .fits)
        #expect(onFullFrame.smallerFormat == "APS-C")
        #expect(onFullFrame.explanation == "Made for APS-C: expect a crop or dark corners on this body.")

        // The other way round, and between two makers' APS-C, the lens covers the sensor.
        let fullFrameLens = Self.gear("50mm", "Nikon F", format: .fullFrame)
        #expect(LensBodyFit(lens: fullFrameLens, body: Self.body("D500", "Nikon F", format: .apsC)).smallerFormat == nil)
        let canonCrop = Self.gear("EF-S 24mm", "Canon EF-S", format: .apsCCanon)
        #expect(LensBodyFit(lens: canonCrop, body: Self.body("X-T5", "Fujifilm X", format: .apsC)).smallerFormat == nil)
        // No format on either side: nothing to say.
        #expect(LensBodyFit(lens: Self.gear("50mm", "Nikon F"), body: fullFrame).smallerFormat == nil)
        #expect(LensBodyFit(lens: Self.gear("50mm", "Nikon F"), body: fullFrame).explanation.isEmpty)
    }

    @Test func eachKindOfFitIsExplained() {
        func explanation(_ lensMount: String, _ bodyMount: String) -> String {
            LensBodyFit(lens: Self.gear("Lens", lensMount), body: Self.body("Body", bodyMount)).explanation
        }
        #expect(explanation("Nikon F", "Nikon Z") == "Needs the Nikon Mount Adapter FTZ II.")
        #expect(explanation("M42", "Pentax K") == "Needs the Pentax Mount Adapter K.", "Equal flange distances, and still a maker's adapter")
        #expect(explanation("Nikon F", "Canon EF").hasPrefix("There's 2.5 mm of room"))
        #expect(explanation("Canon EF", "Nikon F").hasPrefix("The lens would sit 2.5 mm too far"))
        #expect(explanation("Sony A", "Canon EF") == "The two mounts are too close for an adapter to fit between them.")
        #expect(explanation("Canon EF-S", "Canon EF").contains("don't mount"))
        #expect(explanation("Nikon Z", "Fixed lens") == "The camera's lens doesn't come off.")
        #expect(explanation("Homemade", "Nikon Z") == "One of the mounts isn't one the app knows.")
        #expect(LensBodyFit.millimetres(28) == "28 mm")
        #expect(LensBodyFit.millimetres(1.7000000000000002) == "1.7 mm")
        #expect(LensBodyFit.millimetres(25.86) == "25.86 mm")
    }

    // MARK: - The lists

    @Test func aBodyListsTheLensesByHowTheyGoOn() {
        let body = Self.body("Nikon Z6 III", "Nikon Z")
        let native = Self.gear("Z 50mm f/1.8 S", "Nikon Z")
        let nativeToo = Self.gear("a 24-70", "nikon z")
        let fMount = Self.gear("AF-S 85mm", "Nikon F")
        let leica = Self.gear("Summicron 35", "Leica M")
        let owned = Self.gear("Summilux 50", "Leica M")
        let other = Self.gear("Old lens", "Homemade")
        let noMount = Self.gear("Unknown lens", "")
        let adapter = Self.gear("M to Z ring", "Leica M → Nikon Z")
        let secondBody = Self.body("Nikon D850", "Nikon F")
        let tripod = Self.gear("Tripod", "Nikon Z", .support)
        let inventory = [body, native, nativeToo, fMount, leica, owned, other, noMount, adapter, secondBody, tripod]

        let list = CompatibilityList(subject: body, inventory: inventory)
        #expect(list.role == .body)
        #expect(list.sections.map(\.group) == [.fits, .ownedAdapter, .adapter, .cannotTell])
        #expect(list.sections[0].entries.map(\.gear.name) == ["a 24-70", "Z 50mm f/1.8 S"], "By name, whatever the case")
        #expect(list.sections[1].entries.map(\.gear.name) == ["Summicron 35", "Summilux 50"])
        #expect(list.sections[2].entries.map(\.gear.name) == ["AF-S 85mm"])
        #expect(list.sections[3].entries.map(\.gear.name) == ["Old lens"])
        let listed = Set(list.sections.flatMap(\.entries).map(\.id))
        for left in [body, noMount, adapter, secondBody, tripod] {
            #expect(!listed.contains(left.id), "\(left.name) is not a lens with a mount")
        }
    }

    @Test func aLensListsTheBodies() {
        let lens = Self.gear("AF-S 85mm", "Nikon F")
        let dslr = Self.body("Nikon D850", "Nikon F")
        let mirrorless = Self.body("Nikon Z6 III", "Nikon Z")
        let canon = Self.body("Canon 5D", "Canon EF")
        let compact = Self.body("X100VI", "Fixed lens")
        let otherLens = Self.gear("Z 50mm", "Nikon Z")
        let list = CompatibilityList(subject: lens, inventory: [lens, dslr, mirrorless, canon, compact, otherLens])
        #expect(list.role == .lens)
        #expect(list.sections.map(\.group) == [.fits, .adapter, .doesNotFit])
        #expect(list.sections[0].entries.map(\.gear.name) == ["Nikon D850"])
        #expect(list.sections[1].entries.map(\.gear.name) == ["Canon 5D", "Nikon Z6 III"])
        #expect(list.sections[2].entries.map(\.gear.name) == ["X100VI"])
    }

    @Test func compatibilityAppliesOnlyToBodiesLensesAndAdapters() {
        #expect(CompatibilityList.role(of: Self.body("Body", "Nikon Z")) == .body)
        #expect(CompatibilityList.role(of: Self.gear("Lens", "Nikon Z")) == .lens)
        #expect(CompatibilityList.role(of: Self.gear("Ring", "M42 → Nikon Z")) == .adapter)
        #expect(CompatibilityList.role(of: Self.gear("Lens", "  ")) == nil)
        #expect(CompatibilityList.role(of: Self.gear("Drone", "Fixed lens", .drone)) == nil)
        let adapterList = CompatibilityList(subject: Self.gear("Ring", "M42 → Nikon Z"),
                                            inventory: [Self.body("Body", "Nikon Z"), Self.gear("Takumar", "M42")])
        #expect(adapterList.isEmpty)
    }

    // MARK: - Packing

    @Test func aLensWithNoBodyToGoOnIsFlaggedWhenPacking() {
        let zBody = Self.body("Z6 III", "Nikon Z")
        let fBody = Self.body("D850", "Nikon F")
        let zLens = Self.gear("Z 50mm", "Nikon Z")
        let fLens = Self.gear("AF-S 85mm", "Nikon F")
        let canonLens = Self.gear("RF 50mm", "Canon RF")
        let adapter = Self.gear("FTZ II", "Nikon F → Nikon Z")

        // Fits a packed body.
        #expect(CompatibilityList.packingIssue(for: zLens, among: [zBody, zLens]) == nil)
        #expect(CompatibilityList.packingIssue(for: fLens, among: [zBody, fBody, fLens]) == nil, "One body is enough")
        // Needs the maker's adapter, and it isn't packed; then it is.
        let needsAdapter = CompatibilityList.packingIssue(for: fLens, among: [zBody, fLens])
        #expect(needsAdapter?.hasPrefix("Needs the ") == true)
        #expect(needsAdapter?.hasSuffix("which isn't on this shoot") == true)
        #expect(CompatibilityList.packingIssue(for: fLens, among: [zBody, fLens, adapter]) == nil)
        // Room for a plain adapter, but none is packed.
        #expect(CompatibilityList.packingIssue(for: Self.gear("Rokkor", "Minolta MD"), among: [zBody])
                == "Needs an adapter for the bodies on this shoot")
        // Goes on nothing that's packed.
        #expect(CompatibilityList.packingIssue(for: canonLens, among: [fBody, canonLens]) == "Doesn't fit a body on this shoot")
        #expect(CompatibilityList.packingIssue(for: zLens, among: [fBody]) == "Doesn't fit a body on this shoot")
    }

    @Test func packingStaysQuietWithoutSomethingToJudgeBy() {
        let lens = Self.gear("Z 50mm", "Nikon Z")
        #expect(CompatibilityList.packingIssue(for: lens, among: [lens]) == nil, "No body packed")
        #expect(CompatibilityList.packingIssue(for: lens, among: [Self.body("X100VI", "Fixed lens")]) == nil)
        #expect(CompatibilityList.packingIssue(for: lens, among: [Self.body("Odd", "Homemade")]) == nil, "Not on a guess")
        #expect(CompatibilityList.packingIssue(for: Self.gear("Lens", ""), among: [Self.body("Z8", "Nikon Z")]) == nil)
        // Only lenses are judged: a body or a tripod never is.
        #expect(CompatibilityList.packingIssue(for: Self.body("D850", "Nikon F"), among: [Self.body("Z8", "Nikon Z")]) == nil)
        #expect(CompatibilityList.packingIssue(for: Self.gear("Tripod", "Nikon F", .support), among: [Self.body("Z8", "Nikon Z")]) == nil)
    }
}
