@preconcurrency import SwiftUI
@preconcurrency import AVFoundation

@MainActor
class BarcodeScannerService: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var scannedCode: String?
    @Published var scanError: String?
    @Published var hasPermission = false
    @Published var isSessionReady = false

    private let capture: CaptureSessionCoordinator
    private let permissionProvider: (() async -> Bool)?
    private var startTask: Task<Void, Never>?
    private var generation = 0
    private var activeOutput: AVCaptureMetadataOutput?
    private var observers: [NSObjectProtocol] = []

    var session: AVCaptureSession? { capture.session }

    init(capture: CaptureSessionCoordinator = .shared, permissionProvider: (() async -> Bool)? = nil) {
        self.capture = capture
        self.permissionProvider = permissionProvider
        super.init()
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: self.capture.session, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isScanning else { return }
                    self.stopScanning()
                    self.scanError = "Camera access was interrupted. Close the scanner and try again."
                }
            })
        }
    }

    func checkCameraPermissions() async {
        if let permissionProvider {
            hasPermission = await permissionProvider()
        } else {
            switch await CaptureSessionCoordinator.requestAccess() {
            case .granted: hasPermission = true
            case .denied: hasPermission = false
            case .noCamera:
                hasPermission = false
                scanError = "Camera not available on this device."
                return
            }
        }
        if !hasPermission {
            scanError = "Camera access is required. Enable it in Settings → Privacy & Security → Camera."
        }
    }

    func startScanning() {
        guard !isScanning else { return }
        generation &+= 1
        let requestedGeneration = generation
        isScanning = true
        isSessionReady = false
        scannedCode = nil
        scanError = nil
        startTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == requestedGeneration { startTask = nil } }
            guard !Task.isCancelled else { return }
            await checkCameraPermissions()
            guard !Task.isCancelled, generation == requestedGeneration, isScanning else { return }
            guard hasPermission else { isScanning = false; return }
            do {
                let output = try await capture.startBarcodeScanning(delegate: self)
                guard !Task.isCancelled, generation == requestedGeneration, isScanning else {
                    // `stopScanning()` ran while this start was in flight. The start hops off the
                    // main actor before enqueuing on the camera queue, so that stop's
                    // `capture.stop(for:)` can land on the queue FIRST — the session then starts
                    // after it and stayed running (camera indicator on) behind a stopped UI. Stop
                    // it again now, unless a newer scan has begun (its start reconfigures the session).
                    if !isScanning { capture.stop(for: .barcodeScanner) }
                    return
                }
                activeOutput = output
                isSessionReady = true
            } catch {
                guard generation == requestedGeneration else { return }
                isScanning = false
                isSessionReady = false
                activeOutput = nil
                scanError = error.localizedDescription
            }
        }
    }

    func stopScanning() {
        generation &+= 1
        startTask?.cancel()
        startTask = nil
        capture.stop(for: .barcodeScanner)
        isScanning = false
        isSessionReady = false
        activeOutput = nil
    }

    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        capture.previewLayer
    }

    func resetScanner() {
        scannedCode = nil
        scanError = nil
    }

    deinit {
        startTask?.cancel()
        capture.stop(for: .barcodeScanner)
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}

extension BarcodeScannerService: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        // The delegate is registered on main. Reject callbacks from a stopped/replaced output.
        MainActor.assumeIsolated {
            guard isScanning, isSessionReady, output === activeOutput, scannedCode == nil,
                  let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            scannedCode = value
            stopScanning()
            HapticFeedbackManager.shared.barcodeScanSuccess()
        }
    }
}

// MARK: - Supporting Types

/// Barcode scan result with additional metadata
struct BarcodeResult {
    let code: String
    let type: AVMetadataObject.ObjectType
    let timestamp: Date
    
    var displayType: String {
        switch type {
        case .ean13: return "EAN-13"
        case .ean8: return "EAN-8"
        case .upce: return "UPC-E"
        case .code128: return "Code 128"
        case .code39: return "Code 39"
        case .code93: return "Code 93"
        case .qr: return "QR Code"
        case .pdf417: return "PDF417"
        default: return "Barcode"
        }
    }
}
