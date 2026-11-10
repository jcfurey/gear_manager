//
//  WeatherKitCloudProvider.swift
//  ShutterManager
//
//  Apple Weather, through WeatherKit: the only place the app asks for weather.
//

import CoreLocation
import Foundation
import WeatherKit

/// The cloud forecast from Apple Weather.
///
/// The app needs the WeatherKit capability on its App ID and the
/// `com.apple.developer.weatherkit` entitlement; without them every request fails, which the
/// screens show as a forecast that couldn't be loaded. Each request counts against the
/// developer account's monthly allowance, so `CloudForecastStore` asks once per place an hour.
///
/// Apple's terms: the forecast is shown with the Apple Weather mark and its legal link
/// (`WeatherAttributionRow`), and isn't kept beyond the session.
struct WeatherKitCloudProvider: CloudForecastProviding {
    func hours(at point: GeoCoordinate, in range: DateInterval) async throws -> [CloudHour] {
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let hourly: Forecast<HourWeather> = try await WeatherService.shared.weather(
            for: location, including: .hourly(startDate: range.start, endDate: range.end))
        return hourly.forecast.map { hour in
            let layers = hour.cloudCoverByAltitude
            return CloudHour(start: hour.date, cover: hour.cloudCover, low: layers.low, medium: layers.medium,
                             high: layers.high, precipitationChance: hour.precipitationChance,
                             condition: hour.condition.description, symbolName: hour.symbolName)
        }
    }

    func attribution() async throws -> CloudAttribution {
        let credit = try await WeatherService.shared.attribution
        return CloudAttribution(legalPage: credit.legalPageURL, lightMark: credit.combinedMarkLightURL,
                                darkMark: credit.combinedMarkDarkURL)
    }
}
