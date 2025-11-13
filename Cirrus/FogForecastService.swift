//
//  FogForecastService.swift
//  Cirrus
//
//  Service de prévision de brouillard et heure de dissipation
//

import Foundation
import CoreLocation
import WeatherKit

@MainActor
class FogForecastService: ObservableObject {
    static let shared = FogForecastService()

    @Published var fogForecast: FogForecast?
    @Published var hourlyFogRisk: [HourlyFogRisk] = []
    @Published var isLoading = false
    @Published var error: FogError?

    private init() {}

    // MARK: - Public Methods

    func analyzeFogConditions(
        metar: METAR,
        aerodrome: Aerodrome,
        hourlyForecasts: [HourlyWeatherForecast]? = nil
    ) async {
        isLoading = true
        error = nil

        do {
            // Analyser les conditions actuelles
            let currentRisk = calculateFogRisk(
                temperature: metar.temperature.celsius,
                dewpoint: metar.dewpoint,
                windSpeed: metar.wind.speed,
                visibility: metar.visibility.value,
                time: Date()
            )

            // Prédire l'heure de dissipation si brouillard présent
            var dissipationTime: Date?
            if currentRisk.level == .present || currentRisk.level == .forming {
                dissipationTime = predictDissipationTime(
                    metar: metar,
                    aerodrome: aerodrome
                )
            }

            // Analyser les prochaines 24h
            let hourlyRisks = try await analyzeNext24Hours(
                metar: metar,
                aerodrome: aerodrome
            )

            self.fogForecast = FogForecast(
                currentRisk: currentRisk,
                dissipationTime: dissipationTime,
                nextFormationTime: findNextFormationTime(hourlyRisks: hourlyRisks),
                aerodrome: aerodrome,
                generatedAt: Date()
            )

            self.hourlyFogRisk = hourlyRisks

            isLoading = false
        } catch {
            self.error = .analysisError(error.localizedDescription)
            isLoading = false
        }
    }

    // MARK: - Fog Risk Calculation

    private func calculateFogRisk(
        temperature: Double,
        dewpoint: Double,
        windSpeed: Int,
        visibility: Double,
        time: Date
    ) -> FogRisk {
        // Calcul de la différence température - point de rosée (spread)
        let spread = temperature - dewpoint

        // Calcul de l'humidité relative
        let humidity = calculateRelativeHumidity(temperature: temperature, dewpoint: dewpoint)

        // Déterminer le niveau de risque
        var level: FogRiskLevel
        var probability: Int
        var description: String

        // Brouillard présent (visibilité < 1 SM)
        if visibility < 1.0 {
            level = .present
            probability = 100
            description = "Brouillard actuellement présent"
        }
        // Brouillard en formation (spread < 1°C, visibilité réduite)
        else if spread < 1.0 && visibility < 3.0 && windSpeed < 5 {
            level = .forming
            probability = 90
            description = "Brouillard en cours de formation"
        }
        // Risque très élevé (spread < 2°C, vent faible)
        else if spread < 2.0 && humidity > 90 && windSpeed < 5 {
            level = .veryHigh
            probability = 75
            description = "Risque très élevé de formation"
        }
        // Risque élevé
        else if spread < 3.0 && humidity > 85 && windSpeed < 8 {
            level = .high
            probability = 60
            description = "Risque élevé de brouillard"
        }
        // Risque modéré
        else if spread < 4.0 && humidity > 75 && windSpeed < 10 {
            level = .moderate
            probability = 40
            description = "Risque modéré de brouillard"
        }
        // Risque faible
        else if spread < 5.0 && humidity > 65 {
            level = .low
            probability = 20
            description = "Risque faible de brouillard"
        }
        // Pas de risque
        else {
            level = .none
            probability = 0
            description = "Aucun risque de brouillard"
        }

        // Facteurs aggravants
        var factors: [String] = []

        if spread < 2.0 {
            factors.append("Écart température-rosée très faible (\(String(format: "%.1f", spread))°C)")
        }

        if humidity > 90 {
            factors.append("Humidité très élevée (\(Int(humidity))%)")
        }

        if windSpeed < 5 {
            factors.append("Vent très faible (\(windSpeed) kt)")
        }

        // Heure de la nuit / petit matin = risque accru
        let hour = Calendar.current.component(.hour, from: time)
        if hour >= 22 || hour <= 8 {
            factors.append("Période nocturne/matinale favorable")
        }

        return FogRisk(
            level: level,
            probability: probability,
            description: description,
            spread: spread,
            humidity: humidity,
            windSpeed: windSpeed,
            visibility: visibility,
            factors: factors
        )
    }

    // MARK: - Dissipation Prediction

    private func predictDissipationTime(metar: METAR, aerodrome: Aerodrome) -> Date? {
        let now = Date()
        let calendar = Calendar.current

        // Obtenir l'heure du lever du soleil
        let sunrise = getSunrise(for: aerodrome.location.coordinate, date: now)

        // Calculer le temps estimé de dissipation
        let spread = metar.temperature.celsius - metar.dewpoint
        let windSpeed = metar.wind.speed

        // Facteurs de dissipation
        var dissipationDelay: TimeInterval = 0

        // Spread faible = dissipation plus lente
        if spread < 1.0 {
            dissipationDelay += 3 * 3600 // 3 heures
        } else if spread < 2.0 {
            dissipationDelay += 2 * 3600 // 2 heures
        } else {
            dissipationDelay += 1 * 3600 // 1 heure
        }

        // Vent aide à la dissipation
        if windSpeed > 5 {
            dissipationDelay -= 1800 // -30 min
        }
        if windSpeed > 10 {
            dissipationDelay -= 1800 // -30 min supplémentaires
        }

        // Le soleil est le principal facteur de dissipation
        let estimatedDissipation = sunrise.addingTimeInterval(dissipationDelay)

        // Si déjà après le lever du soleil, calcul différent
        if now > sunrise {
            let hoursSinceSunrise = now.timeIntervalSince(sunrise) / 3600
            if hoursSinceSunrise < 3 {
                // Devrait se dissiper bientôt
                return now.addingTimeInterval(dissipationDelay - (hoursSinceSunrise * 1800))
            }
        }

        return estimatedDissipation
    }

    // MARK: - Hourly Analysis

    private func analyzeNext24Hours(metar: METAR, aerodrome: Aerodrome) async throws -> [HourlyFogRisk] {
        var hourlyRisks: [HourlyFogRisk] = []

        // Simuler les prévisions horaires (dans une vraie implémentation, utiliser WeatherKit)
        let now = Date()

        for hour in 0..<24 {
            let forecastTime = now.addingTimeInterval(TimeInterval(hour * 3600))

            // Simuler l'évolution de la température et du point de rosée
            let hourOfDay = Calendar.current.component(.hour, from: forecastTime)

            // Modèle simplifié : température baisse la nuit, monte le jour
            var tempAdjust = 0.0
            if hourOfDay >= 6 && hourOfDay <= 18 {
                // Jour : température monte
                tempAdjust = Double(hourOfDay - 6) * 0.5
            } else {
                // Nuit : température baisse
                if hourOfDay > 18 {
                    tempAdjust = -Double(hourOfDay - 18) * 0.3
                } else {
                    tempAdjust = -Double(6 - hourOfDay) * 0.3
                }
            }

            let forecastTemp = metar.temperature.celsius + tempAdjust
            let forecastDewpoint = metar.dewpoint + (tempAdjust * 0.5) // Point de rosée évolue moins vite
            let forecastWind = metar.wind.speed + Int.random(in: -2...3)

            // Estimer la visibilité
            let spread = forecastTemp - forecastDewpoint
            var forecastVisibility = 10.0
            if spread < 1.0 {
                forecastVisibility = 0.5
            } else if spread < 2.0 {
                forecastVisibility = 2.0
            } else if spread < 3.0 {
                forecastVisibility = 5.0
            }

            let risk = calculateFogRisk(
                temperature: forecastTemp,
                dewpoint: forecastDewpoint,
                windSpeed: forecastWind,
                visibility: forecastVisibility,
                time: forecastTime
            )

            hourlyRisks.append(HourlyFogRisk(
                time: forecastTime,
                risk: risk,
                temperature: forecastTemp,
                dewpoint: forecastDewpoint
            ))
        }

        return hourlyRisks
    }

    // MARK: - Helper Methods

    private func findNextFormationTime(hourlyRisks: [HourlyFogRisk]) -> Date? {
        // Trouver la prochaine période à haut risque
        for hourlyRisk in hourlyRisks {
            if hourlyRisk.risk.level == .high ||
               hourlyRisk.risk.level == .veryHigh ||
               hourlyRisk.risk.level == .forming {
                return hourlyRisk.time
            }
        }
        return nil
    }

    private func calculateRelativeHumidity(temperature: Double, dewpoint: Double) -> Double {
        let a = 17.625
        let b = 243.04

        let gamma_t = (a * temperature) / (b + temperature)
        let gamma_dp = (a * dewpoint) / (b + dewpoint)

        let rh = 100.0 * exp(gamma_dp - gamma_t)
        return min(100.0, max(0.0, rh))
    }

    private func getSunrise(for coordinate: CLLocationCoordinate2D, date: Date) -> Date {
        // Calcul simplifié du lever du soleil
        // Dans une vraie implémentation, utiliser une bibliothèque d'astronomie
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)

        // Approximation : lever du soleil vers 6h-7h (dépend de la saison et latitude)
        // Utiliser la latitude pour ajuster
        let latitude = coordinate.latitude
        var sunriseHour = 6

        // Ajustement basique selon latitude et saison
        let month = components.month ?? 6
        if month >= 11 || month <= 2 { // Hiver
            sunriseHour = 7
        } else if month >= 5 && month <= 8 { // Été
            sunriseHour = 5
        }

        components.hour = sunriseHour
        components.minute = 30

        return calendar.date(from: components) ?? date.addingTimeInterval(6 * 3600)
    }

    func getFlightReadyTime(forecast: FogForecast) -> Date? {
        // Temps recommandé pour le décollage = dissipation + 30 min de marge
        guard let dissipation = forecast.dissipationTime else { return nil }
        return dissipation.addingTimeInterval(30 * 60)
    }
}

// MARK: - Models

struct FogForecast {
    let currentRisk: FogRisk
    let dissipationTime: Date?
    let nextFormationTime: Date?
    let aerodrome: Aerodrome
    let generatedAt: Date

    var hasActiveFog: Bool {
        currentRisk.level == .present || currentRisk.level == .forming
    }

    var recommendation: String {
        if hasActiveFog {
            if let dissipation = dissipationTime {
                return "Brouillard présent. Décollage possible vers \(dissipation.formatted(date: .omitted, time: .shortened))"
            } else {
                return "Brouillard présent. Évolution incertaine."
            }
        } else if currentRisk.level == .veryHigh || currentRisk.level == .high {
            return "Risque élevé de brouillard. Surveiller l'évolution."
        } else if currentRisk.level == .moderate {
            return "Risque modéré de brouillard. Conditions acceptables."
        } else {
            return "Pas de risque de brouillard. Conditions favorables."
        }
    }
}

struct FogRisk {
    let level: FogRiskLevel
    let probability: Int
    let description: String
    let spread: Double
    let humidity: Double
    let windSpeed: Int
    let visibility: Double
    let factors: [String]
}

enum FogRiskLevel: Int, Comparable {
    case none = 0
    case low = 1
    case moderate = 2
    case high = 3
    case veryHigh = 4
    case forming = 5
    case present = 6

    static func < (lhs: FogRiskLevel, rhs: FogRiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var description: String {
        switch self {
        case .none: return "Aucun risque"
        case .low: return "Risque faible"
        case .moderate: return "Risque modéré"
        case .high: return "Risque élevé"
        case .veryHigh: return "Risque très élevé"
        case .forming: return "En formation"
        case .present: return "Présent"
        }
    }

    var color: String {
        switch self {
        case .none: return "green"
        case .low: return "lightGreen"
        case .moderate: return "yellow"
        case .high: return "orange"
        case .veryHigh: return "red"
        case .forming: return "darkRed"
        case .present: return "purple"
        }
    }

    var emoji: String {
        switch self {
        case .none: return "✅"
        case .low: return "🟢"
        case .moderate: return "🟡"
        case .high: return "🟠"
        case .veryHigh: return "🔴"
        case .forming: return "🌫️"
        case .present: return "🌫️"
        }
    }
}

struct HourlyFogRisk: Identifiable {
    let id = UUID()
    let time: Date
    let risk: FogRisk
    let temperature: Double
    let dewpoint: Double

    var hour: String {
        time.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Errors

enum FogError: LocalizedError {
    case analysisError(String)
    case noData

    var errorDescription: String? {
        switch self {
        case .analysisError(let message):
            return "Erreur d'analyse: \(message)"
        case .noData:
            return "Aucune donnée disponible"
        }
    }
}
