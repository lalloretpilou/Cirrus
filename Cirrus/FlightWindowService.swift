//
//  FlightWindowService.swift
//  Cirrus
//
//  Service de recherche de fenêtre de vol optimale
//

import Foundation
import CoreLocation

@MainActor
class FlightWindowService: ObservableObject {
    static let shared = FlightWindowService()

    @Published var flightWindows: [FlightWindow] = []
    @Published var optimalWindow: FlightWindow?
    @Published var currentConditions: WindowConditions?
    @Published var isLoading = false
    @Published var error: FlightWindowError?

    // Configuration de recherche
    var searchConfig = SearchConfig.default

    private init() {}

    // MARK: - Public Methods

    func findOptimalWindows(
        aerodrome: Aerodrome,
        metar: METAR,
        taf: TAF?,
        flightType: FlightType = .vfr
    ) async {
        isLoading = true
        error = nil

        do {
            // Analyser les conditions actuelles
            let current = analyzeCurrentConditions(metar: metar, aerodrome: aerodrome)
            self.currentConditions = current

            // Générer les fenêtres horaires
            let windows = try await generateFlightWindows(
                aerodrome: aerodrome,
                metar: metar,
                taf: taf,
                flightType: flightType
            )

            // Trier par score (meilleur en premier)
            let sortedWindows = windows.sorted { $0.score > $1.score }

            self.flightWindows = sortedWindows
            self.optimalWindow = sortedWindows.first(where: { $0.isRecommended })

            isLoading = false
        } catch {
            self.error = .analysisError(error.localizedDescription)
            isLoading = false
        }
    }

    // MARK: - Current Conditions Analysis

    private func analyzeCurrentConditions(metar: METAR, aerodrome: Aerodrome) -> WindowConditions {
        var score = 100
        var factors: [ConditionFactor] = []
        var restrictions: [String] = []

        // Flight Rules
        switch metar.flightRules {
        case .vfr:
            factors.append(ConditionFactor(
                category: .flightRules,
                description: "VFR - Conditions visuelles",
                impact: .positive,
                points: 0
            ))
        case .mvfr:
            score -= 20
            factors.append(ConditionFactor(
                category: .flightRules,
                description: "MVFR - Conditions visuelles marginales",
                impact: .negative,
                points: -20
            ))
            restrictions.append("Vol VFR avec prudence")
        case .ifr:
            score -= 40
            factors.append(ConditionFactor(
                category: .flightRules,
                description: "IFR - Conditions aux instruments",
                impact: .critical,
                points: -40
            ))
            restrictions.append("Vol IFR uniquement")
        case .lifr:
            score -= 60
            factors.append(ConditionFactor(
                category: .flightRules,
                description: "LIFR - Conditions très mauvaises",
                impact: .critical,
                points: -60
            ))
            restrictions.append("Vol fortement déconseillé")
        }

        // Visibility
        if metar.visibility.value < 1.0 {
            score -= 40
            factors.append(ConditionFactor(
                category: .visibility,
                description: "Visibilité très faible (\(metar.visibility.value) SM)",
                impact: .critical,
                points: -40
            ))
        } else if metar.visibility.value < 3.0 {
            score -= 20
            factors.append(ConditionFactor(
                category: .visibility,
                description: "Visibilité réduite (\(metar.visibility.value) SM)",
                impact: .negative,
                points: -20
            ))
        } else if metar.visibility.value >= 10.0 {
            factors.append(ConditionFactor(
                category: .visibility,
                description: "Excellente visibilité (\(metar.visibility.value) SM)",
                impact: .positive,
                points: 0
            ))
        }

        // Wind
        let windSpeed = metar.wind.speed
        let gustSpeed = metar.wind.gust ?? 0

        if gustSpeed > 25 {
            score -= 40
            factors.append(ConditionFactor(
                category: .wind,
                description: "Rafales très fortes (\(gustSpeed) kt)",
                impact: .critical,
                points: -40
            ))
            restrictions.append("Vent violent - Vol déconseillé")
        } else if gustSpeed > 15 || windSpeed > 20 {
            score -= 20
            factors.append(ConditionFactor(
                category: .wind,
                description: "Vent fort avec rafales (\(windSpeed)G\(gustSpeed) kt)",
                impact: .negative,
                points: -20
            ))
            restrictions.append("Vent significatif - Pilotes expérimentés")
        } else if windSpeed < 5 {
            factors.append(ConditionFactor(
                category: .wind,
                description: "Vent calme (\(windSpeed) kt)",
                impact: .positive,
                points: 0
            ))
        }

        // Ceiling
        let lowestCeiling = metar.clouds
            .filter { $0.coverage == .broken || $0.coverage == .overcast }
            .map { $0.altitude }
            .min()

        if let ceiling = lowestCeiling {
            if ceiling < 1000 {
                score -= 40
                factors.append(ConditionFactor(
                    category: .ceiling,
                    description: "Plafond très bas (\(ceiling) ft)",
                    impact: .critical,
                    points: -40
                ))
                restrictions.append("Plafond bas - Vol VFR déconseillé")
            } else if ceiling < 3000 {
                score -= 20
                factors.append(ConditionFactor(
                    category: .ceiling,
                    description: "Plafond bas (\(ceiling) ft)",
                    impact: .negative,
                    points: -20
                ))
            }
        } else {
            factors.append(ConditionFactor(
                category: .ceiling,
                description: "Pas de plafond nuageux",
                impact: .positive,
                points: 0
            ))
        }

        // Temperature spread (fog risk)
        let spread = metar.temperature.celsius - metar.dewpoint
        if spread < 2.0 {
            score -= 15
            factors.append(ConditionFactor(
                category: .fog,
                description: "Risque de brouillard (écart T-Td: \(String(format: "%.1f", spread))°C)",
                impact: .negative,
                points: -15
            ))
            restrictions.append("Surveiller évolution brouillard")
        }

        // Weather phenomena
        for phenomenon in metar.weatherPhenomena {
            switch phenomenon.intensity {
            case .heavy:
                score -= 30
                factors.append(ConditionFactor(
                    category: .precipitation,
                    description: "\(phenomenon.description) intense",
                    impact: .critical,
                    points: -30
                ))
                restrictions.append("Précipitations intenses")
            case .moderate:
                score -= 15
                factors.append(ConditionFactor(
                    category: .precipitation,
                    description: "\(phenomenon.description) modéré",
                    impact: .negative,
                    points: -15
                ))
            case .light:
                score -= 5
                factors.append(ConditionFactor(
                    category: .precipitation,
                    description: "\(phenomenon.description) léger",
                    impact: .caution,
                    points: -5
                ))
            case .vicinity:
                factors.append(ConditionFactor(
                    category: .precipitation,
                    description: "\(phenomenon.description) à proximité",
                    impact: .caution,
                    points: 0
                ))
            }

            // Thunderstorms
            if phenomenon.descriptor == "TS" {
                score -= 50
                restrictions.append("ORAGE - Vol interdit")
            }
        }

        // Determine overall status
        let status: WindowStatus
        if score >= 80 {
            status = .excellent
        } else if score >= 60 {
            status = .good
        } else if score >= 40 {
            status = .acceptable
        } else if score >= 20 {
            status = .marginal
        } else {
            status = .poor
        }

        return WindowConditions(
            timestamp: Date(),
            score: max(0, score),
            status: status,
            flightRules: metar.flightRules,
            visibility: metar.visibility.value,
            ceiling: lowestCeiling,
            windSpeed: windSpeed,
            gustSpeed: gustSpeed > 0 ? gustSpeed : nil,
            temperature: metar.temperature.celsius,
            dewpoint: metar.dewpoint,
            factors: factors,
            restrictions: restrictions
        )
    }

    // MARK: - Flight Windows Generation

    private func generateFlightWindows(
        aerodrome: Aerodrome,
        metar: METAR,
        taf: TAF?,
        flightType: FlightType
    ) async throws -> [FlightWindow] {
        var windows: [FlightWindow] = []

        guard let taf = taf else {
            // Sans TAF, on ne peut analyser que les conditions actuelles
            let currentWindow = FlightWindow(
                startTime: Date(),
                endTime: Date().addingTimeInterval(3600),
                conditions: analyzeCurrentConditions(metar: metar, aerodrome: aerodrome),
                score: currentConditions?.score ?? 50,
                isRecommended: (currentConditions?.score ?? 0) >= 60,
                duration: 60,
                flightType: flightType
            )
            return [currentWindow]
        }

        // Analyser chaque période TAF
        for (index, forecast) in taf.forecasts.prefix(24).enumerated() {
            // Créer un METAR simulé pour cette période
            let simulatedMETAR = createSimulatedMETAR(from: forecast, baseMetar: metar)

            // Analyser les conditions
            let conditions = analyzeCurrentConditions(metar: simulatedMETAR, aerodrome: aerodrome)

            // Calculer la durée de la fenêtre
            let nextForecast = taf.forecasts.indices.contains(index + 1) ? taf.forecasts[index + 1] : nil
            let endTime = nextForecast?.startTime ?? forecast.startTime.addingTimeInterval(3600)
            let duration = Int(endTime.timeIntervalSince(forecast.startTime) / 60)

            // Ajuster le score selon le type de vol
            var adjustedScore = conditions.score
            adjustedScore = adjustScoreForFlightType(score: adjustedScore, conditions: conditions, flightType: flightType)

            // Créer la fenêtre
            let window = FlightWindow(
                startTime: forecast.startTime,
                endTime: endTime,
                conditions: conditions,
                score: adjustedScore,
                isRecommended: adjustedScore >= searchConfig.minimumScore,
                duration: duration,
                flightType: flightType
            )

            windows.append(window)
        }

        return windows
    }

    private func createSimulatedMETAR(from forecast: TAF.Forecast, baseMetar: METAR) -> METAR {
        // Créer un METAR simulé basé sur les prévisions TAF
        return METAR(
            station: baseMetar.station,
            observationTime: forecast.startTime,
            rawText: "SIMULATED",
            flightRules: forecast.flightRules ?? baseMetar.flightRules,
            wind: forecast.wind,
            visibility: forecast.visibility ?? baseMetar.visibility,
            weatherPhenomena: forecast.weatherPhenomena,
            clouds: forecast.clouds,
            temperature: baseMetar.temperature, // TAF n'a pas toujours la température
            dewpoint: baseMetar.dewpoint,
            altimeter: baseMetar.altimeter,
            remarks: nil
        )
    }

    private func adjustScoreForFlightType(score: Int, conditions: WindowConditions, flightType: FlightType) -> Int {
        var adjusted = score

        switch flightType {
        case .vfr:
            // VFR nécessite de bonnes conditions visuelles
            if conditions.flightRules == .ifr || conditions.flightRules == .lifr {
                adjusted = 0 // Impossible
            } else if conditions.flightRules == .mvfr {
                adjusted -= 20
            }

        case .ifr:
            // IFR est plus tolérant aux conditions météo
            if conditions.flightRules == .mvfr {
                adjusted -= 5 // Peu d'impact
            }

        case .student:
            // Élève pilote nécessite des conditions excellentes
            if conditions.status != .excellent && conditions.status != .good {
                adjusted -= 30
            }
            if let gust = conditions.gustSpeed, gust > 10 {
                adjusted -= 20
            }

        case .crossCountry:
            // Vol de navigation nécessite bonne visibilité
            if conditions.visibility < 5.0 {
                adjusted -= 25
            }
            if conditions.ceiling != nil && conditions.ceiling! < 3000 {
                adjusted -= 20
            }

        case .training:
            // Vol d'entraînement local moins exigeant
            if conditions.status == .poor {
                adjusted -= 20
            }
        }

        return max(0, min(100, adjusted))
    }

    // MARK: - Recommendations

    func getRecommendations(windows: [FlightWindow]) -> [WindowRecommendation] {
        var recommendations: [WindowRecommendation] = []

        // Trouver la meilleure fenêtre immédiate (dans les 3 prochaines heures)
        let now = Date()
        let immediateWindows = windows.filter {
            $0.startTime.timeIntervalSince(now) <= 3 * 3600 && $0.startTime >= now
        }

        if let bestImmediate = immediateWindows.max(by: { $0.score < $1.score }), bestImmediate.isRecommended {
            recommendations.append(WindowRecommendation(
                type: .immediate,
                title: "Décollage immédiat possible",
                message: "Fenêtre favorable dans \(relativeTime(bestImmediate.startTime)) avec score \(bestImmediate.score)/100",
                window: bestImmediate,
                priority: .high
            ))
        }

        // Trouver la meilleure fenêtre globale
        if let best = windows.max(by: { $0.score < $1.score }), best.isRecommended {
            recommendations.append(WindowRecommendation(
                type: .optimal,
                title: "Fenêtre optimale",
                message: "Meilleures conditions \(relativeTime(best.startTime)) (score \(best.score)/100, durée \(best.duration) min)",
                window: best,
                priority: .high
            ))
        }

        // Avertir des périodes dangereuses
        let dangerousWindows = windows.filter { $0.score < 30 }
        if !dangerousWindows.isEmpty {
            let times = dangerousWindows.map { relativeTime($0.startTime) }.joined(separator: ", ")
            recommendations.append(WindowRecommendation(
                type: .warning,
                title: "⚠️ Périodes à éviter",
                message: "Conditions défavorables : \(times)",
                window: nil,
                priority: .high
            ))
        }

        // Détection de dégradation
        if windows.count >= 2 {
            let current = windows[0]
            let next = windows[1]
            if next.score < current.score - 20 {
                recommendations.append(WindowRecommendation(
                    type: .warning,
                    title: "Dégradation prévue",
                    message: "Les conditions vont se dégrader \(relativeTime(next.startTime))",
                    window: next,
                    priority: .medium
                ))
            }
        }

        // Détection d'amélioration
        if let poor = windows.first(where: { $0.status == .poor || $0.status == .marginal }),
           let improvement = windows.first(where: {
               $0.startTime > poor.startTime && $0.status == .excellent || $0.status == .good
           }) {
            recommendations.append(WindowRecommendation(
                type: .info,
                title: "Amélioration prévue",
                message: "Conditions s'améliorent \(relativeTime(improvement.startTime))",
                window: improvement,
                priority: .low
            ))
        }

        return recommendations.sorted { $0.priority.rawValue < $1.priority.rawValue }
    }

    // MARK: - Helper Methods

    private func relativeTime(_ date: Date) -> String {
        let interval = date.timeIntervalSince(Date())
        let hours = Int(interval / 3600)

        if hours < 0 {
            return "maintenant"
        } else if hours == 0 {
            let minutes = Int(interval / 60)
            return "dans \(minutes) min"
        } else if hours < 24 {
            return "dans \(hours)h"
        } else {
            let days = hours / 24
            return "dans \(days)j"
        }
    }
}

// MARK: - Models

struct FlightWindow: Identifiable {
    let id = UUID()
    let startTime: Date
    let endTime: Date
    let conditions: WindowConditions
    let score: Int
    let isRecommended: Bool
    let duration: Int  // minutes
    let flightType: FlightType

    var status: WindowStatus {
        conditions.status
    }

    var timeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }

    var formattedDuration: String {
        if duration >= 60 {
            let hours = duration / 60
            let mins = duration % 60
            return mins > 0 ? "\(hours)h\(mins)" : "\(hours)h"
        } else {
            return "\(duration) min"
        }
    }
}

struct WindowConditions {
    let timestamp: Date
    let score: Int
    let status: WindowStatus
    let flightRules: FlightRules
    let visibility: Double       // SM
    let ceiling: Int?            // feet
    let windSpeed: Int           // knots
    let gustSpeed: Int?          // knots
    let temperature: Double      // °C
    let dewpoint: Double         // °C
    let factors: [ConditionFactor]
    let restrictions: [String]

    var spread: Double {
        temperature - dewpoint
    }
}

enum WindowStatus: Int, Comparable {
    case poor = 0
    case marginal = 1
    case acceptable = 2
    case good = 3
    case excellent = 4

    static func < (lhs: WindowStatus, rhs: WindowStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var description: String {
        switch self {
        case .poor: return "Médiocre"
        case .marginal: return "Marginal"
        case .acceptable: return "Acceptable"
        case .good: return "Bon"
        case .excellent: return "Excellent"
        }
    }

    var color: String {
        switch self {
        case .poor: return "red"
        case .marginal: return "orange"
        case .acceptable: return "yellow"
        case .good: return "lightGreen"
        case .excellent: return "green"
        }
    }

    var emoji: String {
        switch self {
        case .poor: return "🔴"
        case .marginal: return "🟠"
        case .acceptable: return "🟡"
        case .good: return "🟢"
        case .excellent: return "✅"
        }
    }
}

struct ConditionFactor {
    let category: FactorCategory
    let description: String
    let impact: FactorImpact
    let points: Int

    enum FactorCategory {
        case flightRules
        case visibility
        case ceiling
        case wind
        case precipitation
        case fog
        case icing
        case other
    }

    enum FactorImpact {
        case positive
        case neutral
        case caution
        case negative
        case critical

        var color: String {
            switch self {
            case .positive: return "green"
            case .neutral: return "gray"
            case .caution: return "yellow"
            case .negative: return "orange"
            case .critical: return "red"
            }
        }

        var icon: String {
            switch self {
            case .positive: return "checkmark.circle.fill"
            case .neutral: return "minus.circle.fill"
            case .caution: return "exclamationmark.triangle.fill"
            case .negative: return "xmark.circle.fill"
            case .critical: return "xmark.octagon.fill"
            }
        }
    }
}

enum FlightType: String, CaseIterable {
    case vfr = "VFR"
    case ifr = "IFR"
    case student = "Élève Pilote"
    case crossCountry = "Navigation"
    case training = "Local/Entraînement"

    var icon: String {
        switch self {
        case .vfr: return "eye"
        case .ifr: return "gauge"
        case .student: return "graduationcap"
        case .crossCountry: return "map"
        case .training: return "arrow.triangle.2.circlepath"
        }
    }
}

struct SearchConfig {
    var minimumScore: Int           // Score minimum pour recommandation
    var minimumDuration: Int        // Durée minimum de fenêtre (minutes)
    var maxWindSpeed: Int           // Vent max acceptable (kt)
    var minVisibility: Double       // Visibilité min (SM)
    var minCeiling: Int             // Plafond min (ft)

    static let `default` = SearchConfig(
        minimumScore: 60,
        minimumDuration: 60,
        maxWindSpeed: 25,
        minVisibility: 3.0,
        minCeiling: 1500
    )

    static let student = SearchConfig(
        minimumScore: 80,
        minimumDuration: 120,
        maxWindSpeed: 15,
        minVisibility: 5.0,
        minCeiling: 3000
    )

    static let relaxed = SearchConfig(
        minimumScore: 40,
        minimumDuration: 30,
        maxWindSpeed: 35,
        minVisibility: 1.0,
        minCeiling: 500
    )
}

struct WindowRecommendation: Identifiable {
    let id = UUID()
    let type: RecommendationType
    let title: String
    let message: String
    let window: FlightWindow?
    let priority: Priority

    enum RecommendationType {
        case immediate
        case optimal
        case warning
        case info

        var icon: String {
            switch self {
            case .immediate: return "airplane.departure"
            case .optimal: return "star.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: String {
            switch self {
            case .immediate: return "blue"
            case .optimal: return "green"
            case .warning: return "orange"
            case .info: return "gray"
            }
        }
    }

    enum Priority: Int {
        case high = 0
        case medium = 1
        case low = 2
    }
}

// MARK: - Errors

enum FlightWindowError: LocalizedError {
    case noData
    case analysisError(String)

    var errorDescription: String? {
        switch self {
        case .noData:
            return "Aucune donnée disponible"
        case .analysisError(let message):
            return "Erreur d'analyse: \(message)"
        }
    }
}
