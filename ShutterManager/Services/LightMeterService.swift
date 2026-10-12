//
//  LightMeterService.swift
//  ShutterManager
//
//  A reflected-light meter from the camera's auto-exposure: what it chose, corrected by how far
//  its picture is from its target, read a few times a second.
//

import Combine
@preconcurrency import AVFoundation

@MainActor
final class LightMeterService: ObservableObject {
    enum Status: Equatable {
        case idle, starting, running
        /// No camera, no permission, or the camera failed; the message says which.
        case unavailable(String)
    }

    @Published private(set) var status: Status = .idle
    /// The scene as EV at ISO 100, steadied and before calibration. Nil until the first reading.
    @Published private(set) var sceneEV: Double?
    /// What the camera chose for the latest reading.
    @Published private(set) var exposure: CameraExposure?
    /// Another app or a call has the camera for now; the session resumes by itself.
    @Published private(set) var isInterrupted = false

    static let noCameraMessage = "This device has no camera to meter with. Enter the scene's EV by hand instead."
    static let deniedMessage = "Camera access is off for Shutter Manager. Turn it on in Settings → Privacy & Security → Camera, or enter the scene's EV by hand."
    static let failedMessage = "The camera stopped. Try again."

    /// How often the reading updates.
    static let sampleInterval: Duration = .milliseconds(200)

    private let capture: CaptureSessionCoordinator
    private var device: AVCaptureDevice?
    private var startTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var generation = 0
    private var observers: [NSObjectProtocol] = []
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    init(capture: CaptureSessionCoordinator = .shared) {
        self.capture = capture
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification,
                                            object: capture.session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.status == .running else { return }
                self.isInterrupted = true
            }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification,
                                            object: capture.session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isInterrupted = false }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                                            object: capture.session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.status == .running else { return }
                self.stop()
                self.status = .unavailable(Self.failedMessage)
            }
        })
    }

    /// Starts the camera and the readings, asking for camera access the first time.
    func start() {
        switch status {
        case .starting, .running: return
        case .idle, .unavailable: break
        }
        generation &+= 1
        let requestedGeneration = generation
        status = .starting
        startTask = Task { [weak self] in
            guard let self else { return }
            let access = await CaptureSessionCoordinator.requestAccess()
            guard !Task.isCancelled, generation == requestedGeneration else { return }
            switch access {
            case .granted: break
            case .denied:
                status = .unavailable(Self.deniedMessage)
                return
            case .noCamera:
                status = .unavailable(Self.noCameraMessage)
                return
            }
            do {
                let device = try await capture.startLightMeter()
                guard !Task.isCancelled, generation == requestedGeneration else {
                    // `stop()` ran while the camera was starting, and its stop may have reached the
                    // camera queue first. Stop again unless a newer start has taken over.
                    if status == .idle { capture.stop(for: .lightMeter) }
                    return
                }
                self.device = device
                followRotation(of: device)
                status = .running
                startPolling()
            } catch {
                guard generation == requestedGeneration else { return }
                status = .unavailable(error.localizedDescription)
            }
        }
    }

    /// Stops the readings and, unless the barcode scanner has taken it, the camera.
    func stop() {
        generation &+= 1
        startTask?.cancel()
        startTask = nil
        pollTask?.cancel()
        pollTask = nil
        rotationObservation?.invalidate()
        rotationObservation = nil
        rotationCoordinator = nil
        capture.stop(for: .lightMeter)
        device = nil
        status = .idle
        isInterrupted = false
        sceneEV = nil
        exposure = nil
    }

    /// Meters from a point on the sensor (0–1, from the preview layer), or the whole frame for nil.
    func meter(at devicePoint: CGPoint?) {
        guard status == .running else { return }
        capture.meterLight(at: devicePoint)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.sample()
                try? await Task.sleep(for: Self.sampleInterval)
            }
        }
    }

    private func sample() {
        guard let device, !isInterrupted else { return }
        let reading = CameraExposure(aperture: Double(device.lensAperture), shutter: device.exposureDuration.seconds,
                                     iso: Double(device.iso), targetOffset: Double(device.exposureTargetOffset))
        guard let ev = reading.ev100 else { return }
        exposure = reading
        sceneEV = LightMeter.smoothed(ev, previous: sceneEV)
    }

    /// Keeps the preview level as the device turns (the iPad shows it in any orientation).
    private func followRotation(of device: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: capture.previewLayer)
        rotationCoordinator = coordinator
        applyPreviewRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, change in
            guard let angle = change.newValue else { return }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.applyPreviewRotation(angle) }
            }
        }
    }

    private func applyPreviewRotation(_ angle: CGFloat) {
        guard let connection = capture.previewLayer.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    deinit {
        startTask?.cancel()
        pollTask?.cancel()
        capture.stop(for: .lightMeter)
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
