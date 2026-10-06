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
