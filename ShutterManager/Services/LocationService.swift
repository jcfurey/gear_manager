//
//  LocationService.swift
//  ShutterManager
//
//  One-shot location for the sky planners: asked for only when you tap "Use My Location", and
//  only while the app is in use.
//

import Foundation
import CoreLocation

@MainActor
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    @Published private(set) var location: CLLocation?
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isLocating = false
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()
    /// A request is waiting for the permission prompt's answer.
    private var wantsLocation = false

    override init() {
        super.init()
        manager.delegate = self
        // A hundred metres is plenty for sun and moon times, and it's quick to get.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorization = manager.authorizationStatus
    }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    static let deniedMessage = "Location access is off for Shutter Manager. Turn it on in Settings → Privacy & Security → Location Services, or pick the place on the map."

    /// Gets the current location once, asking for permission the first time.
    func requestLocation() {
        errorMessage = nil
        switch manager.authorizationStatus {
        case .notDetermined:
            wantsLocation = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            isLocating = true
            manager.requestLocation()
        default:
            errorMessage = Self.deniedMessage
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    // The manager was made on the main thread, so it calls back there.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorization = status
            guard wantsLocation, status != .notDetermined else { return }
            wantsLocation = false
            requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let latest = locations.last
        MainActor.assumeIsolated {
            location = latest
            isLocating = false
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        MainActor.assumeIsolated {
            isLocating = false
            errorMessage = denied
                ? Self.deniedMessage
                : "Your location isn't available right now. Try again, or pick the place on the map."
        }
    }
}
