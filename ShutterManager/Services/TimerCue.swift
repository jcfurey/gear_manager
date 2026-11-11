//
//  TimerCue.swift
//  ShutterManager
//
//  The app's own alert for a running timer, for when a notification can't be shown.
//

import AudioToolbox
import Foundation

/// A banner, a haptic and a short tone, given while the app is open. `ToolTimers` calls it for
/// each alert that comes due when notifications are off.
@MainActor
enum TimerCue {
    static func give(_ alert: NotificationManager.TimerAlert) {
        // The banner is also read out by VoiceOver.
        ToastNotificationManager.shared.info(alert.title, message: alert.body, duration: 4)
        HapticFeedbackManager.shared.warning()
        TimerTone.play()
    }
}

/// A short two-note tone, made in code so the app ships no sound file.
///
/// It plays as a system alert sound: it mixes with whatever else is playing, needs no audio
/// session, and with the ring switch on silent it's a vibration instead.
@MainActor
enum TimerTone {
    private static var soundID: SystemSoundID?

    static func play() {
        guard let id = soundID ?? register() else { return }
        soundID = id
        AudioServicesPlayAlertSound(id)
    }

    /// Writes the tone to the caches folder and hands it to the system; nil if either fails.
    private static func register() -> SystemSoundID? {
        guard let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let url = folder.appendingPathComponent("timer-cue.wav")
        do {
            try TimerToneData.wav().write(to: url, options: .atomic)
        } catch {
            return nil
        }
        var id: SystemSoundID = 0
        return AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError ? id : nil
    }
}
