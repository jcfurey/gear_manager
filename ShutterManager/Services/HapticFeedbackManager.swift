//
//  HapticFeedbackManager.swift
//  ShutterManager
//
//  Centralized haptic feedback. Owns reusable UIFeedbackGenerators and maps app actions
//  (button tap, save, delete, etc.) to consistent impact/selection/notification haptics.
//

import UIKit
import SwiftUI

/// Centralized haptic feedback manager for consistent tactile responses throughout the app
@MainActor
final class HapticFeedbackManager {
    
    // MARK: - Singleton
    
    static let shared = HapticFeedbackManager()
    
    private init() {}

    /// Whether haptics are enabled in Settings (default on). Read live so the global "Haptic
    /// Feedback" toggle actually suppresses feedback app-wide — previously nothing consumed it,
    /// making the setting a no-op.
    private var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.hapticFeedback) as? Bool ?? true
    }

    // MARK: - Feedback Generators
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let impactSoft = UIImpactFeedbackGenerator(style: .soft)
    private let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()
    
    // MARK: - Public Interface
    
    /// Prepare feedback generators for low-latency response
    func prepare() {
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        impactSoft.prepare()
        impactRigid.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
    }
    
    // MARK: - Impact Feedback
    
    /// Light impact for subtle interactions (e.g., picker scrolling, minor state changes)
    func light() {
        guard hapticsEnabled else { return }
        impactLight.impactOccurred()
    }

    /// Medium impact for standard button taps and interactions
    func medium() {
        guard hapticsEnabled else { return }
        impactMedium.impactOccurred()
    }

    /// Heavy impact for significant actions (e.g., deletion, major state changes)
    func heavy() {
        guard hapticsEnabled else { return }
        impactHeavy.impactOccurred()
    }

    /// Soft impact for gentle feedback (e.g., toggles, switches)
    func soft() {
        guard hapticsEnabled else { return }
        impactSoft.impactOccurred()
    }

    /// Rigid impact for precise feedback (e.g., a value locking in)
    func rigid() {
        guard hapticsEnabled else { return }
        impactRigid.impactOccurred()
    }
    
    // MARK: - Selection Feedback
    
    /// Selection feedback for picker changes and option selection
    func selection() {
        guard hapticsEnabled else { return }
        selectionGenerator.selectionChanged()
    }
    
    // MARK: - Notification Feedback
    
    /// Success notification (e.g., save successful, goal completed)
    func success() {
        guard hapticsEnabled else { return }
        notificationGenerator.notificationOccurred(.success)
    }

    /// Warning notification (e.g., approaching limit, incomplete action)
    func warning() {
        guard hapticsEnabled else { return }
        notificationGenerator.notificationOccurred(.warning)
    }

    /// Error notification (e.g., failed action, validation error)
    func error() {
        guard hapticsEnabled else { return }
        notificationGenerator.notificationOccurred(.error)
    }
    
    // MARK: - Context-Specific Feedback
    
    /// Feedback for button taps
    func buttonTap() {
        medium()
    }
    
    /// Feedback for toggle switches
    func toggle() {
        soft()
    }
    
    /// Feedback for successful save operations
    func saveSuccess() {
        success()
    }
    
    /// Feedback for deletion actions
    func delete() {
        heavy()
    }
    
    /// Feedback for picker value changes
    func pickerChange() {
        selection()
    }
    
    /// Feedback for maintenance reminder
    func maintenanceReminder() {
        warning()
    }
    
    /// Feedback for barcode scan success
    func barcodeScanSuccess() {
        success()
    }
    
    /// Feedback for calculation complete
    func calculationComplete() {
        soft()
    }
    
    /// Feedback for export/backup success
    func exportSuccess() {
        success()
    }
    
    /// Feedback for navigation action
    func navigation() {
        light()
    }
    
    /// Feedback for validation error
    func validationError() {
        error()
    }
}

// MARK: - SwiftUI View Extension

extension View {
    /// Add haptic feedback to a button tap
    func hapticFeedback(_ type: HapticFeedbackType = .medium) -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded {
                Task { @MainActor in
                    switch type {
                    case .light:
                        HapticFeedbackManager.shared.light()
                    case .medium:
                        HapticFeedbackManager.shared.medium()
                    case .heavy:
                        HapticFeedbackManager.shared.heavy()
                    case .soft:
                        HapticFeedbackManager.shared.soft()
                    case .rigid:
                        HapticFeedbackManager.shared.rigid()
                    case .selection:
                        HapticFeedbackManager.shared.selection()
                    case .success:
                        HapticFeedbackManager.shared.success()
                    case .warning:
                        HapticFeedbackManager.shared.warning()
                    case .error:
                        HapticFeedbackManager.shared.error()
                    }
                }
            }
        )
    }
}

// MARK: - Haptic Feedback Type

enum HapticFeedbackType {
    case light
    case medium
    case heavy
    case soft
    case rigid
    case selection
    case success
    case warning
    case error
}
