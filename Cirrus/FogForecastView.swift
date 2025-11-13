//
//  FogForecastView.swift
//  Cirrus
//
//  Vue des prévisions de brouillard et heure de dissipation
//

import SwiftUI
import Charts

struct FogForecastView: View {
    @StateObject private var fogService = FogForecastService.shared
    @StateObject private var aviationService = AviationWeatherService.shared
    @StateObject private var locationManager = LocationManager()

    @State private var selectedAerodrome: Aerodrome?
    @State private var showAerodromeSearch = false

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.1, blue: 0.15), Color(red: 0.1, green: 0.15, blue: 0.25)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if fogService.isLoading {
                    LoadingView(message: "Analyse des conditions de brouillard...")
                } else if let forecast = fogService.fogForecast {
                    ScrollView {
                        VStack(spacing: 20) {
                            // En-tête aérodrome
                            AerodromeSelectionHeader(
                                aerodrome: forecast.aerodrome,
                                onTap: { showAerodromeSearch = true }
                            )
                            .padding(.horizontal)

                            // Carte de risque actuel
                            CurrentFogRiskCard(forecast: forecast, fogService: fogService)
                                .padding(.horizontal)

                            // Si brouillard présent : dissipation
                            if forecast.hasActiveFog, let dissipation = forecast.dissipationTime {
                                DissipationCard(dissipationTime: dissipation, fogService: fogService, forecast: forecast)
                                    .padding(.horizontal)
                            }

                            // Graphique évolution 24h
                            if !fogService.hourlyFogRisk.isEmpty {
                                HourlyFogChart(hourlyRisks: fogService.hourlyFogRisk)
                                    .padding(.horizontal)
                            }

                            // Facteurs et recommandations
                            FogFactorsCard(risk: forecast.currentRisk)
                                .padding(.horizontal)

                            // Prochaine formation
                            if let nextFormation = forecast.nextFormationTime {
                                NextFormationCard(formationTime: nextFormation)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                } else {
                    // Configuration initiale
                    FogSetupView(
                        selectedAerodrome: $selectedAerodrome,
                        onSearch: { showAerodromeSearch = true },
                        onAnalyze: analyzeFog
                    )
                }
            }
            .navigationTitle("Prévisions Brouillard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: refreshData) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(isPresented: $showAerodromeSearch) {
                AerodromeSearchSheet(
                    selectedAerodrome: $selectedAerodrome,
                    title: "Choisir un aérodrome"
                )
            }
            .task {
                await loadInitialData()
            }
        }
    }

    private func loadInitialData() async {
        if let location = locationManager.currentLocation {
            // Trouver l'aérodrome le plus proche
            let coordinate = location.coordinate
            if let nearbyAerodrome = aviationService.nearbyAerodromes.first {
                selectedAerodrome = nearbyAerodrome
                await analyzeFog()
            } else {
                // Charger les aérodromes proches
                do {
                    let nearby = try await aviationService.fetchNearbyAerodromes(coordinate: coordinate, radius: 50)
                    if let first = nearby.first {
                        selectedAerodrome = first
                        await analyzeFog()
                    }
                } catch {
                    print("Error loading nearby aerodromes: \(error)")
                }
            }
        }
    }

    private func analyzeFog() async {
        guard let aerodrome = selectedAerodrome else { return }

        // Récupérer le METAR
        if let metar = aviationService.currentMETAR {
            await fogService.analyzeFogConditions(
                metar: metar,
                aerodrome: aerodrome
            )
        } else {
            // Charger le METAR
            do {
                let metar = try await aviationService.fetchMETAR(for: aerodrome.icaoCode)
                await fogService.analyzeFogConditions(
                    metar: metar,
                    aerodrome: aerodrome
                )
            } catch {
                print("Error fetching METAR: \(error)")
            }
        }
    }

    private func refreshData() {
        Task {
            await analyzeFog()
        }
    }
}

// MARK: - Aerodrome Selection Header

struct AerodromeSelectionHeader: View {
    let aerodrome: Aerodrome
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(aerodrome.icaoCode)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text(aerodrome.name)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

// MARK: - Current Fog Risk Card

struct CurrentFogRiskCard: View {
    let forecast: FogForecast
    let fogService: FogForecastService

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // En-tête avec emoji et niveau
            HStack {
                Text(forecast.currentRisk.level.emoji)
                    .font(.system(size: 60))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Risque Actuel")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))

                    Text(forecast.currentRisk.level.description)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("\(forecast.currentRisk.probability)% de probabilité")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer()
            }

            Divider()
                .background(Color.white.opacity(0.3))

            // Paramètres clés
            VStack(spacing: 12) {
                HStack {
                    ParameterView(
                        icon: "thermometer",
                        label: "Écart T-Td",
                        value: "\(String(format: "%.1f", forecast.currentRisk.spread))°C",
                        status: spreadStatus(forecast.currentRisk.spread)
                    )

                    ParameterView(
                        icon: "humidity",
                        label: "Humidité",
                        value: "\(Int(forecast.currentRisk.humidity))%",
                        status: humidityStatus(forecast.currentRisk.humidity)
                    )
                }

                HStack {
                    ParameterView(
                        icon: "wind",
                        label: "Vent",
                        value: "\(forecast.currentRisk.windSpeed) kt",
                        status: windStatus(forecast.currentRisk.windSpeed)
                    )

                    ParameterView(
                        icon: "eye",
                        label: "Visibilité",
                        value: "\(String(format: "%.1f", forecast.currentRisk.visibility)) SM",
                        status: visibilityStatus(forecast.currentRisk.visibility)
                    )
                }
            }

            Divider()
                .background(Color.white.opacity(0.3))

            // Recommandation
            HStack(spacing: 12) {
                Image(systemName: recommendationIcon(forecast.currentRisk.level))
                    .font(.title2)
                    .foregroundColor(recommendationColor(forecast.currentRisk.level))

                Text(forecast.recommendation)
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .padding()
            .background(recommendationColor(forecast.currentRisk.level).opacity(0.2))
            .cornerRadius(8)
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }

    private func spreadStatus(_ spread: Double) -> ParameterStatus {
        if spread < 2.0 { return .critical }
        else if spread < 3.0 { return .warning }
        else { return .good }
    }

    private func humidityStatus(_ humidity: Double) -> ParameterStatus {
        if humidity > 90 { return .critical }
        else if humidity > 80 { return .warning }
        else { return .good }
    }

    private func windStatus(_ wind: Int) -> ParameterStatus {
        if wind < 5 { return .warning }
        else if wind > 10 { return .good }
        else { return .neutral }
    }

    private func visibilityStatus(_ visibility: Double) -> ParameterStatus {
        if visibility < 3.0 { return .critical }
        else if visibility < 5.0 { return .warning }
        else { return .good }
    }

    private func recommendationIcon(_ level: FogRiskLevel) -> String {
        switch level {
        case .none, .low: return "checkmark.circle.fill"
        case .moderate: return "exclamationmark.triangle.fill"
        case .high, .veryHigh: return "xmark.octagon.fill"
        case .forming, .present: return "eye.slash.fill"
        }
    }

    private func recommendationColor(_ level: FogRiskLevel) -> Color {
        switch level {
        case .none, .low: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .veryHigh: return .red
        case .forming, .present: return .purple
        }
    }
}

struct ParameterView: View {
    let icon: String
    let label: String
    let value: String
    let status: ParameterStatus

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(status.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))

                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(status.color.opacity(0.2))
        .cornerRadius(8)
    }
}

enum ParameterStatus {
    case good
    case neutral
    case warning
    case critical

    var color: Color {
        switch self {
        case .good: return .green
        case .neutral: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Dissipation Card

struct DissipationCard: View {
    let dissipationTime: Date
    let fogService: FogForecastService
    let forecast: FogForecast

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sun.max.fill")
                    .font(.title)
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Dissipation Prévue")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(dissipationTime, style: .time)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                }

                Spacer()
            }

            Divider()
                .background(Color.white.opacity(0.3))

            // Temps restant
            TimeRemainingView(until: dissipationTime)

            // Heure de décollage recommandée
            if let flightReady = fogService.getFlightReadyTime(forecast: forecast) {
                HStack(spacing: 8) {
                    Image(systemName: "airplane.departure")
                        .foregroundColor(.green)

                    Text("Décollage possible dès ")
                        .font(.subheadline)
                        .foregroundColor(.white)

                    Text(flightReady, style: .time)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
                .padding()
                .background(Color.green.opacity(0.2))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}

struct TimeRemainingView: View {
    let until: Date

    var body: some View {
        let remaining = until.timeIntervalSinceNow

        if remaining > 0 {
            let hours = Int(remaining / 3600)
            let minutes = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)

            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .foregroundColor(.white.opacity(0.7))

                Text("Dans")
                    .foregroundColor(.white.opacity(0.7))

                if hours > 0 {
                    Text("\(hours)h \(minutes)min")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                } else {
                    Text("\(minutes) min")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
            }
            .font(.subheadline)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Dissipation en cours")
                    .foregroundColor(.white)
            }
            .font(.subheadline)
        }
    }
}

// MARK: - Hourly Fog Chart

struct HourlyFogChart: View {
    let hourlyRisks: [HourlyFogRisk]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Évolution sur 24 heures")
                .font(.headline)
                .foregroundColor(.white)

            // Graphique
            Chart {
                ForEach(hourlyRisks.prefix(24)) { hourlyRisk in
                    BarMark(
                        x: .value("Heure", hourlyRisk.time, unit: .hour),
                        y: .value("Risque", hourlyRisk.risk.level.rawValue)
                    )
                    .foregroundStyle(riskColor(hourlyRisk.risk.level))
                }
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(values: [0, 1, 2, 3, 4, 5, 6]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let intValue = value.as(Int.self) {
                            Text(levelLabel(intValue))
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                    AxisValueLabel(format: .dateTime.hour())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            // Légende
            HStack(spacing: 16) {
                ForEach([FogRiskLevel.none, .low, .moderate, .high, .veryHigh, .present], id: \.self) { level in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(riskColor(level))
                            .frame(width: 8, height: 8)

                        Text(level.description)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }

    private func riskColor(_ level: FogRiskLevel) -> Color {
        switch level {
        case .none: return .green
        case .low: return Color(red: 0.7, green: 0.9, blue: 0.5)
        case .moderate: return .yellow
        case .high: return .orange
        case .veryHigh: return .red
        case .forming: return Color(red: 0.6, green: 0.1, blue: 0.1)
        case .present: return .purple
        }
    }

    private func levelLabel(_ value: Int) -> String {
        switch value {
        case 0: return "Aucun"
        case 1: return "Faible"
        case 2: return "Modéré"
        case 3: return "Élevé"
        case 4: return "T.Élevé"
        case 5: return "Formation"
        case 6: return "Présent"
        default: return ""
        }
    }
}

// MARK: - Fog Factors Card

struct FogFactorsCard: View {
    let risk: FogRisk

    var body: some View {
        if !risk.factors.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Facteurs de risque")
                    .font(.headline)
                    .foregroundColor(.white)

                ForEach(risk.factors, id: \.self) { factor in
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)

                        Text(factor)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

// MARK: - Next Formation Card

struct NextFormationCard: View {
    let formationTime: Date

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title2)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("Prochaine formation probable")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))

                Text(formationTime, style: .relative)
                    .font(.headline)
                    .foregroundColor(.white)

                Text("à \(formationTime.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Fog Setup View

struct FogSetupView: View {
    @Binding var selectedAerodrome: Aerodrome?
    let onSearch: () -> Void
    let onAnalyze: () async -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("🌫️ Prévisions de Brouillard")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Heure de dissipation et risque de formation")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding()

            Button(action: onSearch) {
                HStack {
                    Image(systemName: "mappin.circle")
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Aérodrome")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))

                        if let aerodrome = selectedAerodrome {
                            Text("\(aerodrome.icaoCode) - \(aerodrome.name)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        } else {
                            Text("Choisir un aérodrome")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
            }
            .padding(.horizontal)

            Button(action: {
                Task {
                    await onAnalyze()
                }
            }) {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("Analyser les conditions")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(selectedAerodrome != nil ? Color.blue : Color.gray.opacity(0.5))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(selectedAerodrome == nil)
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 40)
    }
}

struct LoadingView: View {
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text(message)
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

#Preview {
    FogForecastView()
}
