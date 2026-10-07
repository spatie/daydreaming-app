import CoreLocation
import Foundation
import MapKit

enum OnboardingLocationPolicy {
    static func updated(_ state: OnboardingLocationState, authorization: CLAuthorizationStatus) -> OnboardingLocationState {
        guard state == .requesting || state == .denied else { return state }
        switch authorization {
        case .authorized, .authorizedAlways: return .allowed
        case .denied, .restricted: return .denied
        default: return state
        }
    }
}

enum LocalWeatherLocationPolicy {
    static func isFresh(_ location: CLLocation, now: Date = .now) -> Bool {
        CLLocationCoordinate2DIsValid(location.coordinate)
            && location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= 10_000
            && now.timeIntervalSince(location.timestamp) >= -60
            && now.timeIntervalSince(location.timestamp) < 900
    }
}

@MainActor
final class LocationReader: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var location: CLLocation?
    var onLocation: (() -> Void)?
    private var hasRequested = false
    private var isRequesting = false
    private var nextRequestAt = Date.distantPast
    private var nameRequest: MKReverseGeocodingRequest?
    private(set) var placeName: String?
    var onPlaceName: (() -> Void)?
    var freshLocation: CLLocation? {
        location.flatMap { LocalWeatherLocationPolicy.isFresh($0) ? $0 : nil }
    }
    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func request(force: Bool = false) {
        guard !isRequesting, force || Date() >= nextRequestAt else { return }
        guard force || freshLocation == nil else { return }
        hasRequested = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways:
            isRequesting = true
            nextRequestAt = Date().addingTimeInterval(30)
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if hasRequested && (manager.authorizationStatus == .authorized || manager.authorizationStatus == .authorizedAlways) {
            isRequesting = true
            nextRequestAt = Date().addingTimeInterval(30)
            manager.requestLocation()
        } else {
            if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                manager.stopUpdatingLocation()
                isRequesting = false
                location = nil
                nameRequest?.cancel()
                nameRequest = nil
                placeName = nil
                onPlaceName?()
            }
            onLocation?()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        isRequesting = false
        guard let latest = locations.last(where: { LocalWeatherLocationPolicy.isFresh($0) }) else {
            onLocation?()
            return
        }
        let previous = location
        location = latest
        onLocation?()
        if placeName == nil || previous.map({ latest.distance(from: $0) > 1_000 }) == true {
            nameRequest?.cancel()
            placeName = nil
            onPlaceName?()
            guard let request = MKReverseGeocodingRequest(location: latest) else { return }
            nameRequest = request
            request.getMapItems { [weak self] items, _ in
                guard let self, self.nameRequest === request else { return }
                self.placeName = items?.first?.addressRepresentations?.cityWithContext
                self.nameRequest = nil
                self.onPlaceName?()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isRequesting = false
        onLocation?()
    }
}

enum WeatherContextError: LocalizedError {
    case waitingForLocation
    case locationPermissionRequired
    case forecastUnavailable

    var errorDescription: String? {
        switch self {
        case .waitingForLocation:
            "Waiting for your location to load. You can also choose a weather condition manually."
        case .locationPermissionRequired:
            "Allow location access in System Settings, or choose a weather condition manually."
        case .forecastUnavailable:
            "Weather data is unavailable right now. Your current wallpaper stays in place."
        }
    }
}

@MainActor
final class WeatherContextProvider {
    private var cachedSnapshot: WeatherSnapshot?
    private var hourlyForecast: [HourlyWeatherForecast] = []
    private var cachedCoordinates: String?
    private var nextFetchAt: Date = .distantPast
    private var lastModified: String?
    private let fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
        try await URLSession.shared.data(for: request)
    }) {
        self.fetch = fetch
    }

    func cachedWeather(at date: Date, now: Date = .now) -> WeatherSnapshot? {
        guard let current = currentSnapshot(at: now) else { return nil }
        return HourlyWeatherForecast.select(date: date, now: now, current: current, forecast: hourlyForecast)
    }

    func weather(at date: Date, location: CLLocation, now: Date = .now) async throws -> WeatherSnapshot {
        let current = try await current(at: location, now: now)
        return HourlyWeatherForecast.select(date: date, now: now, current: current, forecast: hourlyForecast)
    }

    func current(at location: CLLocation, now: Date = .now) async throws -> WeatherSnapshot {
        let latitude = Self.coordinate(location.coordinate.latitude)
        let longitude = Self.coordinate(location.coordinate.longitude)
        let coordinates = "\(latitude),\(longitude)"

        if coordinates == cachedCoordinates,
           let current = currentSnapshot(at: now),
           now < nextFetchAt {
            return current
        }

        guard var components = URLComponents(string: "https://api.met.no/weatherapi/locationforecast/2.0/compact") else {
            throw WeatherContextError.forecastUnavailable
        }
        components.queryItems = [
            URLQueryItem(name: "lat", value: latitude),
            URLQueryItem(name: "lon", value: longitude),
        ]
        guard let url = components.url else { throw WeatherContextError.forecastUnavailable }

        var request = URLRequest(url: url)
        request.setValue("Daydreaming/0.1 (+https://freek.dev)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if coordinates == cachedCoordinates, let lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await fetch(request)
        } catch {
            if let fallback = recentSnapshot(for: coordinates, now: now) { return fallback }
            throw WeatherContextError.forecastUnavailable
        }
        guard let response = response as? HTTPURLResponse else {
            throw WeatherContextError.forecastUnavailable
        }

        if response.statusCode == 304, coordinates == cachedCoordinates, let current = currentSnapshot(at: now) {
            nextFetchAt = max(now.addingTimeInterval(900), Self.expiry(from: response) ?? .distantPast)
            return current
        }
        if !(200..<300).contains(response.statusCode),
           let fallback = recentSnapshot(for: coordinates, now: now) {
            return fallback
        }
        guard (200..<300).contains(response.statusCode),
              let forecast = try? JSONDecoder().decode(ForecastResponse.self, from: data),
              let symbolCode = forecast.properties.timeseries.first?.data.nextHour?.summary.symbolCode else {
            throw WeatherContextError.forecastUnavailable
        }

        let label = Self.label(for: symbolCode)
        let snapshot = WeatherSnapshot(label: label, symbol: Self.symbol(for: label), fetchedAt: now)
        hourlyForecast = forecast.properties.timeseries.compactMap { step in
            guard let date = ISO8601DateFormatter().date(from: step.time), let code = step.data.nextHour?.summary.symbolCode else { return nil }
            let label = Self.label(for: code)
            return HourlyWeatherForecast(date: date, weather: WeatherSnapshot(label: label, symbol: Self.symbol(for: label), fetchedAt: now))
        }
        cachedSnapshot = snapshot
        cachedCoordinates = coordinates
        nextFetchAt = max(now.addingTimeInterval(900), Self.expiry(from: response) ?? .distantPast)
        lastModified = response.value(forHTTPHeaderField: "Last-Modified")
        return currentSnapshot(at: now) ?? snapshot
    }

    private func currentSnapshot(at date: Date) -> WeatherSnapshot? {
        hourlyForecast.last(where: { $0.date <= date })?.weather ?? cachedSnapshot
    }

    nonisolated static func label(for code: String) -> String {
        let code = code.lowercased()
        if code.contains("thunder") { return "stormy" }
        if code.contains("snow") || code.contains("sleet") { return "snowy" }
        if code.contains("rain") || code.contains("drizzle") { return "rainy" }
        if code.contains("fog") { return "foggy" }
        if code.hasPrefix("fair") { return "mostly clear" }
        if code.hasPrefix("partlycloudy") { return "partly cloudy" }
        if code.contains("cloud") { return "cloudy" }
        return "clear"
    }

    nonisolated private static func symbol(for label: String) -> String {
        switch label {
        case "stormy": "cloud.bolt.rain"
        case "snowy": "cloud.snow"
        case "rainy": "cloud.rain"
        case "foggy": "cloud.fog"
        case "cloudy": "cloud"
        case "mostly clear", "partly cloudy": "cloud.sun"
        default: "sun.max"
        }
    }

    private static func coordinate(_ value: CLLocationDegrees) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func recentSnapshot(for coordinates: String, now: Date) -> WeatherSnapshot? {
        guard coordinates == cachedCoordinates,
              let current = currentSnapshot(at: now),
              now.timeIntervalSince(current.fetchedAt) < 7_200 else {
            return nil
        }
        nextFetchAt = now.addingTimeInterval(300)
        return current
    }

    private static func expiry(from response: HTTPURLResponse) -> Date? {
        guard let value = response.value(forHTTPHeaderField: "Expires") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }
}

private struct ForecastResponse: Decodable {
    struct Properties: Decodable {
        struct TimeStep: Decodable {
            struct DataPoint: Decodable {
                struct Period: Decodable {
                    struct Summary: Decodable {
                        let symbolCode: String
                        enum CodingKeys: String, CodingKey { case symbolCode = "symbol_code" }
                    }
                    let summary: Summary
                }
                let nextHour: Period?
                enum CodingKeys: String, CodingKey { case nextHour = "next_1_hours" }
            }
            let time: String
            let data: DataPoint
        }
        let timeseries: [TimeStep]
    }
    let properties: Properties
}


struct HourlyWeatherForecast: Equatable, Sendable {
    let date: Date
    let weather: WeatherSnapshot

    static func select(date: Date, now: Date, current: WeatherSnapshot, forecast: [Self], calendar: Calendar = .current) -> WeatherSnapshot {
        let hour = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        let currentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        guard hour > currentHour, calendar.isDate(date, inSameDayAs: now) else { return current }
        return forecast.first { calendar.isDate($0.date, equalTo: date, toGranularity: .hour) }?.weather ?? current
    }
}
