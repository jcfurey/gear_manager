//
//  TimerToneTests.swift
//  ShutterManagerTests
//
//  The timer's alert tone: the samples, and the WAV file made from them. Foundation-only, so it
//  also runs on Linux.
//

import Foundation
import Testing
@testable import ShutterManager

struct TimerToneTests {
    private static func uint32(_ data: Data, at offset: Int) -> UInt32 {
        data.subdata(in: offset..<(offset + 4)).enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
    }

    private static func uint16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[data.startIndex + offset]) | UInt16(data[data.startIndex + offset + 1]) << 8
    }

    @Test func theToneIsTwoShortNotes() {
        let samples = TimerToneData.samples()
        let seconds = TimerToneData.notes.reduce(0) { $0 + $1.seconds }
        #expect(seconds == 0.4)
        #expect(samples.count == 17_640, "0.4 s at 44.1 kHz")
        #expect(TimerToneData.notes[1].frequency > TimerToneData.notes[0].frequency, "The second note is the higher")

        // Loud enough to hear, with headroom; and each note starts and ends at silence, so the
        // speaker doesn't click.
        let peak = samples.map { abs(Int($0)) }.max() ?? 0
        #expect(peak > 15_000 && peak < 20_000)
        let firstNote = Int(TimerToneData.notes[0].seconds * Double(TimerToneData.sampleRate))
        for index in [0, firstNote - 1, firstNote, samples.count - 1] {
            #expect(abs(Int(samples[index])) < 400, "Sample \(index) should be near silence")
        }
    }

    @Test func theFileIsAPlainWAV() {
        let data = TimerToneData.wav()
        let samples = TimerToneData.samples()
        #expect(data.count == 44 + samples.count * 2)
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
        #expect(Self.uint32(data, at: 4) == UInt32(data.count - 8))
        #expect(String(decoding: data.subdata(in: 8..<16), as: UTF8.self) == "WAVEfmt ")
        #expect(Self.uint32(data, at: 16) == 16)
        #expect(Self.uint16(data, at: 20) == 1, "PCM")
        #expect(Self.uint16(data, at: 22) == 1, "Mono")
        #expect(Self.uint32(data, at: 24) == 44_100)
        #expect(Self.uint32(data, at: 28) == 88_200, "Bytes a second")
        #expect(Self.uint16(data, at: 32) == 2)
        #expect(Self.uint16(data, at: 34) == 16)
        #expect(String(decoding: data.subdata(in: 36..<40), as: UTF8.self) == "data")
        #expect(Self.uint32(data, at: 40) == UInt32(samples.count * 2))
        // The samples follow, low byte first.
        let loudest = samples.firstIndex { abs(Int($0)) > 10_000 } ?? 0
        #expect(Int16(bitPattern: Self.uint16(data, at: 44 + loudest * 2)) == samples[loudest])
    }
}
