//
//  ToastNotificationManager.swift
//  ShutterManager
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Toast notification manager for displaying temporary success/error/info messages
@MainActor
class ToastNotificationManager: ObservableObject {
    static let shared = ToastNotificationManager()

    @Published var currentToast: ToastMessage?
    @Published var isShowing = false

    private init() {}

    /// Show a toast notification
    func show(_ message: ToastMessage) {
        currentToast = message
        isShowing = true

        // Toasts auto-dismiss and are the only feedback for success/failure of actions like backup
        // or restore — post a VoiceOver announcement so a blind user hears them (the visual toast
        // alone is silent to VoiceOver, which never moves focus to a transient overlay).
        let spoken = [message.title, message.message].compactMap { $0 }.joined(separator: ". ")
        UIAccessibility.post(notification: .announcement, argument: spoken)

        // Auto-dismiss after duration
        Task {
            try? await Task.sleep(nanoseconds: UInt64(message.duration * 1_000_000_000))
            if currentToast?.id == message.id {
                dismiss()
            }
        }
    }
    
    /// Show a success toast
    func success(_ title: String, message: String? = nil, duration: TimeInterval = 3.0) {
        show(ToastMessage(type: .success, title: title, message: message, duration: duration))
    }
    
    /// Show an error toast
    func error(_ title: String, message: String? = nil, duration: TimeInterval = 4.0) {
        show(ToastMessage(type: .error, title: title, message: message, duration: duration))
    }
    
    /// Show an info toast
    func info(_ title: String, message: String? = nil, duration: TimeInterval = 3.0) {
        show(ToastMessage(type: .info, title: title, message: message, duration: duration))
    }
    
    /// Show a warning toast
    func warning(_ title: String, message: String? = nil, duration: TimeInterval = 3.5) {
        show(ToastMessage(type: .warning, title: title, message: message, duration: duration))
    }
    
    /// Dismiss current toast
    func dismiss() {
        withAnimation(.easeOut(duration: 0.3)) {
            isShowing = false
        }

        let dismissedID = currentToast?.id
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if currentToast?.id == dismissedID {
                currentToast = nil
            }
        }
    }
}

// MARK: - Toast Message Model

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let type: ToastType
    let title: String
    let message: String?
    let duration: TimeInterval
    
    enum ToastType {
        case success
        case error
        case info
        case warning
        
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            case .info: return .blue
            case .warning: return .orange
            }
        }
    }
}

// MARK: - Toast View

struct ToastView: View {
    let toast: ToastMessage
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.type.icon)
                .font(.system(size: 24))
                .foregroundStyle(toast.type.color)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(toast.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if let message = toast.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal)
    }
}

// MARK: - Toast Modifier

struct ToastModifier: ViewModifier {
    @ObservedObject var toastManager = ToastNotificationManager.shared
    
    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            
            if toastManager.isShowing, let toast = toastManager.currentToast {
                ToastView(toast: toast) {
                    toastManager.dismiss()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: toastManager.isShowing)
                .padding(.top, 50)
                .zIndex(999)
            }
        }
    }
}

extension View {
    /// Add toast notification capability to any view
    func toast() -> some View {
        self.modifier(ToastModifier())
    }
}

// MARK: - Common Toast Messages

extension ToastNotificationManager {
    // MARK: - Success Messages
    
    func gearSaved() {
        success("Gear Saved", message: "Your gear item has been saved successfully.")
    }
    
    func gearDeleted() {
        success("Gear Deleted", message: "The gear item has been removed from your inventory.")
    }
    
    func backupCreated() {
        success("Backup Created", message: "Your data has been backed up successfully.")
    }
    
    func backupRestored() {
        success("Backup Restored", message: "Your data has been restored from backup.")
    }
    
    func dataExported() {
        success("Data Exported", message: "Your data has been exported successfully.")
    }
    
    func dataImported() {
        success("Data Imported", message: "Your data has been imported successfully.")
    }
    
    func barcodeScanSuccess() {
        success("Barcode Scanned", message: "Product information retrieved successfully.")
    }
    
    // MARK: - Error Messages
    
    func saveFailed(_ details: String? = nil) {
        error("Save Failed", message: details ?? "Unable to save. Please try again.")
    }
    
    func loadFailed(_ details: String? = nil) {
        error("Load Failed", message: details ?? "Unable to load data. Please try again.")
    }
    
    func deleteFailed(_ details: String? = nil) {
        error("Delete Failed", message: details ?? "Unable to delete item. Please try again.")
    }
    
    func backupFailed(_ details: String? = nil) {
        error("Backup Failed", message: details ?? "Unable to create backup. Please check storage space.")
    }
    
    func restoreFailed(_ details: String? = nil) {
        error("Restore Failed", message: details ?? "Unable to restore backup. Please try again.")
    }
    
    func exportFailed(_ details: String? = nil) {
        error("Export Failed", message: details ?? "Unable to export data. Please try again.")
    }
    
    func importFailed(_ details: String? = nil) {
        error("Import Failed", message: details ?? "Unable to import data. Please check file format.")
    }
    
    func cameraPermissionDenied() {
        error("Camera Access Denied", message: "Please enable camera access in Settings to scan barcodes.")
    }
    
    func barcodeScanFailed() {
        error("Scan Failed", message: "Unable to scan barcode. Please try again or enter manually.")
    }
    
    func productNotFound() {
        warning("Product Not Found", message: "No product information available for this barcode.")
    }
    
    func networkError() {
        error("Network Error", message: "Unable to connect. Please check your internet connection.")
    }
    
    // MARK: - Warning Messages
    
    func storageAlmostFull() {
        warning("Storage Almost Full", message: "Consider removing old backups to free up space.")
    }
    
    func unsavedChanges() {
        warning("Unsaved Changes", message: "You have unsaved changes that will be lost.")
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        Button("Show Success") {
            ToastNotificationManager.shared.success("Success!", message: "Operation completed successfully.")
        }
        
        Button("Show Error") {
            ToastNotificationManager.shared.error("Error", message: "Something went wrong.")
        }
        
        Button("Show Warning") {
            ToastNotificationManager.shared.warning("Warning", message: "This action cannot be undone.")
        }
        
        Button("Show Info") {
            ToastNotificationManager.shared.info("Info", message: "Processing your request...")
        }
    }
    .toast()
}
