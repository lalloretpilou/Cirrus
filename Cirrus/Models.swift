import Foundation
import CoreLocation
import WeatherKit

// MARK: - Weather Models

struct WeatherData: Codable, Identifiable {
    var id = UUID() // Changé en var pour Codable
    let location: Location
    let current: CurrentWeather
    let forecast: [DailyForecast]
    let hourlyForecast: [HourlyForecast]
    let lastUpdated: Date
    let source: WeatherSource
    
    enum WeatherSource: String, Codable {
        case weatherKit = "WeatherKit"
        case weatherAPI = "WeatherAPI"
        case combined = "Combined"
    }
}

struct Location: Codable, Identifiable, Hashable {
    var id = UUID() // Changé en var pour Codable
    let name: String
    let country: String
    let coordinates: Coordinates
    let timezone: String?
    let isFavorite: Bool
    let isPremium: Bool // Indique si cette destination nécessite Premium
    
    struct Coordinates: Codable, Hashable {
        let latitude: Double
        let longitude: Double
        
        var clLocation: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }
}

struct CurrentWeather: Codable {
    let temperature: Double
    let feelsLike: Double
    let condition: WeatherCondition
    let humidity: Int
    let pressure: Double
    let visibility: Double
    let uvIndex: Int
    let windSpeed: Double
    let windDirection: Int
    let cloudCover: Int
    let dewPoint: Double
    let airQuality: AirQuality?
}

struct WeatherCondition: Codable {
    let id: Int
    let main: String
    let description: String
    let icon: String
    
    var emoji: String {
        switch main.lowercased() {
        case "clear": return "☀️"
        case "clouds": return "☁️"
        case "rain": return "🌧️"
        case "drizzle": return "🌦️"
        case "thunderstorm": return "⛈️"
        case "snow": return "❄️"
        case "mist", "fog": return "🌫️"
        default: return "🌤️"
        }
    }
}

struct DailyForecast: Codable, Identifiable {
    var id = UUID() // Changé en var pour Codable
    let date: Date
    let tempMin: Double
    let tempMax: Double
    let condition: WeatherCondition
    let humidity: Int
    let windSpeed: Double
    let precipitationChance: Int
    let uvIndex: Int
    let sunrise: Date?
    let sunset: Date?
    
    var comfortScore: Double {
        // Score de confort pour voyageurs (0-1)
        let tempScore = calculateTempScore()
        let precipScore = Double(100 - precipitationChance) / 100.0
        let windScore = max(0, 1 - (windSpeed / 50.0))
        
        return (tempScore + precipScore + windScore) / 3.0
    }
    
    private func calculateTempScore() -> Double {
        let idealTemp = 22.0
        let tempDiff = abs(tempMax - idealTemp)
        return max(0, 1 - (tempDiff / 20.0))
    }
}

struct HourlyForecast: Codable, Identifiable {
    var id = UUID() // Changé en var pour Codable
    let time: Date
    let temperature: Double
    let feelsLike: Double
    let condition: WeatherCondition
    let precipitationChance: Int
    let windSpeed: Double
    let humidity: Int
}

struct AirQuality: Codable {
    let aqi: Int // Air Quality Index
    let co: Double // Carbon Monoxide
    let no2: Double // Nitrogen Dioxide
    let o3: Double // Ozone
    let pm25: Double // PM2.5
    let pm10: Double // PM10
    let so2: Double // Sulfur Dioxide
    
    var level: AQILevel {
        switch aqi {
        case 1: return .good
        case 2: return .fair
        case 3: return .moderate
        case 4: return .poor
        case 5: return .veryPoor
        default: return .unknown
        }
    }
    
    enum AQILevel: String, CaseIterable {
        case good = "Bon"
        case fair = "Correct"
        case moderate = "Modéré"
        case poor = "Médiocre"
        case veryPoor = "Très mauvais"
        case unknown = "Inconnu"
        
        var color: String {
            switch self {
            case .good: return "#27AE60"
            case .fair: return "#F39C12"
            case .moderate: return "#E67E22"
            case .poor: return "#E74C3C"
            case .veryPoor: return "#8E44AD"
            case .unknown: return "#95A5A6"
            }
        }
    }
}

// MARK: - Trip Models

struct Trip: Codable, Identifiable {
    var id = UUID() // Changé en var pour Codable
    let name: String
    let destinations: [TripDestination]
    let startDate: Date
    let endDate: Date
    let createdAt: Date
    let isActive: Bool
    
    var duration: Int {
        Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
    }
}

struct TripDestination: Codable, Identifiable {
    var id = UUID() // Changé en var pour Codable
    let location: Location
    let arrivalDate: Date
    let departureDate: Date
    let weatherData: WeatherData?
    let notes: String?
    let activities: [PlannedActivity]
}

struct PlannedActivity: Codable, Identifiable {
    var id = UUID() // Changé en var pour Codable
    let name: String
    let type: ActivityType
    let date: Date
    let requiredWeather: WeatherRequirement?
    let isIndoor: Bool
    
    enum ActivityType: String, CaseIterable, Codable {
        case sightseeing = "Visite"
        case outdoor = "Plein air"
        case beach = "Plage"
        case hiking = "Randonnée"
        case shopping = "Shopping"
        case museum = "Musée"
        case restaurant = "Restaurant"
        case photography = "Photo"
        
        var emoji: String {
            switch self {
            case .sightseeing: return "🏛️"
            case .outdoor: return "🌳"
            case .beach: return "🏖️"
            case .hiking: return "🥾"
            case .shopping: return "🛍️"
            case .museum: return "🏛️"
            case .restaurant: return "🍽️"
            case .photography: return "📸"
            }
        }
    }
}

struct WeatherRequirement: Codable {
    let minTemperature: Double?
    let maxTemperature: Double?
    let maxPrecipitationChance: Int?
    let maxWindSpeed: Double?
    let requiresSunlight: Bool
}

// MARK: - Premium Models

struct PremiumFeature: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let icon: String
    let category: FeatureCategory
    let isEnabled: Bool
    
    enum FeatureCategory: String, CaseIterable {
        case destinations = "Destinations"
        case forecasts = "Prévisions"
        case comparisons = "Comparaisons"
        case notifications = "Notifications"
        case offline = "Hors-ligne"
        case ai = "Intelligence Artificielle"
        case integrations = "Intégrations"
    }
}

struct SubscriptionInfo: Codable {
    let isActive: Bool
    let productId: String?
    let expirationDate: Date?
    let autoRenews: Bool
    let purchaseDate: Date?
    let trialEndDate: Date?
    
    var isInTrial: Bool {
        guard let trialEnd = trialEndDate else { return false }
        return Date() < trialEnd
    }
    
    var daysUntilExpiration: Int? {
        guard let expiration = expirationDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiration).day
    }
}

// MARK: - User Preferences

struct UserPreferences: Codable {
    let temperatureUnit: TemperatureUnit
    let windSpeedUnit: WindSpeedUnit
    let pressureUnit: PressureUnit
    let timeFormat: TimeFormat
    let language: String
    let notificationsEnabled: Bool
    let locationServicesEnabled: Bool
    let premiumFeatures: [String] // IDs des fonctionnalités premium activées
    
    enum TemperatureUnit: String, CaseIterable, Codable {
        case celsius = "°C"
        case fahrenheit = "°F"
        case kelvin = "K"
    }
    
    enum WindSpeedUnit: String, CaseIterable, Codable {
        case kmh = "km/h"
        case mph = "mph"
        case ms = "m/s"
        case knots = "knots"
    }
    
    enum PressureUnit: String, CaseIterable, Codable {
        case hPa = "hPa"
        case mmHg = "mmHg"
        case inHg = "inHg"
    }
    
    enum TimeFormat: String, CaseIterable, Codable {
        case twelve = "12h"
        case twentyFour = "24h"
    }
}

// MARK: - Error Models

enum WeatherError: Error, LocalizedError {
    case networkError(String)
    case apiKeyInvalid
    case locationNotFound
    case premiumRequired
    case rateLimitExceeded
    case dataCorrupted
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Erreur réseau: \(message)"
        case .apiKeyInvalid:
            return "Clé API invalide"
        case .locationNotFound:
            return "Lieu introuvable"
        case .premiumRequired:
            return "Fonctionnalité Premium requise"
        case .rateLimitExceeded:
            return "Limite d'API dépassée"
        case .dataCorrupted:
            return "Données corrompues"
        case .unknown(let error):
            return "Erreur inconnue: \(error.localizedDescription)"
        }
    }
}
