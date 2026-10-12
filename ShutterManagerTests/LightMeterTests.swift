//
//  LightMeterTests.swift
//  ShutterManagerTests
//
//  The light meter's reading and solving. Foundation-only, so it also runs on Linux.
//

import Foundation
import Testing
@testable import ShutterManager

private func close(_ a: Double?, _ b: Double, tolerance: Double = 1e-9) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tolerance
}

struct LightMeterTests {
    // f/8 is exactly 2^3 and 1/250 is 2^−8 on the scale, so these EVs are whole numbers.
    private let f8 = ExposureScale.apertureValue(thirds: 18)
    private let f16 = ExposureScale.apertureValue(thirds: 24)
    private let s250 = ExposureScale.shutterValue(thirds: 24)
    private let s125 = ExposureScale.shutterValue(thirds: 21)
    private let s60 = ExposureScale.shutterValue(thirds: 18)

    @Test func cameraExposureReadsTheSceneIncludingTheTargetOffset() {
        var reading = CameraExposure(aperture: f8, shutter: s250, iso: 100, targetOffset: 0)
        #expect(close(reading.ev100, 14))
        // A picture a stop too bright: the scene is an EV brighter than the settings suit.
        reading.targetOffset = 1
        #expect(close(reading.ev100, 15))
        // ISO 200 at the same settings suits a scene one EV darker.
        reading.iso = 200
        #expect(close(reading.ev100, 14))
        reading.shutter = 0
        #expect(reading.ev100 == nil)
        reading = CameraExposure(aperture: f8, shutter: s250, iso: 100, targetOffset: .nan)
        #expect(reading.ev100 == nil)
    }

    @Test func aperturePriorityGivesSunnySixteen() throws {
        // EV 15 at ISO 100 is bright sun: f/16 at 1/125 (2^−7).
        let solution = try #require(LightMeter.solve(ev100: 15, priority: .aperture, aperture: f16, shutter: 1, iso: 100))
        #expect(close(solution.exact, 1.0 / 128))
        #expect(ExposureScale.shutterLabel(solution.settings.shutter) == "1/125")
        #expect(solution.settings.aperture == f16)
        #expect(solution.inRange)
    }

    @Test func shutterPriorityGivesSunnySixteen() throws {
        let solution = try #require(LightMeter.solve(ev100: 15, priority: .shutter, aperture: 1, shutter: s125, iso: 100))
        #expect(close(solution.exact, 16))
        #expect(ExposureScale.apertureLabel(solution.settings.aperture) == "f/16")
        #expect(solution.inRange)
    }

    @Test func isoPrioritySolvesTheSpeed() throws {
        // f/8 at 1/64 is EV 12.
        let solution = try #require(LightMeter.solve(ev100: 12, priority: .iso, aperture: f8, shutter: s60, iso: 1))
        #expect(close(solution.exact, 100, tolerance: 1e-6))
        #expect(ExposureScale.isoLabel(solution.settings.iso) == "ISO 100")
        // Two stops of filter need two stops more speed.
        let filtered = try #require(LightMeter.solve(ev100: 12, priority: .iso, aperture: f8, shutter: s60, iso: 1, filterStops: 2))
        #expect(close(filtered.exact, 400, tolerance: 1e-6))
    }

    @Test func filtersLengthenTheExposure() throws {
        // Ten stops on bright sun at f/16: 1/128 × 1024 = 8 s.
        let solution = try #require(LightMeter.solve(ev100: 15, priority: .aperture, aperture: f16, shutter: 1, iso: 100, filterStops: 10))
        #expect(close(solution.exact, 8))
        #expect(ExposureScale.shutterLabel(solution.settings.shutter) == "8\"")
    }

    @Test func longExposuresStayUnsnappedForBulb() throws {
        // EV 0 at f/16: 256 s, past the 30 s end of the scale.
        let solution = try #require(LightMeter.solve(ev100: 0, priority: .aperture, aperture: f16, shutter: 1, iso: 100))
        #expect(solution.inRange)
        #expect(close(solution.settings.shutter, 256))
    }

    @Test func solvedValuesSnapToTheNearestThird() throws {
        // A sixth of a stop above 1/125 still reads 1/125; half a stop above is 1/160 or 1/100.
        let sixth = try #require(LightMeter.solve(ev100: 15 + 1.0 / 6 - 0.01, priority: .aperture, aperture: f16, shutter: 1, iso: 100))
        #expect(ExposureScale.shutterLabel(sixth.settings.shutter) == "1/125")
        let third = try #require(LightMeter.solve(ev100: 15 + 1.0 / 3, priority: .aperture, aperture: f16, shutter: 1, iso: 100))
        #expect(ExposureScale.shutterLabel(third.settings.shutter) == "1/160")
    }

    @Test func valuesOffTheScaleAreFlagged() throws {
        // Snow in sun at f/1.4 and ISO 3200 needs far less than 1/8000.
        let tooFast = try #require(LightMeter.solve(ev100: 16, priority: .aperture,
                                                    aperture: ExposureScale.apertureValue(thirds: 3), shutter: 1, iso: 3200))
        #expect(!tooFast.inRange)
        // A dark room at 1/1000 and ISO 100 would need wider than f/1.
        let tooWide = try #require(LightMeter.solve(ev100: 4, priority: .shutter, aperture: 1, shutter: 1.0 / 1024, iso: 100))
        #expect(!tooWide.inRange)
        #expect(LightMeter.solve(ev100: .nan, priority: .aperture, aperture: f8, shutter: 1, iso: 100) == nil)
        #expect(LightMeter.solve(ev100: 10, priority: .aperture, aperture: 0, shutter: 1, iso: 100) == nil)
    }

    @Test func smoothingEasesSmallChangesAndTakesJumps() {
        #expect(LightMeter.smoothed(10, previous: nil) == 10)
        #expect(close(LightMeter.smoothed(10.5, previous: 10), 10.15))
        #expect(LightMeter.smoothed(12, previous: 10) == 12)
        #expect(LightMeter.smoothed(9, previous: .nan) == 9)
    }

    @Test func calibrationIsTheDifferenceToATenth() {
        #expect(close(LightMeter.calibration(trusted: 12, measured: 11.66), 0.3))
        #expect(close(LightMeter.calibration(trusted: 11, measured: 11.66), -0.7))
        #expect(LightMeter.calibration(trusted: 20, measured: 10) == LightMeter.calibrationRange.upperBound)
        #expect(LightMeter.calibration(trusted: .infinity, measured: 10) == nil)
    }

    @Test func evLabelsUseATenthAndATrueMinus() {
        #expect(LightMeter.evLabel(12.34) == "12.3")
        #expect(LightMeter.evLabel(-0.04) == "0")
        #expect(LightMeter.evLabel(-1) == "−1")
        #expect(LightMeter.evLabel(15) == "15")
        #expect(LightMeter.evLabel(.nan) == "—")
        #expect(LightMeter.signedEVLabel(0.3) == "+0.3")
        #expect(LightMeter.signedEVLabel(-0.7) == "−0.7")
        #expect(LightMeter.signedEVLabel(0.01) == "0")
    }
}
