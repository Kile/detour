import Foundation

/// Current weather and light, for photo challenges. Only a short description reaches the AI.
struct WeatherSnapshot: Codable, Equatable, Sendable {
    var temperatureC: Double
    /// WMO weather code.
    var weatherCode: Int
    var precipitationMM: Double
    var cloudCover: Int
    var windKmh: Double
    var isDay: Bool
    /// Local times like "07:18".
    var sunrise: String?
    var sunset: String?
    /// Local time of the reading, "HH:mm".
    var observedAt: String?

    var condition: String {
        switch weatherCode {
        case 0: return "clear sky"
        case 1: return "mainly clear"
        case 2: return "partly cloudy"
        case 3: return "overcast"
        case 45, 48: return "fog"
        case 51, 53, 55: return "drizzle"
        case 56, 57: return "freezing drizzle"
        case 61: return "light rain"
        case 63: return "rain"
        case 65: return "heavy rain"
        case 66, 67: return "freezing rain"
        case 71, 73, 75, 77: return "snow"
        case 80, 81, 82: return "rain showers"
        case 85, 86: return "snow showers"
        case 95: return "thunderstorm"
        case 96, 99: return "thunderstorm with hail"
        default: return "mixed weather"
        }
    }

    var emoji: String {
        switch weatherCode {
        case 0, 1: return isDay ? "☀️" : "🌙"
        case 2: return "⛅️"
        case 3: return "☁️"
        case 45, 48: return "🌫️"
        case 51...67, 80...82: return "🌧️"
        case 71...77, 85, 86: return "🌨️"
        case 95...99: return "⛈️"
        default: return "🌤️"
        }
    }

    var isWet: Bool { (51...67).contains(weatherCode) || (80...82).contains(weatherCode) || precipitationMM > 0.1 }
    var isSunny: Bool { isDay && (weatherCode <= 1 || cloudCover < 40) }
    var isStormy: Bool { weatherCode >= 95 }

    /// Short label for the quest card, e.g. "🌧️ 11° · light rain".
    var label: String { "\(emoji) \(Int(temperatureC.rounded()))° · \(condition)" }

    /// Lines for the AI prompt. No coordinates, only conditions.
    var promptLines: [String] {
        var weather = "WEATHER: \(condition), \(Int(temperatureC.rounded()))°C, wind \(Int(windKmh.rounded())) km/h"
        if isStormy { weather += " (stay indoors or under shelter)" }
        var light = "LIGHT: " + (isDay ? "daylight" : "dark")
        if let sunset, isDay { light += ", sunset at \(sunset)" }
        if goldenHour { light += " (golden hour now: low, warm, long shadows)" }
        if let sunrise, !isDay { light += ", sunrise at \(sunrise)" }
        return [weather, light]
    }

    /// Within the hour before sunset or after sunrise.
    var goldenHour: Bool {
        guard isDay, let now = observedAt.flatMap(Self.minutes), let set = sunset.flatMap(Self.minutes) else { return false }
        let rise = sunrise.flatMap(Self.minutes) ?? -1_000
        return (set - 60...set).contains(now) || (rise...rise + 60).contains(now)
    }

    private static func minutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : nil
    }
}

/// Weather from Open-Meteo (free, no API key, no SDK). Only the player's location rounded to
/// about 1 km is sent, and only when making a photo challenge in Nearby/City.
enum WeatherService {
    static func url(for point: GeoPoint) -> URL {
        // Two decimals ≈ 1.1 km: plenty for weather, vague enough for privacy.
        let lat = String(format: "%.2f", point.latitude)
        let lon = String(format: "%.2f", point.longitude)
        return URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)"
            + "&current=temperature_2m,precipitation,weather_code,cloud_cover,wind_speed_10m,is_day"
            + "&daily=sunrise,sunset&timezone=auto&forecast_days=1")!
    }

    static func fetch(at point: GeoPoint, session: URLSession = .shared) async throws -> WeatherSnapshot {
        var request = URLRequest(url: url(for: point), timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "accept")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> WeatherSnapshot {
        struct Response: Decodable {
            struct Current: Decodable {
                var time: String?
                var temperature_2m: Double
                var precipitation: Double?
                var weather_code: Int
                var cloud_cover: Int?
                var wind_speed_10m: Double?
                var is_day: Int?
            }
            struct Daily: Decodable { var sunrise: [String]?; var sunset: [String]? }
            var current: Current
            var daily: Daily?
        }
        let r = try JSONDecoder().decode(Response.self, from: data)
        func clock(_ iso: String?) -> String? { iso.map { String($0.suffix(5)) } }   // "2026-11-15T16:11" → "16:11"
        return WeatherSnapshot(
            temperatureC: r.current.temperature_2m, weatherCode: r.current.weather_code,
            precipitationMM: r.current.precipitation ?? 0, cloudCover: r.current.cloud_cover ?? 50,
            windKmh: r.current.wind_speed_10m ?? 0, isDay: (r.current.is_day ?? 1) == 1,
            sunrise: clock(r.daily?.sunrise?.first), sunset: clock(r.daily?.sunset?.first),
            observedAt: clock(r.current.time))
    }
}
