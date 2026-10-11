//
//  BarcodeScannerView.swift
//  ShutterManager
//

import SwiftUI
import AVFoundation

/// Camera barcode scanner with a viewfinder overlay. On a successful scan it
/// runs a UPC lookup (via `UPCLookupService`) and presents the result, falling
/// back to manual code entry. Reports results through the `onBarcodeScanned`
/// and `onProductFound` callbacks.
struct BarcodeScannerView: View {
    @StateObject private var scannerService = BarcodeScannerService()
    @StateObject private var lookupService = UPCLookupService()
    @Environment(\.dismiss) private var dismiss
    
    let onBarcodeScanned: (String) -> Void
    let onProductFound: ((ProductInfo) -> Void)?
    
    @State private var showingProductInfo = false
    @State private var foundProduct: ProductInfo?
    /// Set by the product sheet's "Add to Inventory" / "Enter Manually": the scan is finished,
    /// so the scanner closes once that sheet has gone (see the sheet's `onDismiss`).
    @State private var closeAfterProductInfo = false
    @State private var showingManualEntry = false
    @State private var manualUPC = ""
    @State private var animateScanLine = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Camera preview background
                ZStack {
                    CameraPreview(scannerService: scannerService, isSessionReady: scannerService.isSessionReady)
                        .ignoresSafeArea()
                    
                    // Loading indicator when session is not ready
                    if !scannerService.isSessionReady && scannerService.isScanning {
                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            
                            Text("Starting Camera...")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(.black.opacity(0.7))
                        .cornerRadius(12)
                    }
                }
                
                // Scanning overlay
                VStack {
                    // Top instruction area
                    VStack(spacing: 8) {
                        Text("Scan Barcode")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        Text("Point camera at product barcode or UPC code")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 20)
                    .background(.black.opacity(0.7))
                    
                    Spacer()
                    
                    // Scanning viewfinder
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(scannerService.isScanning ? Color.green : Color.white, lineWidth: 3)
                            .frame(width: 250, height: 150)
                            // One-shot white→green fade when scanning begins. The previous
                            // `.repeatForever()` kept a live animation transaction going for the
                            // whole session even though the stroke color has a single static end
                            // state (nothing to oscillate) — a perpetual no-op.
                            .animation(.easeInOut(duration: 0.3), value: scannerService.isScanning)
                        
                        // Scanning line animation
                        if scannerService.isScanning {
                            Rectangle()
                                .fill(Color.green.opacity(0.8))
                                .frame(width: 250, height: 2)
                                .offset(y: animateScanLine ? 75 : -75)
                                .onAppear { animateScanLine = true }
                                .onDisappear { animateScanLine = false }
                                .animation(.linear(duration: 2).repeatForever(autoreverses: true), value: animateScanLine)
                        }
                        
                        // Corner brackets
                        VStack {
                            HStack {
                                CornerBracket(corner: .topLeading)
                                Spacer()
                                CornerBracket(corner: .topTrailing)
                            }
                            Spacer()
                            HStack {
                                CornerBracket(corner: .bottomLeading)
                                Spacer()
                                CornerBracket(corner: .bottomTrailing)
                            }
                        }
                        .frame(width: 250, height: 150)
                    }
                    .accessibilityHidden(true)

                    Spacer()
                    
                    // Bottom controls
                    VStack(spacing: 16) {
                        if let error = scannerService.scanError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal)
                                .multilineTextAlignment(.center)
                        }
                        
                        HStack(spacing: 40) {
                            // Cancel button
                            Button("Cancel") {
                                HapticFeedbackManager.shared.buttonTap()
                                dismiss()
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.black.opacity(0.7))
                            .cornerRadius(25)
                            
                            // Manual entry button
                            Button("Enter Manually") {
                                HapticFeedbackManager.shared.buttonTap()
                                showingManualEntry = true
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.black.opacity(0.7))
                            .cornerRadius(25)
                        }
                    }
                    .padding(.bottom, 40)
                    .background(.black.opacity(0.7))
                }
                
                // UPC Lookup loading overlay
                if lookupService.isLoading {
                    Color.black.opacity(0.8)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 24) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        
                        Text("Looking up product...")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        if let scannedCode = scannerService.scannedCode {
                            Text(scannedCode)
                                .font(.monospaced(.body)())
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(.white.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                }
                
                // Scanning success overlay (when no UPC lookup or lookup failed)
                else if let scannedCode = scannerService.scannedCode, !lookupService.isLoading {
                    Color.black.opacity(0.8)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 24) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.green)
                        
                        Text("Barcode Scanned!")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        Text(scannedCode)
                            .font(.monospaced(.body)())
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.2))
                            .cornerRadius(8)
                        
                        if let error = lookupService.lastError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.horizontal)
                                .multilineTextAlignment(.center)
                        }
                        
                        Button("Use This Code") {
                            HapticFeedbackManager.shared.success()
                            onBarcodeScanned(scannedCode)
                            dismiss()
                        }
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(.white)
                        .cornerRadius(25)
                        
                        Button("Scan Again") {
                            HapticFeedbackManager.shared.buttonTap()
                            scannerService.resetScanner()
                            scannerService.startScanning()
                        }
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .onAppear {
                scannerService.startScanning()
            }
            .onChange(of: scannerService.scannedCode) { oldValue, newValue in
                if let barcode = newValue {
                    // No haptic here: BarcodeScannerService already fires `barcodeScanSuccess()`
                    // at detection, and firing it again doubled the success buzz on every scan.
                    Task {
                        if let product = await lookupService.lookupProduct(barcode: barcode) {
                            foundProduct = product
                            closeAfterProductInfo = false
                            showingProductInfo = true
                        }
                    }
                }
            }
            .onDisappear {
                scannerService.stopScanning()
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        // "Add to Inventory" and "Enter Manually" finish the scan, but ProductInfoView can only
        // dismiss ITSELF — which used to leave this scanner's "Barcode Scanned!" screen up behind
        // it, needing a second "Use This Code" (re-reporting the code) or Cancel. Those two
        // closures flag the scanner to close too, once the product sheet is fully gone: dismissing
        // both presentations in the same update is unreliable. Cancel, swipe-down and Scan Again
        // keep the scanner open.
        .sheet(isPresented: $showingProductInfo, onDismiss: {
            if closeAfterProductInfo {
                closeAfterProductInfo = false
                dismiss()
            }
        }) {
            if let product = foundProduct {
                ProductInfoView(
                    productInfo: product,
                    onUseProduct: { productInfo in
                        if let onProductFound = onProductFound {
                            onProductFound(productInfo)
                        } else {
                            onBarcodeScanned(productInfo.barcode)
                        }
                        closeAfterProductInfo = true
                    },
                    onManualEntry: {
                        if let barcode = scannerService.scannedCode {
                            onBarcodeScanned(barcode)
                        }
                        closeAfterProductInfo = true
                    },
                    onScanAgain: {
                        showingProductInfo = false
                        scannerService.resetScanner()
                        scannerService.startScanning()
                    }
                )
            }
        }
        .sheet(isPresented: $showingManualEntry) {
            ManualUPCEntrySheet(
                upc: $manualUPC,
                onSubmit: { upc in
                    HapticFeedbackManager.shared.success()
                    onBarcodeScanned(upc)
                    manualUPC = ""   // don't show this code again on the next open
                    showingManualEntry = false
                    dismiss()
                },
                onCancel: {
                    HapticFeedbackManager.shared.buttonTap()
                    manualUPC = ""   // abandoned input shouldn't reappear on reopen
                    showingManualEntry = false
                    scannerService.startScanning()
                }
            )
        }
    }
}

// MARK: - Camera Preview

/// Hosts the `AVCaptureVideoPreviewLayer` for the scanner's capture session.
///
/// The layer is the service's cached one (`getPreviewLayer()`), attached once when the view is
/// made; updates only show or hide it, and layout only resizes it. `updateUIView` used to tear
/// the layer down and build a new one on EVERY published change of the scanner (scan state,
/// errors, the scanned code…) — a visible flicker plus a fresh layer and layout pass each time.
struct CameraPreview: UIViewRepresentable {
    let scannerService: BarcodeScannerService
    /// The session has live inputs and outputs; until then the view stays black.
    let isSessionReady: Bool

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.attach(scannerService.getPreviewLayer())
        view.setPreviewVisible(isSessionReady)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.setPreviewVisible(isSessionReady)
    }
}

class CameraPreviewUIView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A standalone sublayer animates frame changes implicitly; track the view's bounds exactly.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
    }

    /// Installs the (cached) preview layer once. Re-attaching the same layer is a no-op.
    func attach(_ layer: AVCaptureVideoPreviewLayer?) {
        guard let layer, layer !== previewLayer else { return }
        previewLayer?.removeFromSuperlayer()
        self.layer.addSublayer(layer)   // also removes it from any previous superlayer
        previewLayer = layer
        setNeedsLayout()
    }

    /// Shows the preview only while the session is ready, so a stopped or reconfiguring session
    /// shows black rather than a frozen frame. Cheap: no layer is created or removed.
    func setPreviewVisible(_ visible: Bool) {
        guard let previewLayer, previewLayer.isHidden == visible else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.isHidden = !visible
        CATransaction.commit()
    }
}

// MARK: - Manual UPC Entry Sheet

/// Fallback sheet for typing a barcode by hand when scanning isn't possible.
/// Accepts 8/12/13/14-digit codes (EAN-8, UPC-A, EAN-13, GTIN-14).
struct ManualUPCEntrySheet: View {
    @Binding var upc: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var isValidUPC: Bool {
        let trimmed = upc.trimmingCharacters(in: .whitespaces)
        return [8, 12, 13, 14].contains(trimmed.count) && trimmed.allSatisfy({ $0.isNumber })
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("UPC/Barcode Number") {
                    TextField("Enter 8, 12, 13, or 14 digit code", text: $upc)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    
                    if !upc.isEmpty && !isValidUPC {
                        Label(
                            "Invalid format - must be 8, 12, 13, or 14 digits",
                            systemImage: "exclamationmark.circle.fill"
                        )
                        .foregroundColor(.orange)
                        .font(.caption)
                    }
                }
                
                Section("Common UPC Formats") {
                    Text("EAN-8: 8 digits")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("UPC-A: 12 digits")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("EAN-13: 13 digits")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("GTIN-14: 14 digits")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Enter Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Code") {
                        let trimmed = upc.trimmingCharacters(in: .whitespaces)
                        onSubmit(trimmed)
                    }
                    .disabled(!isValidUPC)
                }
            }
        }
    }
}

// MARK: - Corner Bracket

/// Decorative L-shaped corner bracket for one corner of the scanner viewfinder.
struct CornerBracket: View {
    enum Corner {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
    }
    
    let corner: Corner
    
    var body: some View {
        Path { path in
            let size: CGFloat = 20
            
            switch corner {
            case .topLeading:
                path.move(to: CGPoint(x: size, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: size))
            case .topTrailing:
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: size, y: 0))
                path.addLine(to: CGPoint(x: size, y: size))
            case .bottomLeading:
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: size))
                path.addLine(to: CGPoint(x: size, y: size))
            case .bottomTrailing:
                path.move(to: CGPoint(x: size, y: 0))
                path.addLine(to: CGPoint(x: size, y: size))
                path.addLine(to: CGPoint(x: 0, y: size))
            }
        }
        .stroke(Color.white, lineWidth: 3)
        .frame(width: 20, height: 20)
    }
}

#Preview {
    BarcodeScannerView(
        onBarcodeScanned: { _ in },
        onProductFound: { _ in }
    )
}
