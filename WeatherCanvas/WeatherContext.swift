import CoreLocation
import Foundation
import MapKit
import WeatherKit

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
    static let maximumFallbackAge: TimeInterval = 24 * 60 * 60

    static func isUsable(_ location: CLLocation, now: Date = .now) -> Bool {
        CLLocationCoordinate2DIsValid(location.coordinate)
            && location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= 10_000
            && now.timeIntervalSince(location.timestamp) >= -60
            && now.timeIntervalSince(location.timestamp) < maximumFallbackAge
    }

    static func isFresh(_ location: CLLocation, now: Date = .now) -> Bool {
        isUsable(location, now: now) && now.timeIntervalSince(location.timestamp) < 900
    }
}

@MainActor
final class LocationReader: NSObject, @preconcurrency CLLocationManagerDelegate {
    private struct SavedLocation: Codable {
        let latitude: Double
        let longitude: Double
        let horizontalAccuracy: Double
        let timestamp: Date

        init(_ location: CLLocation) {
            latitude = location.coordinate.latitude
            longitude = location.coordinate.longitude
            horizontalAccuracy = location.horizontalAccuracy
            timestamp = location.timestamp
        }

        var location: CLLocation {
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), altitude: 0,
                       horizontalAccuracy: horizontalAccuracy, verticalAccuracy: -1, timestamp: timestamp)
        }
    }

    private static let savedLocationKey = "lastWeatherLocation"
    private let manager = CLLocationManager()
    private let defaults: UserDefaults
    private(set) var location: CLLocation?
    var onLocation: (() -> Void)?
    private var hasRequested = false
    private var nextRequestAt = Date.distantPast
    private var nameRequest: MKReverseGeocodingRequest?
    private(set) var placeName: String?
    var onPlaceName: (() -> Void)?
    var freshLocation: CLLocation? {
        location.flatMap { LocalWeatherLocationPolicy.isFresh($0) ? $0 : nil }
    }
    var usableLocation: CLLocation? {
        guard authorizationStatus == .authorized || authorizationStatus == .authorizedAlways else { return nil }
        return location.flatMap { LocalWeatherLocationPolicy.isUsable($0) ? $0 : nil }
    }
    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.savedLocationKey),
           let saved = try? JSONDecoder().decode(SavedLocation.self, from: data),
           LocalWeatherLocationPolicy.isUsable(saved.location) {
            location = saved.location
        }
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func request(force: Bool = false) {
        guard force || Date() >= nextRequestAt else { return }
        guard force || freshLocation == nil else { return }
        hasRequested = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways:
            nextRequestAt = Date().addingTimeInterval(30)
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if hasRequested && (manager.authorizationStatus == .authorized || manager.authorizationStatus == .authorizedAlways) {
            nextRequestAt = Date().addingTimeInterval(30)
            manager.requestLocation()
        } else {
            if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                manager.stopUpdatingLocation()
                location = nil
                defaults.removeObject(forKey: Self.savedLocationKey)
                nameRequest?.cancel()
                nameRequest = nil
                placeName = nil
                onPlaceName?()
            }
            onLocation?()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last(where: { LocalWeatherLocationPolicy.isFresh($0) })
                ?? locations.last(where: { LocalWeatherLocationPolicy.isUsable($0) }) else {
            onLocation?()
            return
        }
        let previous = location
        if let previous, latest.timestamp <= previous.timestamp { onLocation?(); return }
        location = latest
        if let data = try? JSONEncoder().encode(SavedLocation(latest)) {
            defaults.set(data, forKey: Self.savedLocationKey)
        }
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
            "Waiting for your location. You can also choose a fixed weather location."
        case .locationPermissionRequired:
            "Allow location access in System Settings, or choose a fixed weather location."
        case .forecastUnavailable:
            "Weather data is unavailable right now. Your current wallpaper stays in place."
        }
    }
}

struct AppleWeatherReport: Sendable {
    let current: WeatherSnapshot
    let hourly: [HourlyWeatherForecast]
    let attribution: WeatherAttribution?

    init(current: WeatherSnapshot, hourly: [HourlyWeatherForecast], attribution: WeatherAttribution? = nil) {
        self.current = current
        self.hourly = hourly
        self.attribution = attribution
    }
}

@MainActor
final class AppleWeatherProvider {
    typealias Fetch = @Sendable (CLLocation, Date) async throws -> AppleWeatherReport

    private let fetch: Fetch
    private var report: AppleWeatherReport?
    private(set) var attribution: WeatherAttribution?
    private var cachedCoordinates: String?
    private var nextFetchAt = Date.distantPast
    private var retryAfter = Date.distantPast

    init(fetch: @escaping Fetch = { location, now in
        let (current, forecast) = try await WeatherService.shared.weather(for: location, including: .current, .hourly)
        let currentSnapshot = WeatherSnapshot(label: current.condition.description, symbol: current.symbolName,
                                              fetchedAt: now, details: WeatherVisualDetails(current: current), source: .apple)
        let hours = forecast.map { hour in
            HourlyWeatherForecast(date: hour.date,
                weather: WeatherSnapshot(label: hour.condition.description, symbol: hour.symbolName, fetchedAt: now,
                                         details: WeatherVisualDetails(hour: hour), source: .apple))
        }
        let attribution = try await WeatherService.shared.attribution
        return AppleWeatherReport(current: currentSnapshot, hourly: hours, attribution: attribution)
    }) {
        self.fetch = fetch
    }

    func cachedWeather(at date: Date, now: Date = .now, location: CLLocation? = nil) -> WeatherSnapshot? {
        if let location, cachedCoordinates != Self.coordinates(for: location) { return nil }
        guard let report, now < nextFetchAt else { return nil }
        return HourlyWeatherForecast.select(date: date, now: now, current: report.current, forecast: report.hourly)
    }

    func weather(at date: Date, location: CLLocation, now: Date = .now) async throws -> WeatherSnapshot {
        let coordinates = Self.coordinates(for: location)
        if coordinates != cachedCoordinates {
            report = nil
            attribution = nil
            cachedCoordinates = coordinates
            nextFetchAt = .distantPast
            retryAfter = .distantPast
        }
        if now >= nextFetchAt || report == nil {
            if report == nil && now < retryAfter { throw WeatherContextError.forecastUnavailable }
            do {
                report = try await fetch(location, now)
                attribution = report?.attribution
                cachedCoordinates = coordinates
                nextFetchAt = min(now.addingTimeInterval(900), Calendar.current.dateInterval(of: .hour, for: now)?.end ?? .distantFuture)
                retryAfter = .distantPast
            } catch {
                retryAfter = now.addingTimeInterval(300)
                guard coordinates == cachedCoordinates, let report,
                      Calendar.current.isDate(report.current.fetchedAt, equalTo: now, toGranularity: .hour),
                      now.timeIntervalSince(report.current.fetchedAt) < 7_200 else { throw error }
                nextFetchAt = now.addingTimeInterval(300)
                return HourlyWeatherForecast.select(date: date, now: now, current: report.current, forecast: report.hourly)
            }
        }
        guard let report else { throw WeatherContextError.forecastUnavailable }
        return HourlyWeatherForecast.select(date: date, now: now, current: report.current, forecast: report.hourly)
    }

    private nonisolated static func coordinates(for location: CLLocation) -> String {
        String(format: "%.2f,%.2f", locale: Locale(identifier: "en_US_POSIX"),
               location.coordinate.latitude, location.coordinate.longitude)
    }
}

private extension WeatherVisualDetails {
    init(current: CurrentWeather) {
        self.init(temperatureCelsius: Self.celsius(current.temperature),
                  apparentTemperatureCelsius: Self.celsius(current.apparentTemperature),
                  dewPointCelsius: Self.celsius(current.dewPoint),
                  cloudCoverPercent: Self.percent(current.cloudCover),
                  lowCloudPercent: Self.percent(current.cloudCoverByAltitude.low),
                  mediumCloudPercent: Self.percent(current.cloudCoverByAltitude.medium),
                  highCloudPercent: Self.percent(current.cloudCoverByAltitude.high),
                  humidityPercent: Self.percent(current.humidity),
                  precipitationType: nil,
                  precipitationChancePercent: nil, precipitationAmountMillimeters: nil,
                  precipitationIntensityMillimetersPerHour: current.precipitationIntensity.converted(to: .metersPerSecond).value * 3_600_000,
                  windSpeedKilometersPerHour: Self.speed(current.wind.speed),
                  windGustKilometersPerHour: current.wind.gust.map(Self.speed),
                  windDirection: current.wind.compassDirection.description,
                  visibilityKilometers: current.visibility.converted(to: .kilometers).value,
                  pressureMillibars: Int(current.pressure.converted(to: .millibars).value.rounded()),
                  pressureTrend: current.pressureTrend.description,
                  uvIndex: current.uvIndex.value, isDaylight: current.isDaylight)
    }

    init(hour: HourWeather) {
        self.init(temperatureCelsius: Self.celsius(hour.temperature),
                  apparentTemperatureCelsius: Self.celsius(hour.apparentTemperature),
                  dewPointCelsius: Self.celsius(hour.dewPoint),
                  cloudCoverPercent: Self.percent(hour.cloudCover),
                  lowCloudPercent: Self.percent(hour.cloudCoverByAltitude.low),
                  mediumCloudPercent: Self.percent(hour.cloudCoverByAltitude.medium),
                  highCloudPercent: Self.percent(hour.cloudCoverByAltitude.high),
                  humidityPercent: Self.percent(hour.humidity),
                  precipitationType: hour.precipitation.description,
                  precipitationChancePercent: Self.percent(hour.precipitationChance),
                  precipitationAmountMillimeters: hour.precipitationAmount.converted(to: .millimeters).value,
                  precipitationIntensityMillimetersPerHour: nil,
                  windSpeedKilometersPerHour: Self.speed(hour.wind.speed),
                  windGustKilometersPerHour: hour.wind.gust.map(Self.speed),
                  windDirection: hour.wind.compassDirection.description,
                  visibilityKilometers: hour.visibility.converted(to: .kilometers).value,
                  pressureMillibars: Int(hour.pressure.converted(to: .millibars).value.rounded()),
                  pressureTrend: hour.pressureTrend.description,
                  uvIndex: hour.uvIndex.value, isDaylight: hour.isDaylight)
    }

    static func celsius(_ value: Measurement<UnitTemperature>) -> Int { Int(value.converted(to: .celsius).value.rounded()) }
    static func speed(_ value: Measurement<UnitSpeed>) -> Int { Int(value.converted(to: .kilometersPerHour).value.rounded()) }
    static func percent(_ value: Double) -> Int { Int((value * 100).rounded()).clamped(to: 0...100) }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int { Swift.min(range.upperBound, Swift.max(range.lowerBound, self)) }
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

    func cachedWeather(at date: Date, now: Date = .now, location: CLLocation? = nil) -> WeatherSnapshot? {
        if let location, cachedCoordinates != "\(Self.coordinate(location.coordinate.latitude)),\(Self.coordinate(location.coordinate.longitude))" { return nil }
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
              let first = forecast.properties.timeseries.first,
              first.data.nextHour?.summary.symbolCode != nil else {
            throw WeatherContextError.forecastUnavailable
        }

        let label = Self.label(for: first)
        let snapshot = WeatherSnapshot(label: label, symbol: Self.symbol(for: label), fetchedAt: now)
        hourlyForecast = forecast.properties.timeseries.compactMap { step in
            guard let date = ISO8601DateFormatter().date(from: step.time), step.data.nextHour?.summary.symbolCode != nil else { return nil }
            let label = Self.label(for: step)
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

    private nonisolated static func label(for step: ForecastResponse.Properties.TimeStep) -> String {
        guard let period = step.data.nextHour else { return "clear" }
        let code = period.summary.symbolCode.lowercased()
        if code.contains("rainshowers"), !code.contains("thunder"),
           let amount = period.details?.precipitationAmount, (0..<0.5).contains(amount),
           let cloudCover = step.data.instant?.details.cloudAreaFraction, (0...100).contains(cloudCover) {
            if cloudCover < 25 { return "mostly clear" }
            if cloudCover < 75 { return "partly cloudy" }
            return "cloudy"
        }
        return label(for: code)
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
                struct Instant: Decodable {
                    struct Details: Decodable {
                        let cloudAreaFraction: Double?
                        enum CodingKeys: String, CodingKey { case cloudAreaFraction = "cloud_area_fraction" }
                    }
                    let details: Details
                }
                struct Period: Decodable {
                    struct Summary: Decodable {
                        let symbolCode: String
                        enum CodingKeys: String, CodingKey { case symbolCode = "symbol_code" }
                    }
                    struct Details: Decodable {
                        let precipitationAmount: Double?
                        enum CodingKeys: String, CodingKey { case precipitationAmount = "precipitation_amount" }
                    }
                    let summary: Summary
                    let details: Details?
                }
                let instant: Instant?
                let nextHour: Period?
                enum CodingKeys: String, CodingKey { case instant, nextHour = "next_1_hours" }
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

@MainActor
enum WeatherPlaceLookup {
    static func search(_ query: String) async throws -> [WeatherPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        request.resultTypes = .address
        let response = try await MKLocalSearch(request: request).start()
        try Task.checkCancellation()
        var seen = Set<String>()
        return response.mapItems.compactMap { item in
            let place = WeatherPlace(name: item.addressRepresentations?.cityWithContext(.full) ?? item.name ?? query,
                                     latitude: item.location.coordinate.latitude, longitude: item.location.coordinate.longitude)
            return place.isValid && seen.insert(place.id).inserted ? place : nil
        }
    }

    static func named(_ place: WeatherPlace) async -> WeatherPlace {
        // Resolve the same approximate place used for the saved fixed location.
        let location = CLLocation(latitude: (place.latitude * 100).rounded() / 100,
                                  longitude: (place.longitude * 100).rounded() / 100)
        guard let request = MKReverseGeocodingRequest(location: location),
              let items = try? await request.mapItems,
              let name = items.first?.addressRepresentations?.cityWithContext(.full) else { return place }
        return WeatherPlace(name: name, latitude: place.latitude, longitude: place.longitude)
    }
}

extension WeatherLocationSelection {
    func resolve(current: CLLocation?) throws -> CLLocation {
        if let place = fixedPlace, place.isValid {
            return CLLocation(latitude: place.latitude, longitude: place.longitude)
        }
        guard self == .current, let current, LocalWeatherLocationPolicy.isUsable(current) else {
            throw WeatherContextError.waitingForLocation
        }
        return current
    }
}
