//
//  CrosswindAnalysisView.swift
//  Cirrus
//
//  Vue d'analyse crosswind multi-pistes temps réel
//

import SwiftUI
import Charts

struct CrosswindAnalysisView: View {
    @StateObject private var crosswindService = CrosswindAnalysisService.shared
    @StateObject private var aviationService = AviationWeatherService.shared

    @State private var selectedAerodrome: Aerodrome?
    @State private var icaoCode: String = ""
    @State private var showAircraftConfig = false
    @State private var selectedRunway: RunwayAnalysis?

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // En-tête avec sélection aérodrome
                        AerodromeSelectionHeader(
                            icaoCode: $icaoCode,
                            selectedAerodrome: selectedAerodrome,
                            onSearch: performAnalysis
                        )

                        if crosswindService.isLoading {
                            ProgressView("Analyse en cours...")
                                .foregroundColor(.white)
                                .padding(.top, 40)
                        } else if let error = crosswindService.error {
                            ErrorCard(error: error)
                        } else if !crosswindService.runwayAnalysis.isEmpty {
                            // Configuration avion
                            AircraftConfigCard(
                                config: crosswindService.aircraftConfig,
                                onTap: { showAircraftConfig = true }
                            )

                            // Piste recommandée
                            if let recommended = crosswindService.recommendedRunway {
                                RecommendedRunwayCard(analysis: recommended)
                            }

                            // Liste des pistes
                            RunwayListSection(
                                analyses: crosswindService.runwayAnalysis,
                                selectedRunway: $selectedRunway
                            )

                            // Prévisions horaires
                            if !crosswindService.hourlyForecasts.isEmpty {
                                HourlyForecastSection(
                                    forecasts: crosswindService.hourlyForecasts
                                )
                            }

                            // Informations détaillées piste sélectionnée
                            if let selected = selectedRunway {
                                RunwayDetailSheet(analysis: selected)
                            }
                        } else {
                            // Vue vide
                            EmptyStateView()
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Analyse Crosswind")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showAircraftConfig) {
                AircraftConfigSheet(
                    selectedConfig: crosswindService.aircraftConfig,
                    onSelect: { config in
                        crosswindService.aircraftConfig = config
                        if let aerodrome = selectedAerodrome,
                           let metar = aviationService.currentMETAR {
                            Task {
                                await crosswindService.analyzeRunways(
                                    aerodrome: aerodrome,
                                    metar: metar,
                                    taf: aviationService.currentTAF
                                )
                            }
                        }
                    }
                )
            }
        }
    }

    private func performAnalysis() {
        Task {
            // Rechercher l'aérodrome
            let aerodromes = try? await aviationService.searchAerodromes(query: icaoCode)
            guard let aerodrome = aerodromes?.first else { return }

            selectedAerodrome = aerodrome

            // Récupérer METAR et TAF
            try? await aviationService.fetchMETAR(for: icaoCode)
            try? await aviationService.fetchTAF(for: icaoCode)

            guard let metar = aviationService.currentMETAR else { return }

            // Analyser les pistes
            await crosswindService.analyzeRunways(
                aerodrome: aerodrome,
                metar: metar,
                taf: aviationService.currentTAF
            )
        }
    }
}

// MARK: - Aerodrome Selection Header

struct AerodromeSelectionHeader: View {
    @Binding var icaoCode: String
    let selectedAerodrome: Aerodrome?
    let onSearch: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "airplane.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Analyse Multi-Pistes")
                        .font(.headline)
                        .foregroundColor(.white)

                    if let aerodrome = selectedAerodrome {
                        Text("\(aerodrome.name) (\(aerodrome.icaoCode))")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    } else {
                        Text("Entrez un code OACI")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }

                Spacer()
            }

            HStack {
                TextField("Code OACI (ex: LFPO)", text: $icaoCode)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.allCharacters)
                    .onChange(of: icaoCode) { newValue in
                        icaoCode = newValue.uppercased()
                    }

                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                .disabled(icaoCode.count < 4)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
    }
}

// MARK: - Aircraft Config Card

struct AircraftConfigCard: View {
    let config: AircraftConfig
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "airplane")
                            .foregroundColor(.blue)
                        Text("Configuration Avion")
                            .font(.headline)
                            .foregroundColor(.white)
                    }

                    Text(config.name)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)

                    HStack(spacing: 20) {
                        LimitBadge(
                            icon: "wind",
                            label: "Démontré",
                            value: "\(Int(config.demonstratedCrosswind)) kt",
                            color: .orange
                        )

                        LimitBadge(
                            icon: "exclamationmark.triangle",
                            label: "Max",
                            value: "\(Int(config.maxCrosswind)) kt",
                            color: .red
                        )
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(12)
        }
    }
}

struct LimitBadge: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)

            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)

            Text(value)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
    }
}

// MARK: - Recommended Runway Card

struct RecommendedRunwayCard: View {
    let analysis: RunwayAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)

                Text("Piste Recommandée")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Text("\(analysis.score)/100")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }

            // Nom de la piste
            HStack {
                Text("RWY \(analysis.runway.name)")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                StatusBadge(status: analysis.status)
            }

            // Composantes de vent
            WindComponentsDisplay(
                components: analysis.windComponents,
                gustComponents: analysis.gustComponents
            )

            // Message d'avertissement si présent
            if let warning = analysis.warningMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(warning)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(8)
                .background(Color.orange.opacity(0.2))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.green.opacity(0.3), Color.green.opacity(0.1)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.green, lineWidth: 2)
        )
    }
}

// MARK: - Runway List Section

struct RunwayListSection: View {
    let analyses: [RunwayAnalysis]
    @Binding var selectedRunway: RunwayAnalysis?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet")
                    .foregroundColor(.white)
                Text("Toutes les Pistes")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            ForEach(analyses) { analysis in
                RunwayRow(
                    analysis: analysis,
                    isRecommended: analyses.first?.id == analysis.id
                )
                .onTapGesture {
                    selectedRunway = analysis
                }
            }
        }
    }
}

struct RunwayRow: View {
    let analysis: RunwayAnalysis
    let isRecommended: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                // Nom de la piste
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("RWY \(analysis.runway.name)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        if isRecommended {
                            Text("✅ RECOMMANDÉ")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }

                    if let surface = analysis.runway.surface {
                        Text(surface)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }

                Spacer()

                // Score et statut
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(analysis.score)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(scoreColor(analysis.score))

                    StatusBadge(status: analysis.status)
                }
            }

            // Barre de score
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 8)
                        .cornerRadius(4)

                    Rectangle()
                        .fill(scoreColor(analysis.score))
                        .frame(width: geometry.size.width * CGFloat(analysis.score) / 100, height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)

            // Composantes de vent compactes
            HStack(spacing: 16) {
                WindComponent(
                    icon: "arrow.left.and.right",
                    label: "Crosswind",
                    value: analysis.windComponents.crosswind,
                    color: crosswindColor(analysis.windComponents.crosswind, limits: analysis.aircraftLimits)
                )

                WindComponent(
                    icon: analysis.windComponents.headwind >= 0 ? "arrow.up" : "arrow.down",
                    label: analysis.windComponents.headwind >= 0 ? "Headwind" : "Tailwind",
                    value: abs(analysis.windComponents.headwind),
                    color: analysis.windComponents.headwind >= 0 ? .green : .red
                )

                if let gust = analysis.gustComponents {
                    WindComponent(
                        icon: "wind",
                        label: "Rafales",
                        value: gust.crosswind,
                        color: crosswindColor(gust.crosswind, limits: analysis.aircraftLimits)
                    )
                }
            }

            // Message d'avertissement si présent
            if let warning = analysis.warningMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(warning)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.2))
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color.gray.opacity(isRecommended ? 0.3 : 0.2))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isRecommended ? Color.green : Color.clear, lineWidth: 2)
        )
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default: return .red
        }
    }

    private func crosswindColor(_ crosswind: Double, limits: AircraftConfig) -> Color {
        if crosswind > limits.maxCrosswind {
            return .red
        } else if crosswind > limits.demonstratedCrosswind {
            return .orange
        } else if crosswind > 10 {
            return .yellow
        } else {
            return .green
        }
    }
}

struct WindComponent: View {
    let icon: String
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)

            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)

            Text("\(Int(value)) kt")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
    }
}

// MARK: - Wind Components Display

struct WindComponentsDisplay: View {
    let components: WindComponents
    let gustComponents: WindComponents?

    var body: some View {
        HStack(spacing: 20) {
            // Crosswind
            VStack(spacing: 4) {
                Image(systemName: "arrow.left.and.right")
                    .font(.title2)
                    .foregroundColor(.orange)

                Text("Crosswind")
                    .font(.caption)
                    .foregroundColor(.gray)

                Text("\(Int(components.crosswind)) kt")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                if let gust = gustComponents {
                    Text("Rafales: \(Int(gust.crosswind)) kt")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.2))
            .cornerRadius(8)

            // Headwind/Tailwind
            VStack(spacing: 4) {
                Image(systemName: components.headwind >= 0 ? "arrow.up" : "arrow.down")
                    .font(.title2)
                    .foregroundColor(components.headwind >= 0 ? .green : .red)

                Text(components.headwind >= 0 ? "Headwind" : "Tailwind")
                    .font(.caption)
                    .foregroundColor(.gray)

                Text("\(Int(abs(components.headwind))) kt")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                if let gust = gustComponents {
                    Text("Rafales: \(Int(abs(gust.headwind))) kt")
                        .font(.caption2)
                        .foregroundColor(gust.headwind >= 0 ? .green : .red)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background((components.headwind >= 0 ? Color.green : Color.red).opacity(0.2))
            .cornerRadius(8)
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: RunwayStatus

    var body: some View {
        HStack(spacing: 4) {
            Text(status.emoji)
                .font(.caption)
            Text(status.description)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor(status))
        .cornerRadius(6)
    }

    private func statusColor(_ status: RunwayStatus) -> Color {
        switch status.color {
        case "green": return .green
        case "lightGreen": return .green.opacity(0.7)
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        default: return .gray
        }
    }
}

// MARK: - Hourly Forecast Section

struct HourlyForecastSection: View {
    let forecasts: [HourlyRunwayForecast]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.white)
                Text("Évolution Prévue (TAF)")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(forecasts) { forecast in
                        HourlyForecastCard(forecast: forecast)
                    }
                }
            }

            // Chart view
            if forecasts.count > 2 {
                Chart {
                    ForEach(forecasts) { forecast in
                        if let runway = forecast.bestRunway {
                            BarMark(
                                x: .value("Heure", forecast.timeFormatted),
                                y: .value("Score", runway.score)
                            )
                            .foregroundStyle(scoreGradient(runway.score))
                        }
                    }
                }
                .frame(height: 200)
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.gray.opacity(0.3))
                        AxisValueLabel()
                            .foregroundStyle(Color.white)
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel()
                            .foregroundStyle(Color.white)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
    }

    private func scoreGradient(_ score: Int) -> LinearGradient {
        let color: Color
        switch score {
        case 80...100: color = .green
        case 60..<80: color = .yellow
        case 40..<60: color = .orange
        default: color = .red
        }
        return LinearGradient(
            gradient: Gradient(colors: [color, color.opacity(0.7)]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct HourlyForecastCard: View {
    let forecast: HourlyRunwayForecast

    var body: some View {
        VStack(spacing: 8) {
            Text(forecast.timeFormatted)
                .font(.caption)
                .foregroundColor(.gray)

            if let runway = forecast.bestRunway {
                Text("RWY \(runway.runway.name)")
                    .font(.headline)
                    .foregroundColor(.white)

                Text("\(runway.score)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(scoreColor(runway.score))

                StatusBadge(status: runway.status)
            }

            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "wind")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Text("\(forecast.windDirection)° \(forecast.windSpeed) kt")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                if let gust = forecast.gustSpeed {
                    Text("G\(gust) kt")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .frame(width: 120)
        .background(Color.gray.opacity(0.3))
        .cornerRadius(12)
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default: return .red
        }
    }
}

// MARK: - Runway Detail Sheet

struct RunwayDetailSheet: View {
    let analysis: RunwayAnalysis

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("RWY \(analysis.runway.name)")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Spacer()

                StatusBadge(status: analysis.status)
            }

            // Détails complets
            VStack(alignment: .leading, spacing: 12) {
                DetailRow(label: "Longueur", value: "\(analysis.runway.length) m")
                DetailRow(label: "Largeur", value: "\(analysis.runway.width) m")
                if let surface = analysis.runway.surface {
                    DetailRow(label: "Revêtement", value: surface)
                }
                DetailRow(label: "Score", value: "\(analysis.score)/100")
            }

            Divider().background(Color.gray)

            WindComponentsDisplay(
                components: analysis.windComponents,
                gustComponents: analysis.gustComponents
            )

            Spacer()
        }
        .padding()
        .background(Color.black)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .foregroundColor(.white)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Aircraft Config Sheet

struct AircraftConfigSheet: View {
    @Environment(\.dismiss) var dismiss
    let selectedConfig: AircraftConfig
    let onSelect: (AircraftConfig) -> Void

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(AircraftConfig.presets, id: \.name) { config in
                            Button(action: {
                                onSelect(config)
                                dismiss()
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(config.name)
                                            .font(.headline)
                                            .foregroundColor(.white)

                                        HStack(spacing: 16) {
                                            Text("Démontré: \(Int(config.demonstratedCrosswind)) kt")
                                                .font(.caption)
                                                .foregroundColor(.orange)

                                            Text("Max: \(Int(config.maxCrosswind)) kt")
                                                .font(.caption)
                                                .foregroundColor(.red)
                                        }
                                    }

                                    Spacer()

                                    if config.name == selectedConfig.name {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.title2)
                                    }
                                }
                                .padding()
                                .background(
                                    config.name == selectedConfig.name ?
                                    Color.green.opacity(0.2) : Color.gray.opacity(0.2)
                                )
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Configuration Avion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "airplane.circle")
                .font(.system(size: 80))
                .foregroundColor(.gray)

            Text("Aucune analyse en cours")
                .font(.headline)
                .foregroundColor(.white)

            Text("Entrez un code OACI pour analyser les pistes")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }
}

// MARK: - Error Card

struct ErrorCard: View {
    let error: CrosswindError

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)

            Text(error.localizedDescription)
                .foregroundColor(.white)
                .font(.subheadline)
        }
        .padding()
        .background(Color.red.opacity(0.2))
        .cornerRadius(12)
    }
}

// MARK: - Preview

struct CrosswindAnalysisView_Previews: PreviewProvider {
    static var previews: some View {
        CrosswindAnalysisView()
            .preferredColorScheme(.dark)
    }
}
