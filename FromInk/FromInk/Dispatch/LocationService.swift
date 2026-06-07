import Foundation
import CoreLocation
import Dependencies

struct LocationService: Sendable {
    var currentLocation: @Sendable () async -> CLLocation?
    /// Current authorization state, read from a transient
    /// CLLocationManager instance. Used by the onboarding permissions
    /// row to decide whether to show the switch or OPEN SETTINGS.
    var status: @Sendable () async -> LocationAuthStatus
    /// Triggers the system "Allow While Using App" prompt if the
    /// status is `.notDetermined`. Returns the resolved status. If the
    /// status is already non-`.notDetermined`, returns immediately
    /// without prompting — the user has to go to Settings.
    var requestAccess: @Sendable () async -> LocationAuthStatus
}

extension LocationService: DependencyKey {
    static var liveValue: Self {
        .init(
            currentLocation: {
                await OneShotLocationFetcher.shared.fetch()
            },
            status: {
                await MainActor.run {
                    LocationAuthStatus(CLLocationManager().authorizationStatus)
                }
            },
            requestAccess: {
                let current = await MainActor.run {
                    LocationAuthStatus(CLLocationManager().authorizationStatus)
                }
                // Only path that actually shows the system prompt.
                // OneShotLocationFetcher already handles the
                // request-and-wait dance; we discard its CLLocation
                // result since we only need the post-prompt auth
                // status here.
                if current == .notDetermined {
                    _ = await OneShotLocationFetcher.shared.fetch()
                }
                return await MainActor.run {
                    LocationAuthStatus(CLLocationManager().authorizationStatus)
                }
            }
        )
    }

    static var testValue: Self {
        .init(
            currentLocation: {
                CLLocation(latitude: 37.3382, longitude: -121.8863)
            },
            status: { .notDetermined },
            requestAccess: { .notDetermined }
        )
    }
}

extension DependencyValues {
    var locationService: LocationService {
        get { self[LocationService.self] }
        set { self[LocationService.self] = newValue }
    }
}

// MARK: - One-shot fetcher

@MainActor
private final class OneShotLocationFetcher: NSObject, CLLocationManagerDelegate {
    static let shared = OneShotLocationFetcher()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var isFetching = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func fetch() async -> CLLocation? {
        // If already fetching, wait for the same result
        guard !isFetching else {
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.isFetching = true

            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                if let last = manager.location {
                    resolve(last)
                } else {
                    manager.requestLocation()
                }
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
                // continues in locationManagerDidChangeAuthorization
            default:
                resolve(nil)
            }
        }
    }

    private func resolve(_ location: CLLocation?) {
        isFetching = false
        continuation?.resume(returning: location)
        continuation = nil
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isFetching else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if let last = manager.location {
                resolve(last)
            } else {
                manager.requestLocation()
            }
        case .notDetermined:
            break
        default:
            resolve(nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        resolve(locations.first ?? manager.location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Fall back to last known location rather than returning nil
        resolve(manager.location)
    }
}
