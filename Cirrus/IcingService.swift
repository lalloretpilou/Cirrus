//
//  IcingService.swift
//  Cirrus
//
//  Service de calcul et prévision du givrage en altitude
//

import Foundation
import CoreLocation
import WeatherKit

@MainActor
class IcingService: ObservableObject {
    static let shared = IcingService()

    @Published var icingLayers: [IcingLayer] = []
    @Published var icingForecast: [IcingForecastPeriod] = []
    @Published var isLoading = false
    @Published var error: IcingError?

    // Altitudes standards d'analyse (en pieds MSL)
    private let standardAltitudes = [
        0,      // Surface
        3000,   // 3000 ft
        6000,   // 6000 ft
        9000,   // 9000 ft
        12000,  // 12000 ft
        15000,  // 15000 ft
        18000   // 18000 ft
    ]

    private init() {}

    // MARK: - Public Methods

    func analyzeIcingConditions(
        for location: CLLocationCoordinate2D,
        metar: METAR? = nil,
        windsAloft: WindsAloft? = nil
    ) async {
        isLoading = true
        error = nil

        do {
            // Calculer le risque de givrage pour chaque altitude
            var layers: [IcingLayer] = []

            for altitude in standardAltitudes {
                let layer = try await calculateIcingLayer(
                    at: location,
                    altitude: altitude,
                    metar: metar,
                    windsAloft: windsAloft
                )
                layers.append(layer)
            }

            self.icingLayers = layers

            // Générer les prévisions de givrage (6h, 12h, 24h)
            self.icingForecast = try await generateIcingForecast(for: location)

            isLoading = false
        } catch {
            self.error = .analysisError(error.localizedDescription)
            isLoading = false
        }
    }

    // MARK: - Icing Layer Calculation

    private func calculateIcingLayer(
        at location: CLLocationCoordinate2D,
        altitude: Int,
        metar: METAR?,
        windsAloft: WindsAloft?
    ) async throws -> IcingLayer {
        // Obtenir température et humidité à cette altitude
        let temperature = getTemperatureAtAltitude(altitude, metar: metar, windsAloft: windsAloft)
        let humidity = getHumidityAtAltitude(altitude, metar: metar)
        let clouds = getCloudCoverageAtAltitude(altitude, metar: metar)

        // Calculer le risque de givrage
        let risk = calculateIcingRisk(
            temperature: temperature,
            humidity: humidity,
            cloudCoverage: clouds
        )

        // Déterminer le type de givrage
        let type = determineIcingType(temperature: temperature, humidity: humidity)

        return IcingLayer(
            altitude: altitude,
            temperature: temperature,
            humidity: humidity,
            cloudCoverage: clouds,
            icingRisk: risk,
            icingType: type
        )
    }

    private func getTemperatureAtAltitude(_ altitude: Int, metar: METAR?, windsAloft: WindsAloft?) -> Double {
        // Si c'est la surface, utiliser METAR
        if altitude == 0, let metar = metar {
            return metar.temperature.celsius
        }

        // Sinon, utiliser winds aloft si disponible
        if let winds = windsAloft {
            if let level = winds.levels.first(where: { $0.altitude == altitude }) {
                return Double(level.temperature)
            }
        }

        // Sinon, approximation avec lapse rate standard (-2°C par 1000 ft)
        let surfaceTemp = metar?.temperature.celsius ?? 15.0
        let altitudeDiff = Double(altitude) / 1000.0
        return surfaceTemp - (2.0 * altitudeDiff)
    }

    private func getHumidityAtAltitude(_ altitude: Int, metar: METAR?) -> Double {
        if altitude == 0, let metar = metar {
            // Calculer humidité relative depuis T et Td
            let temp = metar.temperature.celsius
            let dewpoint = metar.dewpoint
            return AviationCalculations.calculateRelativeHumidity(temperature: temp, dewpoint: dewpoint)
        }

        // Approximation : humidité diminue avec l'altitude
        let surfaceHumidity: Double = 70.0 // Par défaut
        let decrease = Double(altitude) / 1000.0 * 5.0 // -5% par 1000 ft
        return max(20.0, surfaceHumidity - decrease)
    }

    private func getCloudCoverageAtAltitude(_ altitude: Int, metar: METAR?) -> CloudCoverage {
        guard let metar = metar else { return .none }

        // Chercher les couches nuageuses à cette altitude (±500 ft)
        let relevantClouds = metar.clouds.filter { cloud in
            abs(cloud.altitude - altitude) <= 500
        }

        if relevantClouds.isEmpty {
            return .none
        }

        // Retourner la couverture la plus importante
        if relevantClouds.contains(where: { $0.coverage == .overcast }) {
            return .overcast
        } else if relevantClouds.contains(where: { $0.coverage == .broken }) {
            return .broken
        } else if relevantClouds.contains(where: { $0.coverage == .scattered }) {
            return .scattered
        } else {
            return .few
        }
    }

    private func calculateIcingRisk(
        temperature: Double,
        humidity: Double,
        cloudCoverage: CloudCoverage
    ) -> IcingRisk {
        // Givrage typiquement entre 0°C et -20°C
        guard temperature <= 0 && temperature >= -20 else {
            return .none
        }

        var riskScore = 0.0

        // Score basé sur la température (max risque entre -5°C et -15°C)
        if temperature >= -15 && temperature <= -5 {
            riskScore += 3.0
        } else if temperature >= -20 && temperature <= 0 {
            riskScore += 1.5
        }

        // Score basé sur l'humidité
        if humidity > 80 {
            riskScore += 3.0
        } else if humidity > 60 {
            riskScore += 1.5
        }

        // Score basé sur les nuages (nécessité d'humidité visible)
        switch cloudCoverage {
        case .overcast:
            riskScore += 3.0
        case .broken:
            riskScore += 2.0
        case .scattered:
            riskScore += 1.0
        case .few, .none:
            riskScore += 0.0
        }

        // Déterminer le niveau de risque
        switch riskScore {
        case 0..<2:
            return .none
        case 2..<4:
            return .light
        case 4..<6:
            return .moderate
        case 6..<8:
            return .severe
        default:
            return .extreme
        }
    }

    private func determineIcingType(temperature: Double, humidity: Double) -> IcingType? {
        guard temperature <= 0 && temperature >= -20 else {
            return nil
        }

        // Clear ice (verglas) : -10°C à 0°C avec grosses gouttes
        if temperature > -10 && humidity > 80 {
            return .clearIce
        }

        // Rime ice (givre) : < -10°C avec petites gouttes
        if temperature <= -10 {
            return .rimeIce
        }

        // Mixed : entre les deux
        return .mixedIce
    }

    // MARK: - Forecast Generation

    private func generateIcingForecast(for location: CLLocationCoordinate2D) async throws -> [IcingForecastPeriod] {
        // Générer des prévisions pour 6h, 12h, 24h
        var forecasts: [IcingForecastPeriod] = []

        let intervals: [(hours: Int, label: String)] = [
            (6, "Dans 6h"),
            (12, "Dans 12h"),
            (24, "Dans 24h")
        ]

        for interval in intervals {
            let timestamp = Date().addingTimeInterval(TimeInterval(interval.hours * 3600))

            // Simuler des prévisions (dans une vraie app, utiliser des données météo)
            let forecast = IcingForecastPeriod(
                timestamp: timestamp,
                label: interval.label,
                bottomAltitude: 4000,
                topAltitude: 10000,
                risk: .moderate,
                confidence: 75
            )

            forecasts.append(forecast)
        }

        return forecasts
    }

    // MARK: - Recommendations

    func getFlightRecommendations(icingLayers: [IcingLayer]) -> [IcingRecommendation] {
        var recommendations: [IcingRecommendation] = []

        // Trouver les altitudes sûres
        let safeAltitudes = icingLayers.filter { $0.icingRisk == .none || $0.icingRisk == .light }

        if !safeAltitudes.isEmpty {
            let altitudeList = safeAltitudes.map { "\($0.altitude) ft" }.joined(separator: ", ")
            recommendations.append(IcingRecommendation(
                type: .safe,
                title: "Altitudes sûres",
                message: "Aucun givrage ou givrage léger à : \(altitudeList)",
                priority: .low
            ))
        }

        // Identifier les zones dangereuses
        let dangerousAltitudes = icingLayers.filter { $0.icingRisk == .severe || $0.icingRisk == .extreme }

        if !dangerousAltitudes.isEmpty {
            let altitudeList = dangerousAltitudes.map { "\($0.altitude) ft" }.joined(separator: ", ")
            recommendations.append(IcingRecommendation(
                type: .danger,
                title: "⚠️ Givrage sévère",
                message: "Éviter absolument : \(altitudeList)",
                priority: .high
            ))
        }

        // Recommandation d'équipement
        let hasModerateOrHigher = icingLayers.contains { $0.icingRisk.rawValue >= IcingRisk.moderate.rawValue }

        if hasModerateOrHigher {
            recommendations.append(IcingRecommendation(
                type: .equipment,
                title: "Équipement anti-givrage",
                message: "Avion certifié givrage requis (FIKI)",
                priority: .high
            ))
        }

        // Recommandation de vol VFR
        let highRiskLayers = icingLayers.filter { $0.icingRisk == .severe || $0.icingRisk == .extreme }

        if !highRiskLayers.isEmpty {
            recommendations.append(IcingRecommendation(
                type: .flightRules,
                title: "Vol VFR déconseillé",
                message: "Risque de givrage important - Vol IFR certifié givrage ou report du vol",
                priority: .high
            ))
        }

        return recommendations
    }

    func getSafeAltitudeRange(icingLayers: [IcingLayer]) -> (min: Int, max: Int)? {
        let safeLayers = icingLayers.filter { $0.icingRisk == .none || $0.icingRisk == .light }

        guard !safeLayers.isEmpty else { return nil }

        let altitudes = safeLayers.map { $0.altitude }.sorted()

        // Trouver la plus grande plage continue
        var ranges: [(Int, Int)] = []
        var currentMin = altitudes[0]
        var currentMax = altitudes[0]

        for i in 1..<altitudes.count {
            if altitudes[i] - currentMax <= 3000 { // Tolérance de 3000 ft
                currentMax = altitudes[i]
            } else {
                ranges.append((currentMin, currentMax))
                currentMin = altitudes[i]
                currentMax = altitudes[i]
            }
        }
        ranges.append((currentMin, currentMax))

        // Retourner la plus grande plage
        return ranges.max(by: { $0.1 - $0.0 < $1.1 - $1.0 })
    }
}

// MARK: - Models

struct IcingLayer: Identifiable {
    let id = UUID()
    let altitude: Int               // Feet MSL
    let temperature: Double         // °C
    let humidity: Double            // %
    let cloudCoverage: CloudCoverage
    let icingRisk: IcingRisk
    let icingType: IcingType?
}

enum CloudCoverage {
    case none
    case few
    case scattered
    case broken
    case overcast

    var description: String {
        switch self {
        case .none: return "Ciel clair"
        case .few: return "Peu nuageux"
        case .scattered: return "Nuages épars"
        case .broken: return "Nuages fragmentés"
        case .overcast: return "Couvert"
        }
    }
}

enum IcingRisk: Int, Comparable {
    case none = 0
    case light = 1
    case moderate = 2
    case severe = 3
    case extreme = 4

    static func < (lhs: IcingRisk, rhs: IcingRisk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var description: String {
        switch self {
        case .none: return "Aucun"
        case .light: return "Léger"
        case .moderate: return "Modéré"
        case .severe: return "Sévère"
        case .extreme: return "Extrême"
        }
    }

    var color: String {
        switch self {
        case .none: return "green"
        case .light: return "yellow"
        case .moderate: return "orange"
        case .severe: return "red"
        case .extreme: return "purple"
        }
    }

    var emoji: String {
        switch self {
        case .none: return "✅"
        case .light: return "⚠️"
        case .moderate: return "🟠"
        case .severe: return "🔴"
        case .extreme: return "🚫"
        }
    }
}

enum IcingType {
    case rimeIce        // Givre (blanc, opaque)
    case clearIce       // Verglas (transparent, dangereux)
    case mixedIce       // Mixte

    var description: String {
        switch self {
        case .rimeIce: return "Givre (rime ice)"
        case .clearIce: return "Verglas (clear ice)"
        case .mixedIce: return "Mixte"
        }
    }

    var details: String {
        switch self {
        case .rimeIce:
            return "Givre blanc et opaque. Moins dangereux mais peut s'accumuler rapidement."
        case .clearIce:
            return "Verglas transparent. TRÈS DANGEREUX - accumulation rapide et difficile à détecter."
        case .mixedIce:
            return "Mélange de givre et verglas. Dangereux, accumulation variable."
        }
    }

    var emoji: String {
        switch self {
        case .rimeIce: return "❄️"
        case .clearIce: return "🧊"
        case .mixedIce: return "🌨️"
        }
    }
}

struct IcingForecastPeriod: Identifiable {
    let id = UUID()
    let timestamp: Date
    let label: String
    let bottomAltitude: Int     // Feet MSL
    let topAltitude: Int        // Feet MSL
    let risk: IcingRisk
    let confidence: Int         // 0-100%
}

struct IcingRecommendation: Identifiable {
    let id = UUID()
    let type: RecommendationType
    let title: String
    let message: String
    let priority: Priority

    enum RecommendationType {
        case safe
        case caution
        case danger
        case equipment
        case flightRules

        var icon: String {
            switch self {
            case .safe: return "checkmark.circle.fill"
            case .caution: return "exclamationmark.triangle.fill"
            case .danger: return "xmark.octagon.fill"
            case .equipment: return "wrench.and.screwdriver.fill"
            case .flightRules: return "airplane.circle.fill"
            }
        }

        var color: String {
            switch self {
            case .safe: return "green"
            case .caution: return "yellow"
            case .danger: return "red"
            case .equipment: return "blue"
            case .flightRules: return "orange"
            }
        }
    }

    enum Priority {
        case low
        case medium
        case high

        var sortOrder: Int {
            switch self {
            case .high: return 0
            case .medium: return 1
            case .low: return 2
            }
        }
    }
}

// MARK: - Errors

enum IcingError: LocalizedError {
    case analysisError(String)
    case noData

    var errorDescription: String? {
        switch self {
        case .analysisError(let message):
            return "Erreur d'analyse: \(message)"
        case .noData:
            return "Aucune donnée de givrage disponible"
        }
    }
}

// MARK: - Helper Extension

private extension AviationCalculations {
    static func calculateRelativeHumidity(temperature: Double, dewpoint: Double) -> Double {
        let a = 17.625
        let b = 243.04

        let gamma_t = (a * temperature) / (b + temperature)
        let gamma_dp = (a * dewpoint) / (b + dewpoint)

        let rh = 100.0 * exp(gamma_dp - gamma_t)
        return min(100.0, max(0.0, rh))
    }
}
