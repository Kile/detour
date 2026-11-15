import Foundation
import CoreLocation
import Observation

enum LocationError: LocalizedError, Equatable {
    case denied
    case restricted
    case unavailable
    case timeout

    var errorDescription: String? {
        switch self {
        case .denied: return "Location is off for SideQuest. Turn it on in Settings → SideQuest → Location, or switch to Venue scope."
        case .restricted: return "Location access is restricted on this device. Try Venue scope instead."
        case .unavailable: return "Couldn't find where you are right now. Step outside or try again in a moment."
        case .timeout: return "Getting your location took too long. Try again, or switch to Venue scope."
        }
    }
}

/// When-in-use location only. One-shot fixes, no background tracking.
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationWaiters: [CheckedContinuation<CLLocation, Error>] = []
    private var authorizationWaiters: [CheckedContinuation<CLAuthorizationStatus, Never>] = []

    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var lastLocation: CLLocation?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// Asks for when-in-use permission if needed and returns the resulting status.
    func ensurePermission() async throws {
        if authorizationStatus == .notDetermined {
            authorizationStatus = await withCheckedContinuation { continuation in
                authorizationWaiters.append(continuation)
                manager.requestWhenInUseAuthorization()
            }
        }
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return
        case .restricted: throw LocationError.restricted
        default: throw LocationError.denied
        }
    }

    /// A fresh location fix (re-uses one from the last 30 s if it is accurate enough).
    func currentLocation(maxAge: TimeInterval = 30, timeout: TimeInterval = 15) async throws -> CLLocation {
        try await ensurePermission()
        if let last = lastLocation, -last.timestamp.timeIntervalSinceNow < maxAge, last.horizontalAccuracy <= 100 {
            return last
        }
        return try await withThrowingTaskGroup(of: CLLocation.self) { group in
            group.addTask { @MainActor in
                try await withCheckedThrowingContinuation { continuation in
                    self.locationWaiters.append(continuation)
                    self.manager.requestLocation()
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw LocationError.timeout
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw LocationError.unavailable }
            return first
        }
    }

    /// Neighbourhood/city name for the prompt (never coordinates).
    func placeName(for location: CLLocation) async -> String? {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let placemark = placemarks?.first else { return nil }
        let parts = [placemark.subLocality, placemark.locality].compactMap { $0 }
        return parts.isEmpty ? placemark.name : parts.joined(separator: ", ")
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorizationStatus = status
            guard status != .notDetermined else { return }
            let waiters = authorizationWaiters
            authorizationWaiters.removeAll()
            waiters.forEach { $0.resume(returning: status) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        MainActor.assumeIsolated {
            lastLocation = location
            let waiters = locationWaiters
            locationWaiters.removeAll()
            waiters.forEach { $0.resume(returning: location) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let mapped: LocationError = (error as? CLError)?.code == .denied ? .denied : .unavailable
        MainActor.assumeIsolated {
            // kCLErrorLocationUnknown is transient; keep waiting for the next update.
            if (error as? CLError)?.code == .locationUnknown { return }
            let waiters = locationWaiters
            locationWaiters.removeAll()
            waiters.forEach { $0.resume(throwing: mapped) }
        }
    }
}

extension CLLocation {
    var geoPoint: GeoPoint { GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude) }
}
