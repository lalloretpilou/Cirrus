import Foundation
import CoreLocation
import WeatherKit
import Combine

class WeatherService: ObservableObject {
    static let shared = WeatherService()
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let weatherKitService = WeatherKit.WeatherService.shared
    private let weatherAPIService = WeatherAPIService()
    private let session = URLSession.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Cache pour éviter les appels répétés - FIX: Utilisation de NSCache thread-safe
    private let weatherCache = NSCache<NSString, CachedWeatherData>()
    private let cacheExpiration: TimeInterval = 10 * 60 // 10 minutes
    
    private init() {
        weatherCache.countLimit = 50 // Limiter le cache à 50 entrées
        weatherCache.totalCostLimit = 1024 * 1024 * 10 // 10 MB max
    }
    
    // MARK: - Public Methods
    
    /// Récupère les données météo en utilisant les deux APIs pour plus de fiabilité
    func getWeatherData(for location: Location) async throws -> WeatherData {
        let cacheKey = NSString(string: "\(location.coordinates.latitude),\(location.coordinates.longitude)")
        
        // Vérifier le cache - FIX: Utilisation thread-safe de NSCache
        if let cachedData = weatherCache.object(forKey: cacheKey),
           Date().timeIntervalSince(cachedData.timestamp) < cacheExpiration {
            return cachedData.weatherData
        }
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        var weatherKitData: WeatherData?
        var weatherAPIData: WeatherData?
        var errors: [Error] = []
        
        // Tentative avec WeatherKit
        do {
            weatherKitData = try await getWeatherKitData(for: location)
        } catch {
            errors.append(error)
            print("WeatherKit failed: \(error)")
        }
        
        // Tentative avec WeatherAPI
        do {
            weatherAPIData = try await weatherAPIService.getWeatherData(for: location)
        } catch {
            errors.append(error)
            print("WeatherAPI failed: \(error)")
        }
        
        await MainActor.run {
            isLoading = false
        }
        
        // Combiner les données ou utiliser la meilleure disponible
        let combinedData: WeatherData
        
        if let weatherKitData = weatherKitData, let weatherAPIData = weatherAPIData {
            // Combiner les deux sources pour plus de précision
            combinedData = await combineWeatherData(weatherKit: weatherKitData, weatherAPI: weatherAPIData, location: location)
        } else if let weatherKitData = weatherKitData {
            combinedData = weatherKitData
        } else if let weatherAPIData = weatherAPIData {
            combinedData = weatherAPIData
        } else {
            // Aucune source n'a fonctionné
            let combinedError = WeatherError.networkError("Aucune source météo disponible")
            await MainActor.run {
                self.errorMessage = combinedError.localizedDescription
            }
            throw combinedError
        }
        
        // Mettre en cache - FIX: Création thread-safe de CachedWeatherData
        let cachedData = CachedWeatherData(weatherData: combinedData, timestamp: Date())
        weatherCache.setObject(cachedData, forKey: cacheKey)
        
        return combinedData
    }
    
    /// Recherche de lieux avec autocomplétion
    func searchLocations(query: String) async throws -> [Location] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return try await weatherAPIService.searchLocations(query: query)
    }
    
    /// Obtenir les données météo pour plusieurs destinations (Premium)
    func getMultipleWeatherData(for locations: [Location]) async throws -> [WeatherData] {
        // Vérifier les permissions Premium de manière asynchrone
        let canUse = await MainActor.run {
            return PremiumManager.shared.canUseFeature(.advancedComparison)
        }
        
        guard canUse else {
            throw WeatherError.premiumRequired
        }
        
        return try await withThrowingTaskGroup(of: WeatherData.self) { group in
            for location in locations {
                group.addTask {
                    try await self.getWeatherData(for: location)
                }
            }
            
            var results: [WeatherData] = []
            for try await weatherData in group {
                results.append(weatherData)
            }
            return results
        }
    }
    
    // MARK: - Private Methods
    
    private func getWeatherKitData(for location: Location) async throws -> WeatherData {
        let clLocation = CLLocation(
            latitude: location.coordinates.latitude,
            longitude: location.coordinates.longitude
        )
        
        // Récupérer les données actuelles et les prévisions
        let weather = try await weatherKitService.weather(for: clLocation)
        
        // Convertir en format unifié
        return convertWeatherKitData(weather, for: location)
    }
    
    private func convertWeatherKitData(_ weather: Weather, for location: Location) -> WeatherData {
        // FIX: Gestion sécurisée des valeurs optionnelles
        let windDirection = weather.currentWeather.wind.direction.value ?? 0
        
        // Convertir les données actuelles
        let current = CurrentWeather(
            temperature: weather.currentWeather.temperature.value,
            feelsLike: weather.currentWeather.apparentTemperature.value,
            condition: WeatherCondition(
                id: 0, // WeatherKit n'utilise pas d'ID numérique
                main: weather.currentWeather.condition.description,
                description: weather.currentWeather.condition.description,
                icon: weather.currentWeather.symbolName
            ),
            humidity: Int(weather.currentWeather.humidity * 100),
            pressure: weather.currentWeather.pressure.value,
            visibility: weather.currentWeather.visibility.value,
            uvIndex: weather.currentWeather.uvIndex.value,
            windSpeed: weather.currentWeather.wind.speed.value,
            windDirection: Int(windDirection),
            cloudCover: Int(weather.currentWeather.cloudCover * 100),
            dewPoint: weather.currentWeather.dewPoint.value,
            airQuality: nil // WeatherKit ne fournit pas toujours ces données
        )
        
        // Convertir les prévisions quotidiennes - FIX: Gestion sécurisée des dates
        let dailyForecast = weather.dailyForecast.forecast.compactMap { day -> DailyForecast? in
            guard let sunrise = day.sun.sunrise,
                  let sunset = day.sun.sunset else {
                return DailyForecast(
                    date: day.date,
                    tempMin: day.lowTemperature.value,
                    tempMax: day.highTemperature.value,
                    condition: WeatherCondition(
                        id: 0,
                        main: day.condition.description,
                        description: day.condition.description,
                        icon: day.symbolName
                    ),
                    humidity: Int(weather.currentWeather.humidity * 100),
                    windSpeed: day.wind.speed.value,
                    precipitationChance: Int(day.precipitationChance * 100),
                    uvIndex: day.uvIndex.value,
                    sunrise: nil,
                    sunset: nil
                )
            }
            
            return DailyForecast(
                date: day.date,
                tempMin: day.lowTemperature.value,
                tempMax: day.highTemperature.value,
                condition: WeatherCondition(
                    id: 0,
                    main: day.condition.description,
                    description: day.condition.description,
                    icon: day.symbolName
                ),
                humidity: Int(weather.currentWeather.humidity * 100),
                windSpeed: day.wind.speed.value,
                precipitationChance: Int(day.precipitationChance * 100),
                uvIndex: day.uvIndex.value,
                sunrise: sunrise,
                sunset: sunset
            )
        }
        
        // Convertir les prévisions horaires - FIX: Gestion sécurisée des collections
        let hourlyForecast = weather.hourlyForecast.forecast.prefix(24).compactMap { hour -> HourlyForecast? in
            return HourlyForecast(
                time: hour.date,
                temperature: hour.temperature.value,
                feelsLike: hour.apparentTemperature.value,
                condition: WeatherCondition(
                    id: 0,
                    main: hour.condition.description,
                    description: hour.condition.description,
                    icon: hour.symbolName
                ),
                precipitationChance: Int(hour.precipitationChance * 100),
                windSpeed: hour.wind.speed.value,
                humidity: Int(hour.humidity * 100)
            )
        }
        
        return WeatherData(
            location: location,
            current: current,
            forecast: dailyForecast,
            hourlyForecast: Array(hourlyForecast),
            lastUpdated: Date(),
            source: .weatherKit
        )
    }
    
    private func combineWeatherData(weatherKit: WeatherData, weatherAPI: WeatherData, location: Location) async -> WeatherData {
        // Logique pour combiner les données des deux sources
        let combinedCurrent = CurrentWeather(
            temperature: weatherKit.current.temperature,
            feelsLike: weatherKit.current.feelsLike,
            condition: weatherKit.current.condition,
            humidity: weatherKit.current.humidity,
            pressure: weatherKit.current.pressure,
            visibility: weatherKit.current.visibility,
            uvIndex: weatherKit.current.uvIndex,
            windSpeed: weatherKit.current.windSpeed,
            windDirection: weatherKit.current.windDirection,
            cloudCover: weatherKit.current.cloudCover,
            dewPoint: weatherKit.current.dewPoint,
            airQuality: weatherAPI.current.airQuality // WeatherAPI a de meilleures données AQI
        )
        
        // Combiner les prévisions - FIX: Gestion sécurisée des arrays
        var combinedForecast: [DailyForecast] = []
        
        // WeatherKit pour les 7 premiers jours
        let weatherKitForecast = Array(weatherKit.forecast.prefix(7))
        combinedForecast.append(contentsOf: weatherKitForecast)
        
        // Ajouter les prévisions étendues de WeatherAPI si Premium
        let canUseExtended = await MainActor.run {
            return PremiumManager.shared.canUseFeature(.extendedForecast)
        }
        
        if canUseExtended && weatherAPI.forecast.count > 7 {
            let extendedForecast = Array(weatherAPI.forecast.dropFirst(7).prefix(23)) // Jours 8-30
            combinedForecast.append(contentsOf: extendedForecast)
        }
        
        return WeatherData(
            location: location,
            current: combinedCurrent,
            forecast: combinedForecast,
            hourlyForecast: weatherKit.hourlyForecast, // WeatherKit plus précis à court terme
            lastUpdated: Date(),
            source: .combined
        )
    }
    
    // MARK: - Cache Management
    
    func clearCache() {
        weatherCache.removeAllObjects()
    }
    
    func cleanExpiredCache() {
        // NSCache gère automatiquement l'expiration et la mémoire
        // Pas besoin d'implémentation manuelle avec NSCache
    }
}

// MARK: - WeatherAPI Service

class WeatherAPIService {
    private let apiKey = "43988f5991534043a2b71620212708" // À remplacer par votre clé
    private let baseURL = "https://api.weatherapi.com/v1"
    private let session = URLSession.shared
    
    func getWeatherData(for location: Location) async throws -> WeatherData {
        let url = buildURL(endpoint: "forecast.json", location: location, days: 30)
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw WeatherError.networkError("API request failed with status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        
        do {
            let weatherAPIResponse = try JSONDecoder().decode(WeatherAPIResponse.self, from: data)
            return convertWeatherAPIData(weatherAPIResponse, for: location)
        } catch {
            print("WeatherAPI decode error: \(error)")
            throw WeatherError.dataCorrupted
        }
    }
    
    func searchLocations(query: String) async throws -> [Location] {
        let url = buildSearchURL(query: query)
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw WeatherError.networkError("Search request failed")
        }
        
        do {
            let locations = try JSONDecoder().decode([WeatherAPILocation].self, from: data)
            return locations.map { convertLocation($0) }
        } catch {
            print("WeatherAPI search decode error: \(error)")
            throw WeatherError.dataCorrupted
        }
    }
    
    private func buildURL(endpoint: String, location: Location, days: Int) -> URL {
        var components = URLComponents(string: "\(baseURL)/\(endpoint)")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "q", value: "\(location.coordinates.latitude),\(location.coordinates.longitude)"),
            URLQueryItem(name: "days", value: "\(days)"),
            URLQueryItem(name: "aqi", value: "yes"),
            URLQueryItem(name: "alerts", value: "yes")
        ]
        return components.url!
    }
    
    private func buildSearchURL(query: String) -> URL {
        var components = URLComponents(string: "\(baseURL)/search.json")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "q", value: query)
        ]
        return components.url!
    }
    
    private func convertWeatherAPIData(_ response: WeatherAPIResponse, for location: Location) -> WeatherData {
        let current = CurrentWeather(
            temperature: response.current.temp_c,
            feelsLike: response.current.feelslike_c,
            condition: WeatherCondition(
                id: response.current.condition.code,
                main: response.current.condition.text,
                description: response.current.condition.text,
                icon: response.current.condition.icon
            ),
            humidity: response.current.humidity,
            pressure: response.current.pressure_mb,
            visibility: response.current.vis_km,
            uvIndex: Int(response.current.uv),
            windSpeed: response.current.wind_kph,
            windDirection: response.current.wind_degree,
            cloudCover: response.current.cloud,
            dewPoint: response.current.dewpoint_c ?? 0,
            airQuality: response.current.air_quality.map { aq in
                AirQuality(
                    aqi: Int(aq.us_epa_index ?? 1),
                    co: aq.co,
                    no2: aq.no2,
                    o3: aq.o3,
                    pm25: aq.pm2_5,
                    pm10: aq.pm10,
                    so2: aq.so2
                )
            }
        )
        
        // FIX: Gestion sécurisée du parsing des dates
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let forecast = response.forecast.forecastday.compactMap { day -> DailyForecast? in
            guard let date = dateFormatter.date(from: day.date) else {
                print("Could not parse date: \(day.date)")
                return nil
            }
            
            return DailyForecast(
                date: date,
                tempMin: day.day.mintemp_c,
                tempMax: day.day.maxtemp_c,
                condition: WeatherCondition(
                    id: day.day.condition.code,
                    main: day.day.condition.text,
                    description: day.day.condition.text,
                    icon: day.day.condition.icon
                ),
                humidity: day.day.avghumidity,
                windSpeed: day.day.maxwind_kph,
                precipitationChance: day.day.daily_chance_of_rain,
                uvIndex: Int(day.day.uv),
                sunrise: parseTime(day.astro.sunrise),
                sunset: parseTime(day.astro.sunset)
            )
        }
        
        // FIX: Gestion sécurisée des prévisions horaires
        let hourlyDateFormatter = ISO8601DateFormatter()
        
        let hourlyForecast = response.forecast.forecastday.flatMap { day in
            day.hour.compactMap { hour -> HourlyForecast? in
                guard let time = hourlyDateFormatter.date(from: hour.time) else {
                    print("Could not parse hour time: \(hour.time)")
                    return nil
                }
                
                return HourlyForecast(
                    time: time,
                    temperature: hour.temp_c,
                    feelsLike: hour.feelslike_c,
                    condition: WeatherCondition(
                        id: hour.condition.code,
                        main: hour.condition.text,
                        description: hour.condition.text,
                        icon: hour.condition.icon
                    ),
                    precipitationChance: hour.chance_of_rain,
                    windSpeed: hour.wind_kph,
                    humidity: hour.humidity
                )
            }
        }
        
        return WeatherData(
            location: location,
            current: current,
            forecast: forecast,
            hourlyForecast: Array(hourlyForecast.prefix(48)), // 48 heures
            lastUpdated: Date(),
            source: .weatherAPI
        )
    }
    
    private func convertLocation(_ apiLocation: WeatherAPILocation) -> Location {
        let locationName = apiLocation.region.isEmpty ?
            apiLocation.name :
            "\(apiLocation.name), \(apiLocation.region)"
        
        return Location(
            name: locationName,
            country: apiLocation.country,
            coordinates: Location.Coordinates(
                latitude: apiLocation.lat,
                longitude: apiLocation.lon
            ),
            timezone: nil,
            isFavorite: false,
            isPremium: false
        )
    }
    
    private func parseTime(_ timeString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "hh:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: timeString)
    }
}

// MARK: - Cached Data - FIX: NSCache compatible class

private class CachedWeatherData: NSObject {
    let weatherData: WeatherData
    let timestamp: Date
    
    init(weatherData: WeatherData, timestamp: Date) {
        self.weatherData = weatherData
        self.timestamp = timestamp
        super.init()
    }
}

// MARK: - WeatherAPI Response Models

private struct WeatherAPIResponse: Codable {
    let current: WeatherAPICurrent
    let forecast: WeatherAPIForecast
}

private struct WeatherAPICurrent: Codable {
    let temp_c: Double
    let feelslike_c: Double
    let condition: WeatherAPICondition
    let humidity: Int
    let pressure_mb: Double
    let vis_km: Double
    let uv: Double
    let wind_kph: Double
    let wind_degree: Int
    let cloud: Int
    let dewpoint_c: Double?
    let air_quality: WeatherAPIAirQuality?
}

private struct WeatherAPICondition: Codable {
    let code: Int
    let text: String
    let icon: String
}

private struct WeatherAPIAirQuality: Codable {
    let co: Double
    let no2: Double
    let o3: Double
    let so2: Double
    let pm2_5: Double
    let pm10: Double
    let us_epa_index: Double?
}

private struct WeatherAPIForecast: Codable {
    let forecastday: [WeatherAPIForecastDay]
}

private struct WeatherAPIForecastDay: Codable {
    let date: String
    let day: WeatherAPIDay
    let astro: WeatherAPIAstro
    let hour: [WeatherAPIHour]
}

private struct WeatherAPIDay: Codable {
    let maxtemp_c: Double
    let mintemp_c: Double
    let condition: WeatherAPICondition
    let avghumidity: Int
    let maxwind_kph: Double
    let daily_chance_of_rain: Int
    let uv: Double
}

private struct WeatherAPIAstro: Codable {
    let sunrise: String
    let sunset: String
}

private struct WeatherAPIHour: Codable {
    let time: String
    let temp_c: Double
    let feelslike_c: Double
    let condition: WeatherAPICondition
    let chance_of_rain: Int
    let wind_kph: Double
    let humidity: Int
}

private struct WeatherAPILocation: Codable {
    let name: String
    let region: String
    let country: String
    let lat: Double
    let lon: Double
}
