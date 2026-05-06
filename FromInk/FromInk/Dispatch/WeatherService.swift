import Foundation
import CoreLocation
import Dependencies
import WeatherKit

// MARK: - Snapshot

struct WeatherSnapshot: Equatable, Codable, Sendable {
    let temperature: Double          // always stored in °F for simplicity
    let symbolName: String

    var formattedTemperature: String {
        let unit: UnitTemperature = Locale.current.measurementSystem == .metric ? .celsius : .fahrenheit
        let value = unit == .celsius ? (temperature - 32) * 5 / 9 : temperature
        let m = Measurement(value: value, unit: unit)
        return m.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}

// MARK: - Cache

private struct CachedWeather: Codable {
    let snapshot: WeatherSnapshot
    let cachedAt: Date

    var isStale: Bool { Date().timeIntervalSince(cachedAt) > 1800 }
}

private let cacheKey = "weatherCache"
private let disabledKey = "weatherDisabledUntil"

private func loadCachedWeather() -> CachedWeather? {
    guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
    return try? JSONDecoder().decode(CachedWeather.self, from: data)
}

private func saveWeatherCache(_ snapshot: WeatherSnapshot) {
    let cached = CachedWeather(snapshot: snapshot, cachedAt: Date())
    if let data = try? JSONEncoder().encode(cached) {
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}

// MARK: - Dependency

struct WeatherDependency: Sendable {
    var fetch: @Sendable (CLLocation) async -> WeatherSnapshot?
    var fetchAttribution: @Sendable () async -> WeatherAttributionSnapshot?
}

extension WeatherDependency: DependencyKey {
    static var liveValue: Self {
        .init(
        fetch: { location in
            // Check if disabled until next month due to OVER_QUOTA
            if let disabledUntil = UserDefaults.standard.object(forKey: disabledKey) as? TimeInterval,
               Date().timeIntervalSince1970 < disabledUntil {
                return nil
            }

            // Return 30-minute cache if fresh
            if let cached = loadCachedWeather(), !cached.isStale {
                return cached.snapshot
            }

            do {
                let service = WeatherKit.WeatherService.shared
                let weather = try await service.weather(for: location)
                let tempF = weather.currentWeather.temperature
                    .converted(to: .fahrenheit).value
                let snapshot = WeatherSnapshot(
                    temperature: tempF,
                    symbolName: weather.currentWeather.symbolName
                )
                saveWeatherCache(snapshot)
                return snapshot
            } catch {
                if error.localizedDescription.contains("OVER_QUOTA") {
                    let nextMonth = Calendar.current.nextDate(
                        after: Date(),
                        matching: DateComponents(day: 1),
                        matchingPolicy: .nextTime
                    )!
                    UserDefaults.standard.set(
                        nextMonth.timeIntervalSince1970,
                        forKey: disabledKey
                    )
                }
                return nil
            }
        },
        fetchAttribution: {
            guard let attribution = try? await WeatherKit.WeatherService.shared.attribution else {
                return nil
            }
            return WeatherAttributionSnapshot(
                legalPageURL: attribution.legalPageURL,
                lightLogoURL: attribution.combinedMarkLightURL,
                darkLogoURL: attribution.combinedMarkDarkURL
            )
        })
    }

    static var testValue: Self {
        .init(
            fetch: { _ in WeatherSnapshot(temperature: 72, symbolName: "sun.max.fill") },
            fetchAttribution: { nil }
        )
    }
}

extension DependencyValues {
    var weatherService: WeatherDependency {
        get { self[WeatherDependency.self] }
        set { self[WeatherDependency.self] = newValue }
    }
}
