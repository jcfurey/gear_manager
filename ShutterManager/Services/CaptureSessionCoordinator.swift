//
//  CaptureSessionCoordinator.swift
//  ShutterManager
//
//  The app's one camera. The barcode scanner and the light meter both run on this session.
//

@preconcurrency import AVFoundation

/// Owns the capture session the barcode scanner and the light meter share.
///
/// Each start reconfigures the session for its client and makes that client the owner. A
/// client's stop only stops the session while that client still owns it, so a scanner closing
/// over the light meter (or the reverse) can't stop the camera the other one just started. The
/// session reference is constant; every configuration, start and stop runs on one serial queue.
final class CaptureSessionCoordinator: @unchecked Sendable {
    enum Client: Sendable {
        case barcodeScanner, lightMeter
    }

    enum Access {
        case granted, denied, noCamera
    }

    static let shared = CaptureSessionCoordinator()

    let session = AVCaptureSession()

    /// The one preview layer on the session, shared by every camera view. A layer has one
    /// superlayer, so the view showing the camera attaches it (`CameraPreviewUIView.attach`),
    /// taking it from any other.
    let previewLayer: AVCaptureVideoPreviewLayer

    private let queue = DispatchQueue(label: "jcameronfurey.shuttermanager.camera", qos: .userInitiated)
    /// The client the session is set up for. Read and written only on `queue`.
    private var owner: Client?
    /// The light meter's camera while it owns the session. Only on `queue`.
    private var meterDevice: AVCaptureDevice?

    init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
    }

    /// Camera permission, asking the first time.
    static func requestAccess() async -> Access {
        guard AVCaptureDevice.default(for: .video) != nil else { return .noCamera }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .granted
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
        default: return .denied
        }
    }

    // MARK: - Clients

    /// Sets the session up to read barcodes, delivering them to `delegate` on the main queue.
    func startBarcodeScanning(delegate: AVCaptureMetadataOutputObjectsDelegate) async throws -> AVCaptureMetadataOutput {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    let output = try run(for: .barcodeScanner) { session -> AVCaptureMetadataOutput in
                        guard let device = AVCaptureDevice.default(for: .video) else { throw CaptureError.unavailable }
                        try Self.addInput(for: device, to: session)
                        let metadata = AVCaptureMetadataOutput()
                        guard session.canAddOutput(metadata) else { throw CaptureError.unavailable }
                        session.addOutput(metadata)
                        metadata.setMetadataObjectsDelegate(delegate, queue: .main)
                        let desired: [AVMetadataObject.ObjectType] = [.ean8, .ean13, .pdf417, .qr, .code128, .code39, .code93, .upce]
                        metadata.metadataObjectTypes = desired.filter { metadata.availableMetadataObjectTypes.contains($0) }
                        return metadata
                    }
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Sets the session up for metering with the main back camera, which auto-exposes from the
    /// middle of the frame. Returns the camera, for reading its exposure.
    func startLightMeter() async throws -> AVCaptureDevice {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    let device = try run(for: .lightMeter) { session -> AVCaptureDevice in
                        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                                ?? AVCaptureDevice.default(for: .video) else { throw CaptureError.unavailable }
                        try Self.addInput(for: device, to: session)
                        Self.meter(device, at: nil)
                        return device
                    }
                    meterDevice = device
                    continuation.resume(returning: device)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Meters from `point` (0–1 across the sensor, landscape) or, for nil, the middle of the frame.
    /// Ignored unless the light meter owns the session.
    func meterLight(at point: CGPoint?) {
        queue.async { [self] in
            guard owner == .lightMeter, let meterDevice else { return }
            Self.meter(meterDevice, at: point)
        }
    }

    /// Stops the session if `client` still owns it.
    func stop(for client: Client) {
        queue.async { [self] in
            guard owner == client else { return }
            owner = nil
            meterDevice = nil
            session.stopRunning()
        }
    }

    // MARK: - On the queue

    /// Clears the session, lets `configure` add the client's inputs and outputs, and starts it.
    private func run<T>(for client: Client, _ configure: (AVCaptureSession) throws -> T) throws -> T {
        if session.isRunning { session.stopRunning() }
        owner = client
        meterDevice = nil
        do {
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            for output in session.outputs { session.removeOutput(output) }
            let result: T
            do {
                result = try configure(session)
            } catch {
                session.commitConfiguration()
                throw error
            }
            session.commitConfiguration()
            session.startRunning()
            guard session.isRunning else { throw CaptureError.unavailable }
            return result
        } catch {
            session.stopRunning()
            owner = nil
            throw error
        }
    }

    private static func addInput(for device: AVCaptureDevice, to session: AVCaptureSession) throws {
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CaptureError.unavailable }
        session.addInput(input)
    }

    private static func meter(_ device: AVCaptureDevice, at point: CGPoint?) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = point ?? CGPoint(x: 0.5, y: 0.5)
        }
        // Setting the mode again applies the new point.
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
    }

    deinit {
        let session = session
        queue.async { session.stopRunning() }
    }
}

enum CaptureError: LocalizedError {
    case unavailable

    var errorDescription: String? { "The camera couldn't start. Close this screen and try again." }
}
