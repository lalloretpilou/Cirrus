//
//  RouteWeatherService.swift
//  Cirrus
//
//  Service de calcul des conditions météo en route
//

import Foundation
import CoreLocation
import WeatherKit

@MainActor
class RouteWeatherService: ObservableObject {
    static let shared = RouteWeatherService()

    @Published var routeSegments: [RouteSegment] = []
    @Published var routeSummary: RouteSummary?
    @Published var isLoading = false
    @Published var error: RouteWeatherError?

    // Configuration
    private let segmentDistance: Double = 10.0 // NM - Distance entre les points d'analyse
    private let weatherService = WeatherService.shared

    private init() {}

    // MARK: - Public Methods

    func analyzeRoute(
        from departure: RoutePoint,
        to arrival: RoutePoint,
        cruiseAltitude: Int = 5500
    ) async {
        isLoading = true
        error = nil

        do {
            // Calculer les points intermédiaires le long de la route
            let waypoints = calculateWaypoints(from: departure, to: arrival)

            // Analyser la météo à chaque point
            var segments: [RouteSegment] = []

            for (index, waypoint) in waypoints.enumerated() {
                let segment = try await analyzeSegment(
                    waypoint: waypoint,
                    segmentNumber: index + 1,
                    cruiseAltitude: cruiseAltitude
                )
                segments.append(segment)
            }

            self.routeSegments = segments

            // Générer le résumé de route
            self.routeSummary = generateRouteSummary(
                segments: segments,
                departure: departure,
                arrival: arrival,
                cruiseAltitude: cruiseAltitude
            )

            isLoading = false
        } catch {
            self.error = .analysisError(error.localizedDescription)
            isLoading = false
        }
    }

    // MARK: - Route Calculation

    private func calculateWaypoints(from departure: RoutePoint, to arrival: RoutePoint) -> [Waypoint] {
        var waypoints: [Waypoint] = []

        let departureCoord = departure.coordinate
        let arrivalCoord = arrival.coordinate

        // Calculer la distance totale
        let totalDistance = AviationCalculations.distanceNauticalMiles(
            from: departureCoord,
            to: arrivalCoord
        )

        // Calculer le bearing
        let bearing = AviationCalculations.bearing(
            from: departureCoord,
            to: arrivalCoord
        )

        // Nombre de segments
        let numberOfSegments = Int(ceil(totalDistance / segmentDistance))

        // Générer les waypoints
        for i in 0...numberOfSegments {
            let distance = min(Double(i) * segmentDistance, totalDistance)
            let coordinate = calculateCoordinate(
                from: departureCoord,
                bearing: bearing,
                distance: distance
            )

            let waypoint = Waypoint(
                coordinate: coordinate,
                distanceFromDeparture: distance,
                bearing: bearing
            )

            waypoints.append(waypoint)
        }

        return waypoints
    }

    private func calculateCoordinate(
        from start: CLLocationCoordinate2D,
        bearing: Double,
        distance: Double // Nautical miles
    ) -> CLLocationCoordinate2D {
        let distanceRadians = (distance * 1852.0) / 6371000.0 // Convertir en radians
        let bearingRadians = bearing * .pi / 180.0

        let lat1 = start.latitude * .pi / 180.0
        let lon1 = start.longitude * .pi / 180.0

        let lat2 = asin(
            sin(lat1) * cos(distanceRadians) +
            cos(lat1) * sin(distanceRadians) * cos(bearingRadians)
        )

        let lon2 = lon1 + atan2(
            sin(bearingRadians) * sin(distanceRadians) * cos(lat1),
            cos(distanceRadians) - sin(lat1) * sin(lat2)
        )

        return CLLocationCoordinate2D(
            latitude: lat2 * 180.0 / .pi,
            longitude: lon2 * 180.0 / .pi
        )
    }

    // MARK: - Segment Analysis

    private func analyzeSegment(
        waypoint: Waypoint,
        segmentNumber: Int,
        cruiseAltitude: Int
    ) async throws -> RouteSegment {
        // Récupérer les données météo pour ce point (utilisant WeatherKit)
        let location = CLLocation(latitude: waypoint.coordinate.latitude, longitude: waypoint.coordinate.longitude)

        // Dans une vraie implémentation, on utiliserait WeatherKit
        // Pour l'instant, simuler des données
        let conditions = try await fetchWeatherConditions(at: location)

        // Analyser les risques
        let hazards = analyzeHazards(conditions: conditions, altitude: cruiseAltitude)

        // Déterminer le statut du segment
        let status = determineSegmentStatus(conditions: conditions, hazards: hazards)

        return RouteSegment(
            segmentNumber: segmentNumber,
            waypoint: waypoint,
            conditions: conditions,
            hazards: hazards,
            status: status
        )
    }

    private func fetchWeatherConditions(at location: CLLocation) async throws -> WeatherConditions {
        // Simulation de conditions météo
        // Dans une vraie implémentation, utiliser WeatherKit ou API
        return WeatherConditions(
            temperature: Double.random(in: 10...25),
            dewpoint: Double.random(in: 5...20),
            windDirection: Int.random(in: 0...360),
            windSpeed: Int.random(in: 5...25),
            windGust: nil,
            visibility: Double.random(in: 5...10),
            ceiling: Int.random(in: 2000...8000),
            cloudCoverage: .scattered,
            precipitation: .none,
            flightRules: .vfr
        )
    }

    private func analyzeHazards(conditions: WeatherConditions, altitude: Int) -> [RouteHazard] {
        var hazards: [RouteHazard] = []

        // Vent fort
        if conditions.windSpeed > 25 {
            hazards.append(RouteHazard(
                type: .strongWind,
                severity: conditions.windSpeed > 35 ? .high : .medium,
                description: "Vent fort: \(conditions.windSpeed) kt"
            ))
        }

        // Visibilité réduite
        if conditions.visibility < 5 {
            hazards.append(RouteHazard(
                type: .lowVisibility,
                severity: conditions.visibility < 3 ? .high : .medium,
                description: "Visibilité: \(String(format: "%.1f", conditions.visibility)) SM"
            ))
        }

        // Plafond bas
        if let ceiling = conditions.ceiling, ceiling < 3000 {
            hazards.append(RouteHazard(
                type: .lowCeiling,
                severity: ceiling < 1000 ? .high : .medium,
                description: "Plafond: \(ceiling) ft AGL"
            ))
        }

        // Givrage potentiel
        if conditions.temperature <= 0 && conditions.temperature >= -20 {
            if conditions.cloudCoverage != .none && conditions.cloudCoverage != .few {
                hazards.append(RouteHazard(
                    type: .icing,
                    severity: .high,
                    description: "Risque de givrage"
                ))
            }
        }

        // Précipitations
        if conditions.precipitation != .none {
            hazards.append(RouteHazard(
                type: .precipitation,
                severity: .medium,
                description: "Précipitations présentes"
            ))
        }

        return hazards
    }

    private func determineSegmentStatus(conditions: WeatherConditions, hazards: [RouteHazard]) -> SegmentStatus {
        // Vérifier les dangers critiques
        let criticalHazards = hazards.filter { $0.severity == .high }

        if !criticalHazards.isEmpty {
            return .critical
        }

        // Vérifier les conditions IFR
        if conditions.flightRules == .ifr || conditions.flightRules == .lifr {
            return .marginal
        }

        // Vérifier les dangers modérés
        let moderateHazards = hazards.filter { $0.severity == .medium }

        if !moderateHazards.isEmpty {
            return .caution
        }

        // Bonnes conditions
        return .good
    }

    // MARK: - Route Summary

    private func generateRouteSummary(
        segments: [RouteSegment],
        departure: RoutePoint,
        arrival: RoutePoint,
        cruiseAltitude: Int
    ) -> RouteSummary {
        // Calculer statistiques
        let goodSegments = segments.filter { $0.status == .good }.count
        let cautionSegments = segments.filter { $0.status == .caution }.count
        let marginalSegments = segments.filter { $0.status == .marginal }.count
        let criticalSegments = segments.filter { $0.status == .critical }.count

        let totalDistance = AviationCalculations.distanceNauticalMiles(
            from: departure.coordinate,
            to: arrival.coordinate
        )

        // Déterminer recommandation globale
        let recommendation: RouteRecommendation
        if criticalSegments > 0 {
            recommendation = .notRecommended
        } else if marginalSegments > segments.count / 2 {
            recommendation = .ifrOnly
        } else if cautionSegments > segments.count / 3 {
            recommendation = .caution
        } else {
            recommendation = .recommended
        }

        // Collecter tous les dangers
        let allHazards = segments.flatMap { $0.hazards }

        return RouteSummary(
            departure: departure,
            arrival: arrival,
            totalDistance: totalDistance,
            cruiseAltitude: cruiseAltitude,
            segmentCount: segments.count,
            goodSegments: goodSegments,
            cautionSegments: cautionSegments,
            marginalSegments: marginalSegments,
            criticalSegments: criticalSegments,
            recommendation: recommendation,
            hazards: allHazards
        )
    }
}

// MARK: - Models

struct RoutePoint {
    let name: String
    let icaoCode: String?
    let coordinate: CLLocationCoordinate2D
}

struct Waypoint {
    let coordinate: CLLocationCoordinate2D
    let distanceFromDeparture: Double // NM
    let bearing: Double                // Degrees
}

struct RouteSegment: Identifiable {
    let id = UUID()
    let segmentNumber: Int
    let waypoint: Waypoint
    let conditions: WeatherConditions
    let hazards: [RouteHazard]
    let status: SegmentStatus
}

struct WeatherConditions {
    let temperature: Double         // °C
    let dewpoint: Double            // °C
    let windDirection: Int          // Degrees
    let windSpeed: Int              // Knots
    let windGust: Int?              // Knots
    let visibility: Double          // Statute miles
    let ceiling: Int?               // Feet AGL
    let cloudCoverage: CloudCoverage
    let precipitation: PrecipitationType
    let flightRules: FlightRules
}

enum PrecipitationType {
    case none
    case rain
    case snow
    case mixed

    var description: String {
        switch self {
        case .none: return "Aucune"
        case .rain: return "Pluie"
        case .snow: return "Neige"
        case .mixed: return "Mixte"
        }
    }

    var emoji: String {
        switch self {
        case .none: return ""
        case .rain: return "🌧️"
        case .snow: return "❄️"
        case .mixed: return "🌨️"
        }
    }
}

struct RouteHazard: Identifiable {
    let id = UUID()
    let type: HazardType
    let severity: Severity
    let description: String

    enum HazardType {
        case strongWind
        case lowVisibility
        case lowCeiling
        case icing
        case thunderstorm
        case turbulence
        case precipitation

        var icon: String {
            switch self {
            case .strongWind: return "wind"
            case .lowVisibility: return "eye.slash"
            case .lowCeiling: return "cloud"
            case .icing: return "snowflake"
            case .thunderstorm: return "cloud.bolt"
            case .turbulence: return "waveform.path"
            case .precipitation: return "cloud.rain"
            }
        }
    }

    enum Severity {
        case low
        case medium
        case high

        var color: String {
            switch self {
            case .low: return "green"
            case .medium: return "yellow"
            case .high: return "red"
            }
        }
    }
}

enum SegmentStatus {
    case good
    case caution
    case marginal
    case critical

    var description: String {
        switch self {
        case .good: return "Bonnes conditions"
        case .caution: return "Prudence"
        case .marginal: return "Conditions marginales"
        case .critical: return "Conditions critiques"
        }
    }

    var color: String {
        switch self {
        case .good: return "green"
        case .caution: return "yellow"
        case .marginal: return "orange"
        case .critical: return "red"
        }
    }

    var emoji: String {
        switch self {
        case .good: return "✅"
        case .caution: return "⚠️"
        case .marginal: return "🟠"
        case .critical: return "🚫"
        }
    }
}

struct RouteSummary {
    let departure: RoutePoint
    let arrival: RoutePoint
    let totalDistance: Double          // NM
    let cruiseAltitude: Int            // Feet MSL
    let segmentCount: Int
    let goodSegments: Int
    let cautionSegments: Int
    let marginalSegments: Int
    let criticalSegments: Int
    let recommendation: RouteRecommendation
    let hazards: [RouteHazard]

    var percentageGood: Double {
        Double(goodSegments) / Double(segmentCount) * 100
    }

    var percentageCaution: Double {
        Double(cautionSegments) / Double(segmentCount) * 100
    }

    var percentageMarginal: Double {
        Double(marginalSegments) / Double(segmentCount) * 100
    }

    var percentageCritical: Double {
        Double(criticalSegments) / Double(segmentCount) * 100
    }
}

enum RouteRecommendation {
    case recommended
    case caution
    case ifrOnly
    case notRecommended

    var description: String {
        switch self {
        case .recommended: return "Vol recommandé"
        case .caution: return "Vol avec prudence"
        case .ifrOnly: return "Vol IFR uniquement"
        case .notRecommended: return "Vol non recommandé"
        }
    }

    var emoji: String {
        switch self {
        case .recommended: return "✅"
        case .caution: return "⚠️"
        case .ifrOnly: return "🛩️"
        case .notRecommended: return "⛔"
        }
    }

    var color: String {
        switch self {
        case .recommended: return "green"
        case .caution: return "yellow"
        case .ifrOnly: return "orange"
        case .notRecommended: return "red"
        }
    }
}

// MARK: - Errors

enum RouteWeatherError: LocalizedError {
    case invalidRoute
    case analysisError(String)
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidRoute:
            return "Route invalide"
        case .analysisError(let message):
            return "Erreur d'analyse: \(message)"
        case .noData:
            return "Aucune donnée météo disponible"
        }
    }
}
