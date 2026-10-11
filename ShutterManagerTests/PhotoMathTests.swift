//
//  PhotoMathTests.swift
//  ShutterManagerTests
//
//  The photography math against worked examples. Foundation-only, like the code it tests, so it
//  also runs on Linux (see CLAUDE.md).
//

import Foundation
import Testing
@testable import ShutterManager

private func close(_ a: Double?, _ b: Double, tolerance: Double = 0.01) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tolerance
}

struct ExposureScaleTests {
    @Test func thirdStopScalesSpanTheUsualRange() {
        let apertures = ExposureScale.apertures()
        #expect(apertures.count == 37)
        #expect(apertures.first?.label == "f/1")
        #expect(apertures.last?.label == "f/64")
        #expect(ExposureScale.shutterSpeeds().count == 55)
        #expect(ExposureScale.shutterSpeeds().first?.label == "30\"")
        #expect(ExposureScale.shutterSpeeds().last?.label == "1/8000")
        #expect(ExposureScale.isoSpeeds().first?.label == "ISO 6")
        #expect(ExposureScale.isoSpeeds().last?.label == "ISO 102400")
    }

    @Test func fullStopScalesAreTheClassicMarks() {
        #expect(ExposureScale.apertures(.full).map(\.label) ==
                ["f/1", "f/1.4", "f/2", "f/2.8", "f/4", "f/5.6", "f/8", "f/11", "f/16", "f/22", "f/32", "f/45", "f/64"])
        #expect(ExposureScale.shutterSpeeds(.full).map(\.label) ==
                ["30\"", "15\"", "8\"", "4\"", "2\"", "1\"", "1/2", "1/4", "1/8", "1/15", "1/30", "1/60",
                 "1/125", "1/250", "1/500", "1/1000", "1/2000", "1/4000", "1/8000"])
        #expect(ExposureScale.isoSpeeds(.full).map(\.label).prefix(6) ==
                ["ISO 6", "ISO 12", "ISO 25", "ISO 50", "ISO 100", "ISO 200"])
    }

    @Test func halfStopScalesUseHalfStopMarks() {
        let apertures = ExposureScale.apertures(.half)
        #expect(apertures.count == 25)
        #expect(apertures.map(\.label).contains("f/6.7"))
        let shutters = ExposureScale.shutterSpeeds(.half)
        #expect(shutters.count == 37)
        #expect(shutters.map(\.label).contains("1/180"))
        // Each half step is exactly half a stop.
        for (a, b) in zip(shutters, shutters.dropFirst()) {
            #expect(close(log2(a.value / b.value), 0.5, tolerance: 1e-9))
        }
    }

    @Test func valuesAreExactWhileLabelsAreMarked() {
        let f56 = ExposureScale.apertureValue(thirds: 15)
        #expect(close(f56, 5.657, tolerance: 0.001))
        #expect(ExposureScale.apertureLabel(f56) == "f/5.6")
        #expect(ExposureScale.apertureLabel(5.6) == "f/5.6")
        #expect(ExposureScale.apertureLabel(1.8) == "f/1.8")
        #expect(ExposureScale.apertureLabel(100) == "f/100")
        #expect(ExposureScale.shutterValue(thirds: 24) == 1.0 / 256)
        #expect(ExposureScale.shutterLabel(1.0 / 256) == "1/250")
        #expect(ExposureScale.shutterLabel(1.0 / 250) == "1/250")
        #expect(ExposureScale.shutterLabel(0.5) == "1/2")
        #expect(ExposureScale.shutterLabel(2) == "2\"")
        #expect(ExposureScale.shutterLabel(1.0 / 20000) == "1/20000")
        #expect(ExposureScale.isoLabel(400) == "ISO 400")
        #expect(ExposureScale.isoLabel(ExposureScale.isoValue(thirds: 7)) == "ISO 500")
    }

    @Test func longTimesReadAsDurations() {
        #expect(ExposureScale.shutterLabel(45) == "45 s")
        #expect(ExposureScale.shutterLabel(256) == "4 min 16 s")
        #expect(ExposureScale.durationLabel(3725) == "1 h 2 min")
        #expect(ExposureScale.durationLabel(7200) == "2 h")
        #expect(ExposureScale.durationLabel(600) == "10 min")
        #expect(ExposureScale.durationLabel(2.5) == "2.5 s")
    }

    @Test func snappingFindsTheNearestMark() {
        #expect(ExposureScale.nearest(to: 5.6, in: ExposureScale.apertures())?.label == "f/5.6")
        #expect(ExposureScale.nearest(to: 1.0 / 240, in: ExposureScale.shutterSpeeds())?.label == "1/250")
        #expect(ExposureScale.nearest(to: 3000, in: ExposureScale.shutterSpeeds())?.label == "30\"")
        #expect(ExposureScale.nearest(to: -1, in: ExposureScale.apertures()) == nil)
    }
}

struct ExposureTests {
    @Test func exposureValueFollowsAPEX() {
        let sunny = ExposureSettings(aperture: 16, shutter: 1.0 / 128, iso: 100)
        #expect(close(sunny.ev, 15, tolerance: 1e-9))
        #expect(close(sunny.ev100, 15, tolerance: 1e-9))
        let iso400 = ExposureSettings(aperture: 16, shutter: 1.0 / 512, iso: 400)
        #expect(close(iso400.ev, 17, tolerance: 1e-9))
        #expect(close(iso400.ev100, 15, tolerance: 1e-9), "Same scene, so the same EV100")
        #expect(close(iso400.stops(brighterThan: sunny), 0, tolerance: 1e-9))
    }

    @Test func equivalentExposuresKeepTheSameEV100() {
        let base = ExposureSettings(aperture: 8, shutter: 1.0 / 256, iso: 100)
        let shutter = base.shutter(atAperture: 16, iso: 100)
        #expect(close(shutter, 1.0 / 64, tolerance: 1e-12))
        #expect(ExposureScale.shutterLabel(shutter) == "1/60")
        #expect(close(base.aperture(atShutter: 1.0 / 1024, iso: 100), 4, tolerance: 1e-9))
        #expect(close(base.iso(atAperture: 16, shutter: 1.0 / 256), 400, tolerance: 1e-9))
        let moved = ExposureSettings(aperture: 16, shutter: shutter, iso: 100)
        #expect(close(moved.ev100, base.ev100, tolerance: 1e-9))
        #expect(!ExposureSettings(aperture: 0, shutter: 1, iso: 100).isValid)
    }

    @Test func ndFiltersAddStops() {
        #expect(close(NDFilter.exposure(base: 1.0 / 30, stops: 10), 1024.0 / 30, tolerance: 1e-9))
        #expect(close(NDFilter.stops(density: 0.9), 3, tolerance: 1e-9))
        #expect(close(NDFilter.density(stops: 10), 3, tolerance: 1e-9))
        #expect(NDFilter.factor(stops: 3) == 8)
        #expect(close(NDFilter.stops(factor: 1000), 9.966, tolerance: 0.001))
        // A 6-stop and a 3-stop stacked are 9 stops.
        #expect(NDFilter.exposure(base: 1, stops: 6 + 3) == 512)
        #expect(NDFilter.presets.map(\.stops) == NDFilter.presets.map(\.stops).sorted())
        #expect(NDFilter.presets.first { $0.stops == 10 }?.label == "ND1000 · 3.0 · 10 stops")
    }

    @Test func sunnySixteenOpensUpForDullerLight() {
        let sunny = SunnySixteen.exposure(iso: 100, condition: .sunny)
        #expect(sunny.aperture == 16)
        #expect(sunny.shutter == 0.01)
        let overcast = SunnySixteen.exposure(iso: 400, condition: .overcast)
        #expect(close(overcast.aperture, 8, tolerance: 1e-9))
        #expect(overcast.shutter == 1.0 / 400)
        #expect(ExposureScale.apertureLabel(SunnySixteen.exposure(iso: 100, condition: .snowOrSand).aperture) == "f/22")
        #expect(ExposureScale.apertureLabel(SunnySixteen.exposure(iso: 100, condition: .heavyOvercast).aperture) == "f/5.6")
        for condition in SunnySixteen.Condition.allCases {
            let exposure = SunnySixteen.exposure(iso: 200, condition: condition)
            #expect(ExposureScale.apertureLabel(exposure.aperture) == "f/" + ExposureScale.decimal(condition.aperture, places: 1))
        }
    }
}

struct OpticsTests {
    @Test func depthOfFieldMatchesAWorkedExample() throws {
        // 50 mm at f/8 focused at 5 m with c = 0.03 mm: H ≈ 10.47 m, near ≈ 3.39 m, far ≈ 9.53 m.
        let dof = try #require(DepthOfField(focalLength: 50, aperture: 8, focusDistance: 5000, circleOfConfusion: 0.03))
        #expect(close(dof.hyperfocal, 10_466.7, tolerance: 0.1))
        #expect(close(dof.nearLimit, 3_389.3, tolerance: 0.5))
        #expect(close(dof.farLimit, 9_527.4, tolerance: 0.5))
        #expect(close(dof.total, dof.farLimit - dof.nearLimit, tolerance: 1e-9))
        #expect(close(dof.inFront + dof.behind, dof.total, tolerance: 1e-9))
    }

    @Test func focusingAtTheHyperfocalDistanceReachesInfinity() throws {
        let h = DepthOfField.hyperfocal(focalLength: 24, aperture: 11, circleOfConfusion: 0.03)
        let dof = try #require(DepthOfField(focalLength: 24, aperture: 11, focusDistance: h, circleOfConfusion: 0.03))
        #expect(dof.farLimit == .infinity)
        #expect(close(dof.nearLimit, h / 2, tolerance: 1e-6))
        #expect(dof.total == .infinity)
        let beyond = try #require(DepthOfField(focalLength: 24, aperture: 11, focusDistance: h * 3, circleOfConfusion: 0.03))
        #expect(beyond.farLimit == .infinity)
    }

    @Test func depthOfFieldNeedsFocusBeyondTheFocalLength() {
        #expect(DepthOfField(focalLength: 100, aperture: 8, focusDistance: 50, circleOfConfusion: 0.03) == nil)
        #expect(DepthOfField(focalLength: 50, aperture: 0, focusDistance: 5000, circleOfConfusion: 0.03) == nil)
    }

    @Test func circleOfConfusionScalesWithTheFormat() {
        #expect(close(DepthOfField.circleOfConfusion(for: .fullFrame), 0.0288, tolerance: 0.0001))
        #expect(close(DepthOfField.circleOfConfusion(for: .fullFrame, divisor: 3000), 0.0144, tolerance: 0.0001))
        #expect(DepthOfField.circleOfConfusion(for: .apsC) < DepthOfField.circleOfConfusion(for: .fullFrame))
        #expect(CircleOfConfusionStandard.standard.divisor == 1500)
    }

    @Test func fieldOfViewOfANormalLens() throws {
        let fov = try #require(FieldOfView(focalLength: 50, format: .fullFrame))
        #expect(close(fov.horizontal, 39.6, tolerance: 0.05))
        #expect(close(fov.vertical, 27.0, tolerance: 0.05))
        #expect(close(fov.diagonal, 46.8, tolerance: 0.05))
        let wide = try #require(FieldOfView(focalLength: 24, format: .fullFrame))
        #expect(close(wide.diagonal, 84.1, tolerance: 0.05))
        #expect(FieldOfView(focalLength: 0, format: .fullFrame) == nil)
    }

    @Test func cropEquivalents() throws {
        #expect(close(FieldOfView.equivalentFocalLength(35, cropFactor: 1.5), 52.5, tolerance: 1e-9))
        #expect(close(FieldOfView.matchingFocalLength(50, from: .fullFrame, to: .apsC), 32.6, tolerance: 0.05))
        let frame = try #require(FieldOfView.frameSize(focalLength: 50, format: .fullFrame, distance: 5000))
        #expect(close(frame.width, 3600, tolerance: 1e-6))
        #expect(close(frame.height, 2400, tolerance: 1e-6))
    }
}

struct CalculatorTests {
    @Test func astroExposureLimits() {
        #expect(close(AstroExposure.rule500(focalLength: 20, cropFactor: 1), 25, tolerance: 1e-9))
        #expect(close(AstroExposure.rule500(focalLength: 20, cropFactor: 1.5), 16.67, tolerance: 0.01))
        #expect(close(AstroExposure.npf(focalLength: 20, aperture: 2.8, pixelPitchMicrons: 4.35), 11.42, tolerance: 0.01))
        #expect(close(AstroExposure.pixelPitch(sensorWidth: 36, sensorHeight: 24, pixelsWide: 6048, pixelsHigh: 4024),
                      5.95, tolerance: 0.01))
        // The NPF rule is stricter than the 500 rule for a high-resolution sensor.
        let npf = AstroExposure.npf(focalLength: 20, aperture: 1.8, pixelPitchMicrons: 3.76) ?? 0
        #expect(npf < (AstroExposure.rule500(focalLength: 20, cropFactor: 1) ?? 0))
        #expect(AstroExposure.npf(focalLength: 0, aperture: 2, pixelPitchMicrons: 4) == nil)
    }

    @Test func starTrailsFollowTheSiderealRate() {
        #expect(close(StarTrails.degreesPerHour, 15.041, tolerance: 0.001))
        #expect(close(StarTrails.rotation(seconds: 3600), 15.041, tolerance: 0.001))
        #expect(close(StarTrails.duration(forRotation: 90), 21_541, tolerance: 1))
        #expect(StarTrails.frames(totalSeconds: 3600, exposure: 30, gap: 1) == 116)
        #expect(StarTrails.frames(totalSeconds: 3600, exposure: 0) == 0)
    }

    @Test func timeLapsePlan() throws {
        let plan = try #require(TimeLapsePlan(eventDuration: 7200, interval: 5, framesPerSecond: 24))
        #expect(plan.frames == 1440)
        #expect(plan.clipDuration == 60)
        #expect(plan.speedUp == 120)
        #expect(plan.storage(fileSize: 25) == 36_000)
        #expect(plan.fits(exposure: 4))
        #expect(!plan.fits(exposure: 4.8))
        #expect(TimeLapsePlan.interval(eventDuration: 7200, clipDuration: 30, framesPerSecond: 24) == 10)
        #expect(TimeLapsePlan(eventDuration: 0, interval: 5, framesPerSecond: 24) == nil)
    }

    @Test func flashGuideNumbers() {
        #expect(close(FlashExposure.distance(guideNumber: 60, aperture: 8, iso: 100), 7.5, tolerance: 1e-9))
        #expect(close(FlashExposure.distance(guideNumber: 60, aperture: 8, iso: 400), 15, tolerance: 1e-9))
        #expect(close(FlashExposure.aperture(guideNumber: 60, distance: 7.5, iso: 100), 8, tolerance: 1e-9))
        #expect(close(FlashExposure.requiredGuideNumber(distance: 7.5, aperture: 8, iso: 400), 30, tolerance: 1e-9))
        #expect(close(FlashExposure.guideNumber(60, atPower: 0.25), 30, tolerance: 1e-9))
        #expect(FlashExposure.powerLevels.count == 8)
        #expect(FlashExposure.powerLevels.last?.label == "1/128")
        #expect(FlashExposure.distance(guideNumber: 60, aperture: 0, iso: 100) == nil)
    }

    @Test func printSize() {
        #expect(PrintSize.inches(pixels: 6000, dpi: 300) == 20)
        #expect(PrintSize.dpi(pixels: 6000, inches: 20) == 300)
        #expect(PrintSize.pixels(inches: 10, dpi: 300) == 3000)
        #expect(PrintSize.Quality(dpi: 300) == .best)
        #expect(PrintSize.Quality(dpi: 250) == .good)
        #expect(PrintSize.Quality(dpi: 180) == .viewedFromDistance)
        #expect(PrintSize.Quality(dpi: 100) == .low)
        let paper = PrintSize.Paper(name: "8 × 10 in", shortSide: 8, longSide: 10)
        #expect(PrintSize.fillDPI(pixelsWide: 6000, pixelsHigh: 4000, paper: paper) == 500)
        #expect(close(PrintSize.papers.first { $0.name == "A4" }?.longSide, 11.69, tolerance: 0.01))
    }
}

struct ReciprocityTests {
    @Test func powerLawLengthensOnlyLongExposures() throws {
        let hp5Like = ReciprocityModel.powerLaw(exponent: 1.31, from: 1)
        let ten = try #require(hp5Like.correct(metered: 10))
        #expect(close(ten.corrected, 20.42, tolerance: 0.01))
        #expect(ten.basis == .makerData)
        #expect(close(ten.extraStops, 1.03, tolerance: 0.01))
        #expect(hp5Like.correct(metered: 0.5)?.basis == .noCorrection)
        #expect(hp5Like.correct(metered: 0.5)?.corrected == 0.5)
        #expect(hp5Like.correct(metered: 0) == nil)
    }

    @Test func tablesInterpolateAndFlagExtrapolation() throws {
        let model = ReciprocityModel.table(uncorrectedUpTo: 0.1, points: [
            ReciprocityPoint(metered: 1, corrected: 2),
            ReciprocityPoint(metered: 10, corrected: 50),
            ReciprocityPoint(metered: 100, corrected: 1200)
        ])
        #expect(model.correct(metered: 0.05)?.basis == .noCorrection)
        #expect(model.correct(metered: 10)?.corrected == 50)
        #expect(model.correct(metered: 10)?.basis == .makerData)
        // Between rows, a straight line on log–log axes: 31.6 s sits between 50 s and 1200 s.
        let between = try #require(model.correct(metered: 31.62))
        #expect(close(between.corrected, 244.9, tolerance: 0.5))
        // From the no-correction threshold to the first row.
        let early = try #require(model.correct(metered: 0.5))
        #expect(close(early.corrected, 0.812, tolerance: 0.005))
        let beyond = try #require(model.correct(metered: 1000))
        #expect(beyond.basis == .extrapolated)
        #expect(close(beyond.corrected, 28_800, tolerance: 10))
    }

    @Test func noCorrectionRangesAndMissingData() {
        let model = ReciprocityModel.noCorrectionUpTo(seconds: 120)
        #expect(model.correct(metered: 60)?.basis == .noCorrection)
        #expect(model.correct(metered: 200)?.basis == .noData)
        #expect(model.correct(metered: 200)?.corrected == 200)
        #expect(ReciprocityModel.unpublished.correct(metered: 5)?.basis == .noData)
    }
}

struct DevelopmentSessionTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private var plan: [DevelopmentStepPlan] {
        [DevelopmentStepPlan(name: "Developer", duration: 600, agitation: .everyMinute),
         DevelopmentStepPlan(name: "Stop", duration: 60, agitation: .none),
         DevelopmentStepPlan(name: "Empty", duration: 0, agitation: .none),
         DevelopmentStepPlan(name: "Fix", duration: 300, agitation: .everyThirtySeconds)]
    }

    @Test func stepsRunInOrderAndSkipEmptyOnes() {
        var session = DevelopmentSession(steps: plan)
        #expect(session.steps.map(\.name) == ["Developer", "Stop", "Fix"])
        #expect(session.totalDuration == 960)
        #expect(session.phase(at: t0) == .ready)
        session.start(at: t0)
        #expect(session.phase(at: t0.addingTimeInterval(5)) == .running(remaining: 595, agitating: true))
        #expect(session.phase(at: t0.addingTimeInterval(30)) == .running(remaining: 570, agitating: false))
        #expect(session.phase(at: t0.addingTimeInterval(65)) == .running(remaining: 535, agitating: true))
        #expect(session.phase(at: t0.addingTimeInterval(601)) == .stepComplete)
        session.advance()
        #expect(session.currentStep?.name == "Stop")
        #expect(session.phase(at: t0.addingTimeInterval(700)) == .ready)
        session.advance()
        session.advance()
        #expect(session.isFinished)
        #expect(session.phase(at: t0) == .finished)
    }

    @Test func pausingStopsTheClock() {
        var session = DevelopmentSession(steps: plan)
        session.start(at: t0)
        session.pause(at: t0.addingTimeInterval(100))
        #expect(session.phase(at: t0.addingTimeInterval(150)) == .paused(remaining: 500))
        session.start(at: t0.addingTimeInterval(200))
        #expect(session.elapsed(at: t0.addingTimeInterval(250)) == 150)
        session.restartStep()
        #expect(session.phase(at: t0.addingTimeInterval(300)) == .ready)
    }

    @Test func cuesCoverRemainingAgitationsAndTheStepEnd() {
        var session = DevelopmentSession(steps: plan)
        #expect(session.upcomingCues(after: t0).stepEnd == nil, "Nothing is scheduled before starting")
        session.start(at: t0)
        let cues = session.upcomingCues(after: t0.addingTimeInterval(90))
        #expect(cues.agitations.first == t0.addingTimeInterval(120))
        #expect(cues.agitations.count == 8) // 2:00 … 9:00
        #expect(cues.stepEnd == t0.addingTimeInterval(600))
    }

    @Test func kodakAgitationEveryThirtySeconds() {
        let kodak = AgitationPattern.everyThirtySeconds
        #expect(kodak.isAgitating(at: 4))
        #expect(!kodak.isAgitating(at: 29))
        #expect(kodak.isAgitating(at: 31))
        #expect(!kodak.isAgitating(at: 36))
        #expect(kodak.agitationStarts(within: 300) == [0, 30, 60, 90, 120, 150, 180, 210, 240, 270])
    }

    @Test func aMarkAtTheEndOfTheInitialPeriodDoesNotRestartIt() {
        let long = AgitationPattern(initialSeconds: 30, intervalSeconds: 30, durationSeconds: 5)
        #expect(!long.isAgitating(at: 31))
        #expect(long.isAgitating(at: 61))
        #expect(long.agitationStarts(within: 120) == [0, 60, 90])
        #expect(AgitationPattern.none.agitationStarts(within: 300).isEmpty)
        #expect(AgitationPattern.none.isNone)
        #expect(!AgitationPattern.none.isAgitating(at: 0))
    }
}
