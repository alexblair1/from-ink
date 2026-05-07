import Foundation
import CoreLocation
import Dependencies

struct LocationService: Sendable {
    var currentLocation: @Sendable () async -> CLLocation?
}

extension LocationService: DependencyKey {
    static var liveValue: Self {
        .init(currentLocation: {
            await OneShotLocationFetcher.shared.fetch()
        })
    }

    static var testValue: Self {
        .init(currentLocation: {
            CLLocation(latitude: 37.3382, longitude: -121.8863)
        })
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
