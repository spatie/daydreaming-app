import CoreLocation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Daydreaming

final class HourlyWeatherForecastTests: XCTestCase {
    func testFutureHourTodayUsesMatchingForecastRatherThanCurrentWeather() throws {
        let calendar = utcCalendar()
        let now = try date(day: 5, hour: 10, minute: 25, calendar: calendar)
        let requested = try date(day: 5, hour: 17, minute: 45, calendar: calendar)
        let current = snapshot("clear", at: now)
        let rainy = snapshot("rainy", at: now)
        let forecast = [
            HourlyWeatherForecast(date: try date(day: 5, hour: 16, calendar: calendar), weather: snapshot("cloudy", at: now)),
            HourlyWeatherForecast(date: try date(day: 5, hour: 17, calendar: calendar), weather: rainy),
        ]

        XCTAssertEqual(HourlyWeatherForecast.select(date: requested, now: now, current: current, forecast: forecast, calendar: calendar), rainy)
    }

    func testPastAndCurrentHoursUseCurrentWeatherEvenWithForecastEntries() throws {
        let calendar = utcCalendar()
        let now = try date(day: 5, hour: 10, minute: 25, calendar: calendar)
        let current = snapshot("clear", at: now)
        let outdated = snapshot("rainy", at: now)
        let forecast = [
            HourlyWeatherForecast(date: try date(day: 5, hour: 8, calendar: calendar), weather: outdated),
            HourlyWeatherForecast(date: try date(day: 5, hour: 10, calendar: calendar), weather: outdated),
        ]
        for requested in [
            try date(day: 5, hour: 8, calendar: calendar),
            try date(day: 5, hour: 10, minute: 59, calendar: calendar),
        ] {
            XCTAssertEqual(HourlyWeatherForecast.select(date: requested, now: now, current: current, forecast: forecast, calendar: calendar), current)
        }
    }

    func testTomorrowAndMissingFutureHourFallBackToCurrentWeather() throws {
        let calendar = utcCalendar()
        let now = try date(day: 5, hour: 10, calendar: calendar)
        let tomorrow = try date(day: 6, hour: 14, calendar: calendar)
        let missingToday = try date(day: 5, hour: 18, calendar: calendar)
        let current = snapshot("clear", at: now)
        let forecast = [HourlyWeatherForecast(date: tomorrow, weather: snapshot("snowy", at: now))]

        XCTAssertEqual(HourlyWeatherForecast.select(date: tomorrow, now: now, current: current, forecast: forecast, calendar: calendar), current)
        XCTAssertEqual(HourlyWeatherForecast.select(date: missingToday, now: now, current: current, forecast: forecast, calendar: calendar), current)
    }

    func testFutureHourUsesLocalCalendarDayAcrossUTCMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: -7 * 3_600))
        let now = try date(day: 5, hour: 16, calendar: calendar)
        let requested = try date(day: 5, hour: 18, calendar: calendar)
        let current = snapshot("clear", at: now)
        let predicted = snapshot("rainy", at: now)
        let forecast = [HourlyWeatherForecast(date: requested, weather: predicted)]

        XCTAssertEqual(HourlyWeatherForecast.select(date: requested, now: now, current: current, forecast: forecast, calendar: calendar), predicted)
    }

    func testFairAndPartlyCloudyAreNotOvercast() {
        XCTAssertEqual(WeatherContextProvider.label(for: "clearsky_day"), "clear")
        XCTAssertEqual(WeatherContextProvider.label(for: "fair_day"), "mostly clear")
        XCTAssertEqual(WeatherContextProvider.label(for: "fair_night"), "mostly clear")
        XCTAssertEqual(WeatherContextProvider.label(for: "partlycloudy_day"), "partly cloudy")
        XCTAssertEqual(WeatherContextProvider.label(for: "cloudy"), "cloudy")
        XCTAssertEqual(WeatherContextProvider.label(for: "lightrainshowers_day"), "rainy")
        XCTAssertEqual(WeatherContextProvider.label(for: "snowshowers_night"), "snowy")
    }

    func testLocationMustBeRecentAndHaveValidAccuracy() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func location(age: TimeInterval, accuracy: Double = 1_000) -> CLLocation {
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: 50, longitude: 4), altitude: 0,
                       horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: now.addingTimeInterval(-age))
        }
        XCTAssertTrue(LocalWeatherLocationPolicy.isFresh(location(age: 899), now: now))
        XCTAssertFalse(LocalWeatherLocationPolicy.isFresh(location(age: 900), now: now))
        XCTAssertFalse(LocalWeatherLocationPolicy.isFresh(location(age: 0, accuracy: -1), now: now))
        XCTAssertFalse(LocalWeatherLocationPolicy.isFresh(location(age: 0, accuracy: 50_000), now: now))
        XCTAssertFalse(LocalWeatherLocationPolicy.isFresh(location(age: -120), now: now))
    }

    @MainActor
    func testCurrentWeatherUsesPresentHourAndAdvancesInsideCachedResponse() async throws {
        let calendar = utcCalendar()
        let now = try date(day: 5, hour: 11, minute: 55, calendar: calendar)
        let spy = ForecastTransportSpy()
        let provider = WeatherContextProvider { request in try await spy.fetch(request) }
        let location = CLLocation(latitude: 50, longitude: 4)
        let first = try await provider.current(at: location, now: now)
        XCTAssertEqual(first.label, "mostly clear")
        let later = now.addingTimeInterval(600)
        let current = try await provider.current(at: location, now: later)
        XCTAssertEqual(current.label, "partly cloudy")
        XCTAssertEqual(current.fetchedAt, now)
        XCTAssertEqual(provider.cachedWeather(at: later, now: later)?.label, "partly cloudy")
        let calls = await spy.calls
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testNotModifiedAndOfflineFallbackStillUsePresentHour() async throws {
        let calendar = utcCalendar()
        let now = try date(day: 5, hour: 11, minute: 55, calendar: calendar)
        let spy = ForecastTransportSpy()
        let provider = WeatherContextProvider { request in try await spy.fetch(request) }
        let location = CLLocation(latitude: 50, longitude: 4)
        _ = try await provider.current(at: location, now: now)
        await spy.setStatus(304)
        let refreshed = try await provider.current(at: location, now: now.addingTimeInterval(1_000))
        XCTAssertEqual(refreshed.label, "partly cloudy")
        await spy.setStatus(503)
        let fallback = try await provider.current(at: location, now: now.addingTimeInterval(2_000))
        XCTAssertEqual(fallback.label, "partly cloudy")
        let calls = await spy.calls
        XCTAssertEqual(calls, 3)
    }

    @MainActor
    func testChangingLocationBypassesCachedForecast() async throws {
        let calendar = utcCalendar()
        let now = try date(day: 5, hour: 11, minute: 55, calendar: calendar)
        let spy = ForecastTransportSpy()
        let provider = WeatherContextProvider { request in try await spy.fetch(request) }
        _ = try await provider.current(at: CLLocation(latitude: 50, longitude: 4), now: now)
        _ = try await provider.current(at: CLLocation(latitude: 51, longitude: 5), now: now.addingTimeInterval(1))
        let calls = await spy.calls
        XCTAssertEqual(calls, 2)
        let requests = await spy.requests
        XCTAssertTrue(requests[1].url?.query?.contains("lat=51.00") == true)
        XCTAssertNil(provider.cachedWeather(at: now, now: now, location: CLLocation(latitude: 50, longitude: 4)))
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "If-Modified-Since"))
    }

    func testFixedLocationWorksWithoutCurrentLocationAndSurvivesSettingsRoundTrip() throws {
        let place = WeatherPlace(name: "Example town", latitude: 40, longitude: -70)
        var settings = CanvasSettings()
        settings.weatherLocation = .fixed(place)
        settings.promptTemplate = "Keep my custom idea"
        let restored = try JSONDecoder().decode(CanvasSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.weatherLocation, .fixed(place))
        XCTAssertEqual(restored.promptTemplate, "Keep my custom idea")
        let resolved = try restored.weatherLocation.resolve(current: nil)
        XCTAssertEqual(resolved.coordinate.latitude, 40)
        XCTAssertEqual(resolved.coordinate.longitude, -70)
        XCTAssertThrowsError(try WeatherLocationSelection.current.resolve(current: nil))
    }

    func testOldAndInvalidLocationSettingsPreserveTheIdeaAndUseCurrentLocation() throws {
        XCTAssertEqual(try JSONDecoder().decode(CanvasSettings.self, from: Data("{}".utf8)).weatherLocation, .current)
        var settings = CanvasSettings()
        settings.promptTemplate = "Keep my custom idea"
        settings.weatherLocation = .fixed(WeatherPlace(name: "Invalid", latitude: 91, longitude: 0))
        let restored = try JSONDecoder().decode(CanvasSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.weatherLocation, .current)
        XCTAssertEqual(restored.promptTemplate, "Keep my custom idea")
    }

    func testFixedLocationSeparatesCacheKeysAndCurrentLocationKeepsLegacyKey() {
        var settings = CanvasSettings()
        settings.sourceDigest = "fixture-picture"
        let legacyKey = "fa2153885fdb6ba71993daf2388e42be63ad9c3b5a049685da037eb57c639e44"
        XCTAssertEqual(HourWallpaperCache.recipeID(for: settings), legacyKey)
        settings.weatherLocation = .fixed(WeatherPlace(name: "First place", latitude: 40, longitude: -70))
        let first = HourWallpaperCache.recipeID(for: settings)
        XCTAssertNotEqual(first, legacyKey)
        settings.weatherLocation = .fixed(WeatherPlace(name: "Second place", latitude: 45, longitude: -75))
        XCTAssertNotEqual(HourWallpaperCache.recipeID(for: settings), first)
        settings.weatherLocation = .current
        XCTAssertEqual(HourWallpaperCache.recipeID(for: settings), legacyKey)
    }

    func testPhotoGPSHandlesHemispheresAndRejectsMissingOrInvalidCoordinates() throws {
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 40.0, kCGImagePropertyGPSLongitude: 70.0,
                                  kCGImagePropertyGPSLatitudeRef: "S", kCGImagePropertyGPSLongitudeRef: "W"]
        let place = try XCTUnwrap(ImageStore.pictureLocation(gps: gps))
        XCTAssertEqual(place.latitude, -40)
        XCTAssertEqual(place.longitude, -70)
        XCTAssertNil(ImageStore.pictureLocation(gps: [:]))
        var invalid = gps
        invalid[kCGImagePropertyGPSLatitude] = 91
        XCTAssertNil(ImageStore.pictureLocation(gps: invalid))
        invalid = gps
        invalid.removeValue(forKey: kCGImagePropertyGPSLongitudeRef)
        XCTAssertNil(ImageStore.pictureLocation(gps: invalid))
    }

    func testPhotoLocationReadsActualOriginalMetadata() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 40.0, kCGImagePropertyGPSLongitude: 70.0,
                                  kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitudeRef: "E"]
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyGPSDictionary: gps] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertEqual(ImageStore.pictureLocation(at: url)?.latitude, 40)
        XCTAssertEqual(ImageStore.pictureLocation(at: url)?.longitude, 70)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(day: Int, hour: Int, minute: Int = 0, calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)))
    }

    private func snapshot(_ label: String, at date: Date) -> WeatherSnapshot {
        WeatherSnapshot(label: label, symbol: "cloud", fetchedAt: date)
    }
}

private actor ForecastTransportSpy {
    private(set) var calls = 0
    private(set) var requests: [URLRequest] = []
    private var status = 200
    func setStatus(_ value: Int) { status = value }
    func fetch(_ request: URLRequest) throws -> (Data, URLResponse) {
        calls += 1
        requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Last-Modified": "Mon, 05 Oct 2026 10:00:00 GMT"])!
        let data = Data("""
        {"properties":{"timeseries":[
          {"time":"2026-10-05T10:00:00Z","data":{"next_1_hours":{"summary":{"symbol_code":"cloudy"}}}},
          {"time":"2026-10-05T11:00:00Z","data":{"next_1_hours":{"summary":{"symbol_code":"fair_day"}}}},
          {"time":"2026-10-05T12:00:00Z","data":{"next_1_hours":{"summary":{"symbol_code":"partlycloudy_day"}}}}
        ]}}
        """.utf8)
        return (data, response)
    }
}
