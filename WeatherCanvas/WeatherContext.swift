import CoreLocation
import Foundation

@MainActor
final class LocationReader: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var location: CLLocation?
    var onLocation: (() -> Void)?
    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorized || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        } else {
            onLocation?()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        location = latest
        onLocation?()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
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
    private var cachedCoordinates: String?
    private var nextFetchAt: Date = .distantPast
    private var lastModified: String?

    func current(at location: CLLocation) async throws -> WeatherSnapshot {
        let latitude = Self.coordinate(location.coordinate.latitude)
        let longitude = Self.coordinate(location.coordinate.longitude)
        let coordinates = "\(latitude),\(longitude)"

        if coordinates == cachedCoordinates,
           let cachedSnapshot,
           Date() < nextFetchAt {
            return cachedSnapshot
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
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if let fallback = recentSnapshot(for: coordinates) { return fallback }
            throw WeatherContextError.forecastUnavailable
        }
        guard let response = response as? HTTPURLResponse else {
            throw WeatherContextError.forecastUnavailable
        }

        if response.statusCode == 304, let cachedSnapshot {
            nextFetchAt = max(Date().addingTimeInterval(900), Self.expiry(from: response) ?? .distantPast)
            return cachedSnapshot
        }
        if !(200..<300).contains(response.statusCode),
           let fallback = recentSnapshot(for: coordinates) {
            return fallback
        }
        guard (200..<300).contains(response.statusCode),
              let forecast = try? JSONDecoder().decode(ForecastResponse.self, from: data),
              let symbolCode = forecast.properties.timeseries.first?.data.nextHour?.summary.symbolCode else {
            throw WeatherContextError.forecastUnavailable
        }

        let label = Self.label(for: symbolCode)
        let snapshot = WeatherSnapshot(label: label, symbol: Self.symbol(for: label), fetchedAt: .now)
        cachedSnapshot = snapshot
        cachedCoordinates = coordinates
        nextFetchAt = max(Date().addingTimeInterval(900), Self.expiry(from: response) ?? .distantPast)
        lastModified = response.value(forHTTPHeaderField: "Last-Modified")
        return snapshot
    }

    static func label(for code: String) -> String {
        let code = code.lowercased()
        if code.contains("thunder") { return "stormy" }
        if code.contains("snow") || code.contains("sleet") { return "snowy" }
        if code.contains("rain") || code.contains("drizzle") { return "rainy" }
        if code.contains("fog") { return "foggy" }
        if code.contains("cloud") { return "cloudy" }
        return "clear"
    }

    private static func symbol(for label: String) -> String {
        switch label {
        case "stormy": "cloud.bolt.rain"
        case "snowy": "cloud.snow"
        case "rainy": "cloud.rain"
        case "foggy": "cloud.fog"
        case "cloudy": "cloud"
        default: "sun.max"
        }
    }

    private static func coordinate(_ value: CLLocationDegrees) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func recentSnapshot(for coordinates: String) -> WeatherSnapshot? {
        guard coordinates == cachedCoordinates,
              let cachedSnapshot,
              Date().timeIntervalSince(cachedSnapshot.fetchedAt) < 7_200 else {
            return nil
        }
        nextFetchAt = Date().addingTimeInterval(300)
        return cachedSnapshot
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
            let data: DataPoint
        }
        let timeseries: [TimeStep]
    }
    let properties: Properties
}
