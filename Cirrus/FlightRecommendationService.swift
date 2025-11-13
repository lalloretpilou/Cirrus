//
//  FlightRecommendationService.swift
//  Cirrus
//
//  Intelligent flight recommendation system for pilots
//

import Foundation
import CoreLocation
import WeatherKit

@MainActor
class FlightRecommendationService: ObservableObject {
    static let shared = FlightRecommendationService()

    @Published var currentRecommendation: FlightRecommendation?
    @Published var hourlyRecommendations: [HourlyRecommendation] = []

    private init() {}

    // MARK: - Main Recommendation Engine

    func generateRecommendation(
        metar: METAR,
        taf: TAF?,
        windsAloft: WindsAloft?,
        aerodrome: Aerodrome,
        weather: Weather? = nil
    ) -> FlightRecommendation {
        // Analyze current conditions
        let conditions = analyzeConditions(from: metar, aerodrome: aerodrome)

        // Determine flight type recommendation
        let flightType = determineFlightType(from: metar, conditions: conditions)

        // Calculate optimal altitude
        let recommendedAltitude = calculateOptimalAltitude(
            metar: metar,
            windsAloft: windsAloft,
            taf: taf
        )

        // Find optimal departure window
        let departureWindow = findOptimalDepartureWindow(
            taf: taf,
            currentConditions: metar,
            hoursAhead: 12
        )

        // Generate warnings
        let warnings = generateWarnings(
            metar: metar,
            conditions: conditions,
            aerodrome: aerodrome,
            windsAloft: windsAloft
        )

        // Identify favorable factors
        let favorableFactors = identifyFavorableFactors(
            metar: metar,
            conditions: conditions,
            windsAloft: windsAloft
        )

        let recommendation = FlightRecommendation(
            recommendedAltitude: recommendedAltitude,
            flightType: flightType,
            optimalDepartureWindow: departureWindow,
            conditions: conditions,
            warnings: warnings,
            favorableFactors: favorableFactors
        )

        self.currentRecommendation = recommendation
        return recommendation
    }

    // MARK: - Hourly Forecast Analysis

    func generateHourlyRecommendations(
        taf: TAF,
        aerodrome: Aerodrome,
        hoursAhead: Int = 24
    ) -> [HourlyRecommendation] {
        var recommendations: [HourlyRecommendation] = []

        for forecast in taf.forecasts.prefix(hoursAhead) {
            let ceiling = forecast.clouds.first(where: { $0.coverage == .broken || $0.coverage == .overcast })?.altitude
            let visibility = forecast.visibility.value

            let flightRules = AviationCalculations.determineFlightRules(
                ceiling: ceiling,
                visibility: visibility
            )

            let windSpeed = forecast.wind.speed
            let gustSpeed = forecast.wind.gust

            let score = calculateFlightScore(
                flightRules: flightRules,
                windSpeed: windSpeed,
                gustSpeed: gustSpeed,
                visibility: visibility,
                ceiling: ceiling
            )

            let recommendation = HourlyRecommendation(
                time: forecast.startTime,
                flightRules: flightRules,
                score: score,
                ceiling: ceiling,
                visibility: visibility,
                windSpeed: windSpeed,
                gustSpeed: gustSpeed,
                suitability: determineSuitability(score: score)
            )

            recommendations.append(recommendation)
        }

        self.hourlyRecommendations = recommendations
        return recommendations
    }

    // MARK: - Private Helper Methods

    private func analyzeConditions(from metar: METAR, aerodrome: Aerodrome) -> FlightRecommendation.Conditions {
        let ceiling = metar.clouds.first(where: { $0.coverage == .broken || $0.coverage == .overcast })?.altitude
        let visibility = metar.visibility.value
        let windSpeed = metar.wind.speed
        let gustSpeed = metar.wind.gust

        // Analyze turbulence likelihood
        let turbulenceLevel = analyzeTurbulence(
            windSpeed: windSpeed,
            gustSpeed: gustSpeed,
            temperature: metar.temperature.celsius,
            elevation: aerodrome.elevation
        )

        // Analyze icing likelihood
        let icingLevel = analyzeIcing(
            temperature: metar.temperature.celsius,
            dewpoint: metar.dewpoint,
            clouds: metar.clouds
        )

        return FlightRecommendation.Conditions(
            ceiling: ceiling,
            visibility: visibility,
            windSpeed: windSpeed,
            gustSpeed: gustSpeed,
            turbulenceLevel: turbulenceLevel,
            icingLevel: icingLevel,
            flightRules: metar.flightRules
        )
    }

    private func determineFlightType(
        from metar: METAR,
        conditions: FlightRecommendation.Conditions
    ) -> FlightRecommendation.RecommendedFlightType {
        let flightRules = metar.flightRules
        let windSpeed = conditions.windSpeed
        let gustSpeed = conditions.gustSpeed ?? 0
        let visibility = conditions.visibility

        // Check for severe conditions
        if flightRules == .lifr || windSpeed > 30 || gustSpeed > 40 {
            return .notRecommended
        }

        // Check for IFR conditions
        if flightRules == .ifr {
            return .ifrOnly
        }

        // Check for marginal VFR
        if flightRules == .mvfr || windSpeed > 20 || gustSpeed > 25 {
            return .vfrCaution
        }

        // Check for thunderstorms
        if metar.weatherPhenomena.contains(where: { $0.descriptor == .thunderstorm }) {
            return .notRecommended
        }

        // Check for icing
        if conditions.icingLevel != "Nul" {
            return .vfrCaution
        }

        // Good VFR conditions
        return .vfrRecommended
    }

    private func calculateOptimalAltitude(
        metar: METAR,
        windsAloft: WindsAloft?,
        taf: TAF?
    ) -> FlightRecommendation.AltitudeRange {
        // Calculate minimum altitude (1000 ft above highest cloud layer)
        let highestCloud = metar.clouds.max(by: { $0.altitude < $1.altitude })
        let cloudClearance = (highestCloud?.altitude ?? 0) + 1000

        // VFR minimum: 3000 ft AGL or above clouds + 1000 ft
        let vfrMinimum = max(3000, cloudClearance)

        // Find altitude with best winds if available
        var optimalAltitude = 5500 // Default VFR cruising altitude (eastbound)

        if let winds = windsAloft {
            // Find level with lowest headwind or best tailwind
            optimalAltitude = findBestWindLevel(winds: winds, minimumAltitude: vfrMinimum)
        }

        // Ensure odd altitude for eastbound VFR (or even for westbound)
        optimalAltitude = roundToVFRAltitude(optimalAltitude)

        // Maximum recommended altitude (considering oxygen requirements)
        let maximumAltitude = 10000 // Below 12,500 ft MSL (no oxygen required for <= 30 min)

        let reason = generateAltitudeReason(
            optimal: optimalAltitude,
            cloudClearance: cloudClearance,
            winds: windsAloft
        )

        return FlightRecommendation.AltitudeRange(
            minimum: vfrMinimum,
            optimal: optimalAltitude,
            maximum: maximumAltitude,
            reason: reason
        )
    }

    private func findOptimalDepartureWindow(
        taf: TAF?,
        currentConditions: METAR,
        hoursAhead: Int
    ) -> DateInterval? {
        guard let taf = taf else { return nil }

        var bestPeriods: [(period: TAF.ForecastPeriod, score: Double)] = []

        for forecast in taf.forecasts {
            let ceiling = forecast.clouds.first(where: { $0.coverage == .broken || $0.coverage == .overcast })?.altitude
            let visibility = forecast.visibility.value
            let windSpeed = forecast.wind.speed
            let gustSpeed = forecast.wind.gust

            let flightRules = AviationCalculations.determineFlightRules(
                ceiling: ceiling,
                visibility: visibility
            )

            let score = calculateFlightScore(
                flightRules: flightRules,
                windSpeed: windSpeed,
                gustSpeed: gustSpeed,
                visibility: visibility,
                ceiling: ceiling
            )

            // Only consider periods with good enough scores
            if score >= 6.0 {
                bestPeriods.append((forecast, score))
            }
        }

        // Find the best continuous window
        guard let bestPeriod = bestPeriods.max(by: { $0.score < $1.score }) else {
            return nil
        }

        return DateInterval(start: bestPeriod.period.startTime, end: bestPeriod.period.endTime)
    }

    private func generateWarnings(
        metar: METAR,
        conditions: FlightRecommendation.Conditions,
        aerodrome: Aerodrome,
        windsAloft: WindsAloft?
    ) -> [FlightRecommendation.Warning] {
        var warnings: [FlightRecommendation.Warning] = []

        // Wind warnings
        if conditions.windSpeed > 20 {
            warnings.append(FlightRecommendation.Warning(
                type: .wind,
                message: "Vents forts: \(conditions.windSpeed) kt",
                severity: conditions.windSpeed > 30 ? .severe : .moderate
            ))
        }

        if let gust = conditions.gustSpeed, gust > 15 {
            warnings.append(FlightRecommendation.Warning(
                type: .wind,
                message: "Rafales: \(gust) kt",
                severity: gust > 25 ? .severe : .moderate
            ))
        }

        // Visibility warnings
        if conditions.visibility < 5 {
            warnings.append(FlightRecommendation.Warning(
                type: .visibility,
                message: "Visibilité réduite: \(String(format: "%.1f", conditions.visibility)) SM",
                severity: conditions.visibility < 3 ? .severe : .moderate
            ))
        }

        // Ceiling warnings
        if let ceiling = conditions.ceiling, ceiling < 3000 {
            warnings.append(FlightRecommendation.Warning(
                type: .ceiling,
                message: "Plafond bas: \(ceiling) ft AGL",
                severity: ceiling < 1000 ? .severe : .moderate
            ))
        }

        // Turbulence warnings
        if conditions.turbulenceLevel != "Nul" {
            warnings.append(FlightRecommendation.Warning(
                type: .turbulence,
                message: "Turbulence \(conditions.turbulenceLevel.lowercased())",
                severity: conditions.turbulenceLevel == "Forte" ? .severe : .moderate
            ))
        }

        // Icing warnings
        if conditions.icingLevel != "Nul" {
            warnings.append(FlightRecommendation.Warning(
                type: .icing,
                message: "Risque de givrage \(conditions.icingLevel.lowercased())",
                severity: conditions.icingLevel == "Sévère" ? .severe : .moderate
            ))
        }

        // Thunderstorm warnings
        if metar.weatherPhenomena.contains(where: { $0.descriptor == .thunderstorm }) {
            warnings.append(FlightRecommendation.Warning(
                type: .thunderstorm,
                message: "Orages présents ou à proximité",
                severity: .severe
            ))
        }

        // Calculate crosswind for main runway (if available)
        if let mainRunway = aerodrome.runways.first {
            let runwayHeading = extractRunwayHeading(mainRunway.name)
            let windComponents = AviationCalculations.calculateWindComponents(
                windDirection: metar.wind.direction ?? 0,
                windSpeed: metar.wind.speed,
                runwayHeading: runwayHeading
            )

            if windComponents.crosswind > 10 {
                warnings.append(FlightRecommendation.Warning(
                    type: .crosswind,
                    message: "Vent de travers sur piste \(mainRunway.name): \(Int(windComponents.crosswind)) kt",
                    severity: windComponents.crosswind > 15 ? .severe : .moderate
                ))
            }

            if windComponents.headwind < -5 {
                warnings.append(FlightRecommendation.Warning(
                    type: .tailwind,
                    message: "Vent arrière sur piste \(mainRunway.name): \(Int(abs(windComponents.headwind))) kt",
                    severity: abs(windComponents.headwind) > 10 ? .severe : .moderate
                ))
            }
        }

        return warnings
    }

    private func identifyFavorableFactors(
        metar: METAR,
        conditions: FlightRecommendation.Conditions,
        windsAloft: WindsAloft?
    ) -> [String] {
        var factors: [String] = []

        // Good visibility
        if conditions.visibility >= 10 {
            factors.append("✅ Excellente visibilité (\(Int(conditions.visibility)) SM)")
        }

        // High ceilings
        if let ceiling = conditions.ceiling, ceiling > 5000 {
            factors.append("✅ Plafond élevé (\(ceiling) ft)")
        } else if conditions.ceiling == nil {
            factors.append("✅ Ciel dégagé ou peu de nuages")
        }

        // Light winds
        if conditions.windSpeed < 10 {
            factors.append("✅ Vents calmes (\(conditions.windSpeed) kt)")
        }

        // No gusts
        if conditions.gustSpeed == nil || conditions.gustSpeed! < 5 {
            factors.append("✅ Pas de rafales significatives")
        }

        // Good flight rules
        if metar.flightRules == .vfr {
            factors.append("✅ Conditions VFR")
        }

        // No turbulence
        if conditions.turbulenceLevel == "Nul" {
            factors.append("✅ Pas de turbulence prévue")
        }

        // No icing
        if conditions.icingLevel == "Nul" {
            factors.append("✅ Pas de risque de givrage")
        }

        // Temperature in comfortable range
        let temp = metar.temperature.celsius
        if temp >= 10 && temp <= 25 {
            factors.append("✅ Température agréable (\(Int(temp))°C)")
        }

        // Good pressure
        if metar.altimeter.inHg > 29.80 && metar.altimeter.inHg < 30.20 {
            factors.append("✅ Pression atmosphérique stable")
        }

        return factors
    }

    private func analyzeTurbulence(
        windSpeed: Int,
        gustSpeed: Int?,
        temperature: Double,
        elevation: Int
    ) -> String {
        var turbulenceScore = 0

        // Wind-based turbulence
        if windSpeed > 25 { turbulenceScore += 2 }
        else if windSpeed > 15 { turbulenceScore += 1 }

        // Gust-based turbulence
        if let gust = gustSpeed {
            let gustSpread = gust - windSpeed
            if gustSpread > 15 { turbulenceScore += 2 }
            else if gustSpread > 10 { turbulenceScore += 1 }
        }

        // Temperature-based (convective turbulence on hot days)
        if temperature > 25 { turbulenceScore += 1 }
        if temperature > 30 { turbulenceScore += 1 }

        // Mountain effects
        if elevation > 3000 { turbulenceScore += 1 }

        switch turbulenceScore {
        case 0: return "Nul"
        case 1...2: return "Légère"
        case 3...4: return "Modérée"
        default: return "Forte"
        }
    }

    private func analyzeIcing(
        temperature: Double,
        dewpoint: Double,
        clouds: [METAR.CloudLayer]
    ) -> String {
        // Icing typically occurs between 0°C and -20°C with visible moisture
        guard temperature <= 0 && temperature >= -20 else {
            return "Nul"
        }

        let spread = temperature - dewpoint

        // High humidity + freezing = icing risk
        if spread < 3 && !clouds.isEmpty {
            if temperature >= -10 {
                return "Modéré à sévère" // Most severe icing in this range
            } else {
                return "Léger à modéré"
            }
        } else if spread < 5 {
            return "Léger"
        }

        return "Nul"
    }

    private func findBestWindLevel(winds: WindsAloft, minimumAltitude: Int) -> Int {
        let availableLevels = winds.levels.filter { $0.altitude >= minimumAltitude }

        guard let bestLevel = availableLevels.min(by: { $0.speed < $1.speed }) else {
            return minimumAltitude
        }

        return bestLevel.altitude
    }

    private func roundToVFRAltitude(_ altitude: Int) -> Int {
        // VFR cruising altitudes: Eastbound (0-179°) = odd thousands + 500
        // For simplicity, we'll use odd thousands + 500
        let thousands = (altitude / 1000)
        let roundedThousands = thousands % 2 == 0 ? thousands + 1 : thousands
        return roundedThousands * 1000 + 500
    }

    private func generateAltitudeReason(
        optimal: Int,
        cloudClearance: Int,
        winds: WindsAloft?
    ) -> String {
        var reasons: [String] = []

        if cloudClearance > 1000 {
            reasons.append("Dégagement des nuages")
        }

        if let winds = winds {
            reasons.append("Vents favorables à cette altitude")
        }

        reasons.append("Altitude VFR réglementaire")

        return reasons.joined(separator: ", ")
    }

    private func calculateFlightScore(
        flightRules: FlightRules,
        windSpeed: Int,
        gustSpeed: Int?,
        visibility: Double,
        ceiling: Int?
    ) -> Double {
        var score = 0.0

        // Flight rules score (0-4 points)
        switch flightRules {
        case .vfr: score += 4
        case .mvfr: score += 2
        case .ifr: score += 1
        case .lifr: score += 0
        }

        // Wind score (0-3 points)
        if windSpeed < 10 { score += 3 }
        else if windSpeed < 15 { score += 2 }
        else if windSpeed < 20 { score += 1 }

        // Gust penalty
        if let gust = gustSpeed, gust > 20 {
            score -= 1
        }

        // Visibility score (0-2 points)
        if visibility >= 10 { score += 2 }
        else if visibility >= 5 { score += 1 }

        // Ceiling score (0-1 point)
        if let ceiling = ceiling {
            if ceiling > 5000 { score += 1 }
        } else {
            score += 1 // No ceiling = clear
        }

        return max(0, min(10, score))
    }

    private func determineSuitability(score: Double) -> String {
        switch score {
        case 8...10: return "Excellent"
        case 6..<8: return "Bon"
        case 4..<6: return "Acceptable"
        case 2..<4: return "Marginal"
        default: return "Déconseillé"
        }
    }

    private func extractRunwayHeading(_ runwayName: String) -> Int {
        // Extract heading from runway name (e.g., "09L" -> 090°, "27R" -> 270°)
        let digits = runwayName.prefix(2)
        if let heading = Int(digits) {
            return heading * 10
        }
        return 0
    }
}

// MARK: - Supporting Models

struct HourlyRecommendation: Identifiable {
    let id = UUID()
    let time: Date
    let flightRules: FlightRules
    let score: Double
    let ceiling: Int?
    let visibility: Double
    let windSpeed: Int
    let gustSpeed: Int?
    let suitability: String
}
