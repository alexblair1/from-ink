import Foundation
import CoreLocation
import Dependencies

struct LocationService: Sendable {
    var currentLocation: @Sendable () async -> CLLocation?
}

extension LocationService: DependencyKey {
    static var liveValue: Self {
        .init(currentLocation: {
            await MainActor.run {
                let manager = CLLocationManager()
                switch manager.authorizationStatus {
                case .authorizedWhenInUse, .authorizedAlways:
                    return manager.location
                case .notDetermined:
                    // Request permission; location will be nil this session,
                    // available on the next launch once granted.
                    manager.requestWhenInUseAuthorization()
                    return nil
                default:
                    return nil
                }
            }
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
