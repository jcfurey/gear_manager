@preconcurrency import SwiftUI
@preconcurrency import AVFoundation

protocol BarcodeCaptureControlling: AnyObject {
    var session: AVCaptureSession { get }
    func start(delegate: AVCaptureMetadataOutputObjectsDelegate) async throws -> AVCaptureMetadataOutput
    func stop()
}

/// The session reference is constant; every configuration/start/stop runs on this serial queue.
private final class BarcodeCaptureController: BarcodeCaptureControlling, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "jcameronfurey.shuttermanager.camera", qos: .userInitiated)

    func start(delegate: AVCaptureMetadataOutputObjectsDelegate) async throws -> AVCaptureMetadataOutput {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    if session.isRunning { session.stopRunning() }
                    let output = try configure(delegate: delegate)
                    session.startRunning()
                    guard session.isRunning else { throw CameraError.unavailable }
                    continuation.resume(returning: output)
                } catch {
                    session.stopRunning()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configure(delegate: AVCaptureMetadataOutputObjectsDelegate) throws -> AVCaptureMetadataOutput {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        guard let device = AVCaptureDevice.default(for: .video) else { throw CameraError.unavailable }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.unavailable }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { throw CameraError.unavailable }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(delegate, queue: .main)
        let desired: [AVMetadataObject.ObjectType] = [.ean8, .ean13, .pdf417, .qr, .code128, .code39, .code93, .upce]
        output.metadataObjectTypes = desired.filter { output.availableMetadataObjectTypes.contains($0) }
        return output
    }

    func stop() {
        queue.async { [self] in session.stopRunning() }
    }

    deinit {
        let session = session
        queue.async { session.stopRunning() }
    }
}

private enum CameraError: LocalizedError {
    case unavailable
    var errorDescription: String? { "The camera could not start. Close the scanner and try again." }
}

@MainActor
class BarcodeScannerService: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var scannedCode: String?
    @Published var scanError: String?
    @Published var hasPermission = false
    @Published var isSessionReady = false

    private let capture: BarcodeCaptureControlling
    private let permissionProvider: (() async -> Bool)?
    private var startTask: Task<Void, Never>?
    private var generation = 0
    private var activeOutput: AVCaptureMetadataOutput?
    private var observers: [NSObjectProtocol] = []
    private var previewLayer: AVCaptureVideoPreviewLayer?

    var session: AVCaptureSession? { capture.session }

    init(capture: BarcodeCaptureControlling? = nil, permissionProvider: (() async -> Bool)? = nil) {
        self.capture = capture ?? BarcodeCaptureController()
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
        } else if AVCaptureDevice.default(for: .video) == nil {
            hasPermission = false
            scanError = "Camera not available on this device."
            return
        } else {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: hasPermission = true
            case .notDetermined: hasPermission = await AVCaptureDevice.requestAccess(for: .video)
            default: hasPermission = false
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
                let output = try await capture.start(delegate: self)
                guard !Task.isCancelled, generation == requestedGeneration, isScanning else {
                    // `stopScanning()` ran while this start was in flight. `capture.start` hops off
                    // the main actor before enqueuing on the camera queue, so that stop's
                    // `capture.stop()` can land on the queue FIRST — the session then starts after
                    // it and stayed running (camera indicator on) behind a stopped UI. Stop it
                    // again now, unless a newer scan has begun (its start reconfigures the session).
                    if !isScanning { capture.stop() }
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
        capture.stop()
        isScanning = false
        isSessionReady = false
        activeOutput = nil
    }

    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        if previewLayer == nil {
            previewLayer = AVCaptureVideoPreviewLayer(session: capture.session)
            previewLayer?.videoGravity = .resizeAspectFill
        }
        return previewLayer
    }

    func resetScanner() {
        scannedCode = nil
        scanError = nil
    }

    deinit {
        startTask?.cancel()
        capture.stop()
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
