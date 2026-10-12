//
//  LoadingStateView.swift
//  ShutterManager
//

import SwiftUI

/// Loading state view with customizable message and progress indication
struct LoadingStateView: View {
    let message: String
    let showProgress: Bool
    let progress: Double?
    
    init(
        message: String = "Loading...",
        showProgress: Bool = false,
        progress: Double? = nil
    ) {
        self.message = message
        self.showProgress = showProgress
        self.progress = progress
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Progress Indicator
            if showProgress, let progress = progress {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.5)
            }
            
            // Message
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Inline Loading State

/// Inline loading view for use within existing views
struct InlineLoadingView: View {
    let message: String?
    
    init(message: String? = nil) {
        self.message = message
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
            
            if let message = message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Context-Specific Loading States

extension LoadingStateView {
    
    // MARK: - Barcode & UPC
    
    static func scanningBarcode() -> LoadingStateView {
        LoadingStateView(message: "Scanning barcode...")
    }
    
    static func lookingUpProduct() -> LoadingStateView {
        LoadingStateView(message: "Looking up product...")
    }
    
    // MARK: - Data Operations
    
    static func exportingData(progress: Double? = nil) -> LoadingStateView {
        LoadingStateView(
            message: "Exporting data...",
            showProgress: progress != nil,
            progress: progress
        )
    }
    
    static func importingData(progress: Double? = nil) -> LoadingStateView {
        LoadingStateView(
            message: "Importing data...",
            showProgress: progress != nil,
            progress: progress
        )
    }
    
    static func creatingBackup() -> LoadingStateView {
        LoadingStateView(message: "Creating backup...")
    }
    
    static func restoringBackup() -> LoadingStateView {
        LoadingStateView(message: "Restoring backup...")
    }
    
    static func generatingPDF() -> LoadingStateView {
        LoadingStateView(message: "Generating PDF...")
    }
    
    // MARK: - Generic
    
    static func loading() -> LoadingStateView {
        LoadingStateView(message: "Loading...")
    }
    
    static func saving() -> LoadingStateView {
        LoadingStateView(message: "Saving...")
    }
    
    static func processing() -> LoadingStateView {
        LoadingStateView(message: "Processing...")
    }
}

// MARK: - View Extension for Loading Overlay

extension View {
    /// Add a loading overlay to any view
    func loadingOverlay(
        isLoading: Bool,
        message: String = "Loading...",
        showProgress: Bool = false,
        progress: Double? = nil
    ) -> some View {
        self.overlay {
            if isLoading {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        if showProgress, let progress = progress {
                            ProgressView(value: progress, total: 1.0)
                                .progressViewStyle(.linear)
                                .frame(width: 200)
                                .tint(.white)
                        } else {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(1.5)
                                .tint(.white)
                        }
                        
                        Text(message)
                            .font(.body)
                            .foregroundStyle(.white)
                    }
                    .padding(32)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Standard Loading") {
    LoadingStateView.loading()
}

#Preview("With Progress") {
    LoadingStateView.exportingData(progress: 0.65)
}

#Preview("Inline Loading") {
    InlineLoadingView(message: "Loading data...")
}

#Preview("Loading Overlay") {
    VStack {
        Text("Content Behind Loading Overlay")
            .font(.largeTitle)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.gray.opacity(0.1))
    .loadingOverlay(
        isLoading: true,
        message: "Exporting data...",
        showProgress: true,
        progress: 0.45
    )
}
