//
//  TimerToneData.swift
//  ShutterManager
//
//  The timer's alert tone, made in code as a WAV file. Foundation-only.
//

import Foundation

/// The tone `TimerTone` plays: its samples, and those samples as a WAV file.
enum TimerToneData {
    static let sampleRate = 44_100
    /// Two notes a fifth apart, the second higher: A5 then E6.
    static let notes: [(frequency: Double, seconds: Double)] = [(880, 0.16), (1318.5, 0.24)]
    /// Each note fades in and out over this long, so it doesn't click.
    static let fadeSeconds = 0.012

    /// 16-bit mono PCM samples of the tone, at 60% of full scale.
    static func samples() -> [Int16] {
        var pcm: [Int16] = []
        for note in notes {
            let count = Int(note.seconds * Double(sampleRate))
            let fade = max(Int(fadeSeconds * Double(sampleRate)), 1)
            for index in 0..<count {
                let envelope = min(1, Double(index) / Double(fade), Double(count - 1 - index) / Double(fade))
                let value = sin(2 * .pi * note.frequency * Double(index) / Double(sampleRate))
                pcm.append(Int16((value * envelope * 0.6 * Double(Int16.max)).rounded()))
            }
        }
        return pcm
    }

    /// A complete WAV file: the 44-byte header and the samples, little-endian.
    static func wav() -> Data {
        let pcm = samples()
        let dataBytes = UInt32(pcm.count * 2)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataBytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))                  // The format chunk's length.
        append(UInt16(1))                   // PCM.
        append(UInt16(1))                   // Mono.
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))      // Bytes a second.
        append(UInt16(2))                   // Bytes a sample frame.
        append(UInt16(16))                  // Bits a sample.
        data.append(contentsOf: Array("data".utf8))
        append(dataBytes)
        for sample in pcm { append(sample) }
        return data
    }
}
