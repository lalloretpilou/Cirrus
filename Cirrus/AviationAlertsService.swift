//
//  AviationAlertsService.swift
//  Cirrus
//
//  Aviation-specific weather alerts service
//

import Foundation
import UserNotifications
import CoreLocation

@MainActor
class AviationAlertsService: ObservableObject {
    static let shared = AviationAlertsService()

    @Published var activeAlerts: [AviationAlert] = []
    @Published var notificationsEnabled = false

    private init() {
        checkNotificationPermissions()
    }

    // MARK: - Notification Permissions

    func requestNotificationPermissions() async -> Bool {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            self.notificationsEnabled = granted
            return granted
        } catch {
            print("Error requesting notification permissions: \(error)")
            return false
        }
    }

    private func checkNotificationPermissions() {
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            Task { @MainActor in
                self.notificationsEnabled = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - Alert Generation

    func analyzeConditionsAndGenerateAlerts(
        metar: METAR,
        taf: TAF?,
        aerodrome: Aerodrome,
        windsAloft: WindsAloft?
    ) -> [AviationAlert] {
        var alerts: [AviationAlert] = []

        // Wind alerts
        if metar.wind.speed > 25 {
            alerts.append(AviationAlert(
                type: .strongWind,
                severity: metar.wind.speed > 35 ? .severe : .moderate,
                title: "Vent fort",
                message: "Vent de \(metar.wind.speed) kt",
                location: aerodrome.name,
                validUntil: Date().addingTimeInterval(3600)
            ))
        }

        // Gust alerts
        if let gust = metar.wind.gust, gust > 20 {
            alerts.append(AviationAlert(
                type: .strongWind,
                severity: gust > 30 ? .severe : .moderate,
                title: "Rafales importantes",
                message: "Rafales jusqu'à \(gust) kt",
                location: aerodrome.name,
                validUntil: Date().addingTimeInterval(3600)
            ))
        }

        // Low visibility alerts
        if metar.visibility.value < 3 {
            alerts.append(AviationAlert(
                type: .lowVisibility,
                severity: metar.visibility.value < 1 ? .severe : .moderate,
                title: "Visibilité réduite",
                message: "Visibilité: \(String(format: "%.1f", metar.visibility.value)) SM",
                location: aerodrome.name,
                validUntil: Date().addingTimeInterval(3600)
            ))
        }

        // Low ceiling alerts
        if let ceiling = metar.clouds.first(where: { $0.coverage == .broken || $0.coverage == .overcast }) {
            if ceiling.altitude < 1000 {
                alerts.append(AviationAlert(
                    type: .lowCeiling,
                    severity: ceiling.altitude < 500 ? .severe : .moderate,
                    title: "Plafond bas",
                    message: "Plafond à \(ceiling.altitude) ft AGL",
                    location: aerodrome.name,
                    validUntil: Date().addingTimeInterval(3600)
                ))
            }
        }

        // Icing alerts
        if metar.temperature.celsius <= 0 && metar.temperature.celsius >= -20 {
            let spread = metar.temperature.celsius - metar.dewpoint
            if spread < 3 && !metar.clouds.isEmpty {
                alerts.append(AviationAlert(
                    type: .icing,
                    severity: metar.temperature.celsius >= -10 ? .severe : .moderate,
                    title: "Risque de givrage",
                    message: "Conditions favorables au givrage entre \(Int(metar.temperature.celsius))°C et point de rosée",
                    location: aerodrome.name,
                    validUntil: Date().addingTimeInterval(3600)
                ))
            }
        }

        // Thunderstorm alerts
        if metar.weatherPhenomena.contains(where: { $0.descriptor == .thunderstorm }) {
            alerts.append(AviationAlert(
                type: .thunderstorm,
                severity: .severe,
                title: "Orages",
                message: "Activité orageuse présente ou à proximité",
                location: aerodrome.name,
                validUntil: Date().addingTimeInterval(3600)
            ))
        }

        // Flight rules alerts
        if metar.flightRules == .ifr || metar.flightRules == .lifr {
            alerts.append(AviationAlert(
                type: .flightRules,
                severity: metar.flightRules == .lifr ? .severe : .moderate,
                title: metar.flightRules == .lifr ? "Conditions LIFR" : "Conditions IFR",
                message: metar.flightRules.description,
                location: aerodrome.name,
                validUntil: Date().addingTimeInterval(3600)
            ))
        }

        // Crosswind alerts for main runway
        if let mainRunway = aerodrome.runways.first {
            let runwayHeading = extractRunwayHeading(mainRunway.name)
            let windComponents = AviationCalculations.calculateWindComponents(
                windDirection: metar.wind.direction ?? 0,
                windSpeed: metar.wind.speed,
                runwayHeading: runwayHeading
            )

            if windComponents.crosswind > 15 {
                alerts.append(AviationAlert(
                    type: .crosswind,
                    severity: windComponents.crosswind > 20 ? .severe : .moderate,
                    title: "Vent de travers important",
                    message: "Vent de travers de \(Int(windComponents.crosswind)) kt sur piste \(mainRunway.name)",
                    location: aerodrome.name,
                    validUntil: Date().addingTimeInterval(3600)
                ))
            }
        }

        // Density altitude alerts
        let pressureAlt = AviationCalculations.calculatePressureAltitude(
            fieldElevation: aerodrome.elevation,
            altimeter: metar.altimeter.inHg
        )
        let densityAlt = AviationCalculations.calculateDensityAltitude(
            pressureAltitude: pressureAlt,
            temperature: metar.temperature.celsius,
            dewpoint: metar.dewpoint,
            altimeter: metar.altimeter.inHg
        )

        if densityAlt.performanceImpact == .poor || densityAlt.performanceImpact == .critical {
            alerts.append(AviationAlert(
                type: .highDensityAltitude,
                severity: densityAlt.performanceImpact == .critical ? .severe : .moderate,
                title: "Altitude densité élevée",
                message: "Altitude densité: \(densityAlt.densityAltitude) ft - Performances dégradées",
                location: aerodrome.name,
                validUntil: Date().addingTimeInterval(3600)
            ))
        }

        // TAF-based future alerts
        if let taf = taf {
            for forecast in taf.forecasts.prefix(6) { // Next 6 hours
                // Check for deteriorating conditions
                if let forecastCeiling = forecast.clouds.first(where: { $0.coverage == .broken || $0.coverage == .overcast })?.altitude,
                   forecastCeiling < 1000 {
                    alerts.append(AviationAlert(
                        type: .lowCeiling,
                        severity: .moderate,
                        title: "Plafond bas prévu",
                        message: "Plafond prévu à \(forecastCeiling) ft à \(forecast.startTime.formatted(date: .omitted, time: .shortened))",
                        location: aerodrome.name,
                        validUntil: forecast.endTime
                    ))
                }

                if forecast.wind.speed > 25 {
                    alerts.append(AviationAlert(
                        type: .strongWind,
                        severity: .moderate,
                        title: "Vent fort prévu",
                        message: "Vent de \(forecast.wind.speed) kt prévu à \(forecast.startTime.formatted(date: .omitted, time: .shortened))",
                        location: aerodrome.name,
                        validUntil: forecast.endTime
                    ))
                }
            }
        }

        self.activeAlerts = alerts
        return alerts
    }

    // MARK: - Push Notifications

    func sendNotificationForAlert(_ alert: AviationAlert) async {
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(alert.severity.emoji) \(alert.title)"
        content.body = "\(alert.location): \(alert.message)"
        content.sound = .default

        // Set category based on severity
        switch alert.severity {
        case .severe:
            content.categoryIdentifier = "SEVERE_WEATHER"
        case .moderate:
            content.categoryIdentifier = "MODERATE_WEATHER"
        case .light:
            content.categoryIdentifier = "LIGHT_WEATHER"
        }

        // Create trigger (immediate)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        // Create request
        let request = UNNotificationRequest(
            identifier: alert.id.uuidString,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Error sending notification: \(error)")
        }
    }

    func sendNotificationsForAlerts(_ alerts: [AviationAlert]) async {
        for alert in alerts where alert.severity == .severe {
            await sendNotificationForAlert(alert)
        }
    }

    // MARK: - Alert Management

    func clearExpiredAlerts() {
        activeAlerts.removeAll { $0.validUntil < Date() }
    }

    func dismissAlert(_ alert: AviationAlert) {
        activeAlerts.removeAll { $0.id == alert.id }
    }

    func dismissAllAlerts() {
        activeAlerts.removeAll()
    }

    // MARK: - Helper Methods

    private func extractRunwayHeading(_ runwayName: String) -> Int {
        let digits = runwayName.prefix(2)
        if let heading = Int(digits) {
            return heading * 10
        }
        return 0
    }
}

// MARK: - Aviation Alert Model

struct AviationAlert: Identifiable, Codable {
    let id = UUID()
    let type: AlertType
    let severity: Severity
    let title: String
    let message: String
    let location: String
    let validUntil: Date

    enum CodingKeys: String, CodingKey {
        case type, severity, title, message, location, validUntil
    }

    enum AlertType: String, Codable {
        case strongWind = "WIND"
        case lowVisibility = "VIS"
        case lowCeiling = "CEIL"
        case icing = "ICE"
        case thunderstorm = "TS"
        case turbulence = "TURB"
        case flightRules = "FR"
        case crosswind = "XWIND"
        case highDensityAltitude = "DA"

        var icon: String {
            switch self {
            case .strongWind: return "wind"
            case .lowVisibility: return "eye.slash"
            case .lowCeiling: return "cloud"
            case .icing: return "snowflake"
            case .thunderstorm: return "cloud.bolt"
            case .turbulence: return "waveform.path"
            case .flightRules: return "airplane.circle"
            case .crosswind: return "arrow.left.and.right"
            case .highDensityAltitude: return "arrow.up.circle"
            }
        }
    }

    enum Severity: String, Codable {
        case light = "LIGHT"
        case moderate = "MOD"
        case severe = "SEV"

        var emoji: String {
            switch self {
            case .light: return "⚠️"
            case .moderate: return "⚠️"
            case .severe: return "🚨"
            }
        }

        var color: String {
            switch self {
            case .light: return "yellow"
            case .moderate: return "orange"
            case .severe: return "red"
            }
        }
    }

    var isExpired: Bool {
        validUntil < Date()
    }

    var timeRemaining: String {
        let interval = validUntil.timeIntervalSinceNow
        if interval < 0 { return "Expiré" }

        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
