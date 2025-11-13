//
//  CrosswindAnalysisService.swift
//  Cirrus
//
//  Service d'analyse crosswind multi-pistes temps réel
//

import Foundation

@MainActor
class CrosswindAnalysisService: ObservableObject {
    static let shared = CrosswindAnalysisService()

    @Published var runwayAnalysis: [RunwayAnalysis] = []
    @Published var recommendedRunway: RunwayAnalysis?
    @Published var hourlyForecasts: [HourlyRunwayForecast] = []
    @Published var isLoading = false
    @Published var error: CrosswindError?

    // Configuration avion par défaut
    var aircraftConfig = AircraftConfig.default

    private init() {}

    // MARK: - Public Methods

    func analyzeRunways(
        aerodrome: Aerodrome,
        metar: METAR,
        taf: TAF? = nil
    ) async {
        isLoading = true
        error = nil

        // Analyser chaque piste
        var analyses: [RunwayAnalysis] = []

        for runway in aerodrome.runways {
            let analysis = analyzeRunway(
                runway: runway,
                windDirection: metar.wind.direction ?? 0,
                windSpeed: metar.wind.speed,
                gustSpeed: metar.wind.gust,
                aircraftConfig: aircraftConfig
            )
            analyses.append(analysis)
        }

        // Trier par score (meilleur en premier)
        analyses.sort { $0.score > $1.score }

        self.runwayAnalysis = analyses
        self.recommendedRunway = analyses.first

        // Générer les prévisions horaires si TAF disponible
        if let taf = taf {
            self.hourlyForecasts = await generateHourlyForecasts(
                aerodrome: aerodrome,
                taf: taf
            )
        }

        isLoading = false
    }

    // MARK: - Runway Analysis

    private func analyzeRunway(
        runway: Aerodrome.Runway,
        windDirection: Int,
        windSpeed: Int,
        gustSpeed: Int?,
        aircraftConfig: AircraftConfig
    ) -> RunwayAnalysis {
        // Extraire l'orientation de la piste
        let runwayHeading = extractRunwayHeading(runway.name)

        // Calculer les composantes de vent
        let windComponents = AviationCalculations.calculateWindComponents(
            windDirection: windDirection,
            windSpeed: windSpeed,
            runwayHeading: runwayHeading
        )

        // Calculer avec rafales si présent
        var gustComponents: WindComponents?
        if let gust = gustSpeed {
            gustComponents = AviationCalculations.calculateWindComponents(
                windDirection: windDirection,
                windSpeed: gust,
                runwayHeading: runwayHeading
            )
        }

        // Déterminer le statut selon les limites
        let status = determineRunwayStatus(
            crosswind: windComponents.crosswind,
            gustCrosswind: gustComponents?.crosswind,
            headwind: windComponents.headwind,
            aircraftConfig: aircraftConfig
        )

        // Calculer un score (0-100)
        let score = calculateRunwayScore(
            components: windComponents,
            gustComponents: gustComponents,
            status: status
        )

        return RunwayAnalysis(
            runway: runway,
            windComponents: windComponents,
            gustComponents: gustComponents,
            status: status,
            score: score,
            aircraftLimits: aircraftConfig
        )
    }

    private func determineRunwayStatus(
        crosswind: Double,
        gustCrosswind: Double?,
        headwind: Double,
        aircraftConfig: AircraftConfig
    ) -> RunwayStatus {
        let effectiveCrosswind = gustCrosswind ?? crosswind

        // Vérifier vent arrière
        if headwind < -5 {
            return .tailwind
        }

        // Vérifier crosswind par rapport aux limites
        if effectiveCrosswind > aircraftConfig.maxCrosswind {
            return .exceedsLimits
        } else if effectiveCrosswind > aircraftConfig.demonstratedCrosswind {
            return .aboveDemonstrated
        } else if effectiveCrosswind > 10 {
            return .caution
        } else if effectiveCrosswind > 5 {
            return .acceptable
        } else {
            return .optimal
        }
    }

    private func calculateRunwayScore(
        components: WindComponents,
        gustComponents: WindComponents?,
        status: RunwayStatus
    ) -> Int {
        var score = 100

        // Pénalité pour crosswind
        score -= Int(components.crosswind * 2)

        // Pénalité supplémentaire pour les rafales
        if let gust = gustComponents {
            score -= Int((gust.crosswind - components.crosswind) * 3)
        }

        // Pénalité pour vent arrière
        if components.headwind < 0 {
            score -= Int(abs(components.headwind) * 5)
        }

        // Bonus pour vent de face
        if components.headwind > 0 {
            score += min(Int(components.headwind), 10)
        }

        // Ajustements selon le statut
        switch status {
        case .optimal: score += 10
        case .acceptable: score -= 5
        case .caution: score -= 15
        case .aboveDemonstrated: score -= 30
        case .exceedsLimits: score -= 50
        case .tailwind: score -= 40
        }

        return max(0, min(100, score))
    }

    // MARK: - Hourly Forecasts

    private func generateHourlyForecasts(
        aerodrome: Aerodrome,
        taf: TAF
    ) async -> [HourlyRunwayForecast] {
        var forecasts: [HourlyRunwayForecast] = []

        // Pour chaque période TAF
        for forecastPeriod in taf.forecasts.prefix(12) {
            // Analyser toutes les pistes pour cette période
            var runwayAnalyses: [RunwayAnalysis] = []

            for runway in aerodrome.runways {
                let analysis = analyzeRunway(
                    runway: runway,
                    windDirection: forecastPeriod.wind.direction ?? 0,
                    windSpeed: forecastPeriod.wind.speed,
                    gustSpeed: forecastPeriod.wind.gust,
                    aircraftConfig: aircraftConfig
                )
                runwayAnalyses.append(analysis)
            }

            // Trouver la meilleure piste pour cette période
            let bestRunway = runwayAnalyses.max(by: { $0.score < $1.score })

            forecasts.append(HourlyRunwayForecast(
                time: forecastPeriod.startTime,
                windDirection: forecastPeriod.wind.direction ?? 0,
                windSpeed: forecastPeriod.wind.speed,
                gustSpeed: forecastPeriod.wind.gust,
                bestRunway: bestRunway
            ))
        }

        return forecasts
    }

    // MARK: - Helper Methods

    private func extractRunwayHeading(_ runwayName: String) -> Int {
        // Extraire les chiffres du nom de piste (ex: "09L" -> 09, "27R" -> 27)
        let digits = runwayName.prefix(2)
        if let heading = Int(digits) {
            return heading * 10
        }
        return 0
    }

    func getOppositeRunway(_ runwayName: String) -> String {
        let digits = runwayName.prefix(2)
        let suffix = runwayName.dropFirst(2)

        if let number = Int(digits) {
            let opposite = (number + 18) % 36
            let oppositeStr = String(format: "%02d", opposite == 0 ? 36 : opposite)

            // Inverser le suffixe (L <-> R, C reste C)
            var oppositeSuffix = ""
            if suffix == "L" {
                oppositeSuffix = "R"
            } else if suffix == "R" {
                oppositeSuffix = "L"
            } else {
                oppositeSuffix = String(suffix)
            }

            return oppositeStr + oppositeSuffix
        }

        return runwayName
    }
}

// MARK: - Models

struct RunwayAnalysis: Identifiable {
    let id = UUID()
    let runway: Aerodrome.Runway
    let windComponents: WindComponents
    let gustComponents: WindComponents?
    let status: RunwayStatus
    let score: Int
    let aircraftLimits: AircraftConfig

    var isRecommended: Bool {
        status == .optimal || status == .acceptable
    }

    var warningMessage: String? {
        switch status {
        case .aboveDemonstrated:
            return "⚠️ Au-dessus du vent de travers démontré (\(aircraftLimits.demonstratedCrosswind) kt)"
        case .exceedsLimits:
            return "⛔ Dépasse la limite de vent de travers (\(aircraftLimits.maxCrosswind) kt)"
        case .tailwind:
            return "⛔ Vent arrière - Piste non recommandée"
        case .caution:
            return "⚠️ Vent de travers significatif - Prudence"
        default:
            return nil
        }
    }
}

enum RunwayStatus: Int {
    case optimal = 5
    case acceptable = 4
    case caution = 3
    case aboveDemonstrated = 2
    case exceedsLimits = 1
    case tailwind = 0

    var description: String {
        switch self {
        case .optimal: return "Optimal"
        case .acceptable: return "Acceptable"
        case .caution: return "Prudence"
        case .aboveDemonstrated: return "Au-dessus démontré"
        case .exceedsLimits: return "Dépasse limites"
        case .tailwind: return "Vent arrière"
        }
    }

    var color: String {
        switch self {
        case .optimal: return "green"
        case .acceptable: return "lightGreen"
        case .caution: return "yellow"
        case .aboveDemonstrated: return "orange"
        case .exceedsLimits: return "red"
        case .tailwind: return "red"
        }
    }

    var emoji: String {
        switch self {
        case .optimal: return "✅"
        case .acceptable: return "🟢"
        case .caution: return "⚠️"
        case .aboveDemonstrated: return "🟠"
        case .exceedsLimits: return "🔴"
        case .tailwind: return "⛔"
        }
    }
}

struct AircraftConfig {
    var name: String
    var demonstratedCrosswind: Double  // kt
    var maxCrosswind: Double           // kt
    var maxTailwind: Double            // kt

    static let `default` = AircraftConfig(
        name: "Avion léger standard",
        demonstratedCrosswind: 15,
        maxCrosswind: 20,
        maxTailwind: 5
    )

    static let presets: [AircraftConfig] = [
        AircraftConfig(name: "Cessna 152/172", demonstratedCrosswind: 15, maxCrosswind: 20, maxTailwind: 5),
        AircraftConfig(name: "Piper PA-28", demonstratedCrosswind: 17, maxCrosswind: 22, maxTailwind: 5),
        AircraftConfig(name: "Diamond DA40", demonstratedCrosswind: 18, maxCrosswind: 23, maxTailwind: 5),
        AircraftConfig(name: "Robin DR400", demonstratedCrosswind: 16, maxCrosswind: 21, maxTailwind: 5),
        AircraftConfig(name: "Cirrus SR20/22", demonstratedCrosswind: 20, maxCrosswind: 25, maxTailwind: 5)
    ]
}

struct HourlyRunwayForecast: Identifiable {
    let id = UUID()
    let time: Date
    let windDirection: Int
    let windSpeed: Int
    let gustSpeed: Int?
    let bestRunway: RunwayAnalysis?

    var timeFormatted: String {
        time.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Errors

enum CrosswindError: LocalizedError {
    case noRunways
    case invalidData
    case analysisError(String)

    var errorDescription: String? {
        switch self {
        case .noRunways:
            return "Aucune piste disponible pour cet aérodrome"
        case .invalidData:
            return "Données invalides"
        case .analysisError(let message):
            return "Erreur d'analyse: \(message)"
        }
    }
}
