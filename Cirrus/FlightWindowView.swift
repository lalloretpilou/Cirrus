//
//  FlightWindowView.swift
//  Cirrus
//
//  Vue des fenêtres de vol optimales
//

import SwiftUI
import Charts

struct FlightWindowView: View {
    @StateObject private var windowService = FlightWindowService.shared
    @StateObject private var aviationService = AviationWeatherService.shared

    @State private var selectedAerodrome: Aerodrome?
    @State private var icaoCode: String = ""
    @State private var selectedFlightType: FlightType = .vfr
    @State private var showFlightTypeSelector = false
    @State private var selectedWindow: FlightWindow?

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // En-tête
                        AerodromeSearchHeader(
                            icaoCode: $icaoCode,
                            selectedAerodrome: selectedAerodrome,
                            onSearch: performAnalysis
                        )

                        // Sélecteur type de vol
                        FlightTypeSelector(
                            selectedType: $selectedFlightType,
                            onSelect: {
                                if let aerodrome = selectedAerodrome,
                                   let metar = aviationService.currentMETAR {
                                    Task {
                                        await windowService.findOptimalWindows(
                                            aerodrome: aerodrome,
                                            metar: metar,
                                            taf: aviationService.currentTAF,
                                            flightType: selectedFlightType
                                        )
                                    }
                                }
                            }
                        )

                        if windowService.isLoading {
                            ProgressView("Analyse des fenêtres...")
                                .foregroundColor(.white)
                                .padding(.top, 40)
                        } else if let error = windowService.error {
                            WindowErrorCard(error: error)
                        } else if !windowService.flightWindows.isEmpty {
                            // Conditions actuelles
                            if let current = windowService.currentConditions {
                                CurrentConditionsCard(conditions: current)
                            }

                            // Recommandations
                            RecommendationsSection(
                                recommendations: windowService.getRecommendations(
                                    windows: windowService.flightWindows
                                )
                            )

                            // Timeline des fenêtres
                            WindowTimelineSection(
                                windows: windowService.flightWindows,
                                selectedWindow: $selectedWindow
                            )

                            // Chart de scores
                            WindowScoreChart(windows: windowService.flightWindows)

                        } else {
                            WindowEmptyState()
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Fenêtres de Vol")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $selectedWindow) { window in
                WindowDetailSheet(window: window)
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

            // Analyser les fenêtres
            await windowService.findOptimalWindows(
                aerodrome: aerodrome,
                metar: metar,
                taf: aviationService.currentTAF,
                flightType: selectedFlightType
            )
        }
    }
}

// MARK: - Aerodrome Search Header

struct AerodromeSearchHeader: View {
    @Binding var icaoCode: String
    let selectedAerodrome: Aerodrome?
    let onSearch: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 30))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Fenêtre de Vol Optimale")
                        .font(.headline)
                        .foregroundColor(.white)

                    if let aerodrome = selectedAerodrome {
                        Text("\(aerodrome.name) (\(aerodrome.icaoCode))")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    } else {
                        Text("Recherchez un aérodrome")
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

// MARK: - Flight Type Selector

struct FlightTypeSelector: View {
    @Binding var selectedType: FlightType
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type de vol")
                .font(.caption)
                .foregroundColor(.gray)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(FlightType.allCases, id: \.self) { type in
                        Button(action: {
                            selectedType = type
                            onSelect()
                        }) {
                            HStack {
                                Image(systemName: type.icon)
                                Text(type.rawValue)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(selectedType == type ? .white : .gray)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                selectedType == type ?
                                Color.blue : Color.gray.opacity(0.2)
                            )
                            .cornerRadius(10)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Current Conditions Card

struct CurrentConditionsCard: View {
    let conditions: WindowConditions

    var body: some View {
        VStack(spacing: 16) {
            // En-tête
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Conditions Actuelles")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(conditions.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()

                // Score et statut
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(conditions.score)")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(statusColor(conditions.status))

                    HStack(spacing: 4) {
                        Text(conditions.status.emoji)
                        Text(conditions.status.description)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(conditions.status))
                    .cornerRadius(6)
                }
            }

            // Paramètres météo
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ConditionParameter(
                    icon: "eye",
                    label: "Visibilité",
                    value: "\(String(format: "%.1f", conditions.visibility)) SM",
                    color: visibilityColor(conditions.visibility)
                )

                ConditionParameter(
                    icon: "wind",
                    label: "Vent",
                    value: conditions.gustSpeed != nil ?
                    "\(conditions.windSpeed)G\(conditions.gustSpeed!) kt" :
                    "\(conditions.windSpeed) kt",
                    color: windColor(conditions.windSpeed, gust: conditions.gustSpeed)
                )

                ConditionParameter(
                    icon: "cloud",
                    label: "Plafond",
                    value: conditions.ceiling != nil ? "\(conditions.ceiling!) ft" : "Aucun",
                    color: ceilingColor(conditions.ceiling)
                )

                ConditionParameter(
                    icon: "thermometer",
                    label: "Écart T-Td",
                    value: "\(String(format: "%.1f", conditions.spread))°C",
                    color: spreadColor(conditions.spread)
                )
            }

            // Restrictions
            if !conditions.restrictions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Restrictions")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }

                    ForEach(conditions.restrictions, id: \.self) { restriction in
                        HStack {
                            Text("•")
                                .foregroundColor(.orange)
                            Text(restriction)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.2))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
    }

    private func statusColor(_ status: WindowStatus) -> Color {
        switch status.color {
        case "green": return .green
        case "lightGreen": return .green.opacity(0.7)
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        default: return .gray
        }
    }

    private func visibilityColor(_ vis: Double) -> Color {
        if vis >= 10 { return .green }
        else if vis >= 5 { return .yellow }
        else if vis >= 3 { return .orange }
        else { return .red }
    }

    private func windColor(_ wind: Int, gust: Int?) -> Color {
        let maxWind = gust ?? wind
        if maxWind > 25 { return .red }
        else if maxWind > 15 { return .orange }
        else if maxWind > 10 { return .yellow }
        else { return .green }
    }

    private func ceilingColor(_ ceiling: Int?) -> Color {
        guard let ceiling = ceiling else { return .green }
        if ceiling < 1000 { return .red }
        else if ceiling < 3000 { return .orange }
        else { return .yellow }
    }

    private func spreadColor(_ spread: Double) -> Color {
        if spread < 2 { return .orange }
        else if spread < 3 { return .yellow }
        else { return .green }
    }
}

struct ConditionParameter: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)

            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)

            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.2))
        .cornerRadius(8)
    }
}

// MARK: - Recommendations Section

struct RecommendationsSection: View {
    let recommendations: [WindowRecommendation]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Recommandations")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            ForEach(recommendations) { recommendation in
                RecommendationCard(recommendation: recommendation)
            }
        }
    }
}

struct RecommendationCard: View {
    let recommendation: WindowRecommendation

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: recommendation.type.icon)
                .font(.title2)
                .foregroundColor(typeColor(recommendation.type.color))
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(recommendation.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(recommendation.message)
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()
        }
        .padding()
        .background(typeColor(recommendation.type.color).opacity(0.2))
        .cornerRadius(10)
    }

    private func typeColor(_ colorName: String) -> Color {
        switch colorName {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "gray": return .gray
        default: return .gray
        }
    }
}

// MARK: - Window Timeline Section

struct WindowTimelineSection: View {
    let windows: [FlightWindow]
    @Binding var selectedWindow: FlightWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "timeline.selection")
                    .foregroundColor(.white)
                Text("Timeline des Fenêtres")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            ForEach(windows.prefix(12)) { window in
                WindowTimelineCard(window: window)
                    .onTapGesture {
                        selectedWindow = window
                    }
            }
        }
    }
}

struct WindowTimelineCard: View {
    let window: FlightWindow

    var body: some View {
        HStack(spacing: 12) {
            // Timeline indicator
            VStack {
                Circle()
                    .fill(statusColor(window.status))
                    .frame(width: 16, height: 16)

                Rectangle()
                    .fill(statusColor(window.status).opacity(0.3))
                    .frame(width: 2, height: 40)
            }

            // Window info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(window.timeRange)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    Spacer()

                    Text("\(window.score)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(statusColor(window.status))

                    if window.isRecommended {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                    }
                }

                // Status badge
                HStack(spacing: 4) {
                    Text(window.status.emoji)
                        .font(.caption)
                    Text(window.status.description)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor(window.status))
                .cornerRadius(6)

                // Key conditions
                HStack(spacing: 16) {
                    ConditionBadge(
                        icon: "eye",
                        value: "\(String(format: "%.1f", window.conditions.visibility)) SM"
                    )

                    ConditionBadge(
                        icon: "wind",
                        value: "\(window.conditions.windSpeed) kt"
                    )

                    if let ceiling = window.conditions.ceiling {
                        ConditionBadge(
                            icon: "cloud",
                            value: "\(ceiling) ft"
                        )
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .padding()
        .background(
            window.isRecommended ?
            Color.green.opacity(0.1) : Color.gray.opacity(0.2)
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(window.isRecommended ? Color.green : Color.clear, lineWidth: 2)
        )
    }

    private func statusColor(_ status: WindowStatus) -> Color {
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

struct ConditionBadge: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.gray)
            Text(value)
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Window Score Chart

struct WindowScoreChart: View {
    let windows: [FlightWindow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.white)
                Text("Évolution des Scores")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            Chart {
                ForEach(windows.prefix(12)) { window in
                    LineMark(
                        x: .value("Heure", window.startTime),
                        y: .value("Score", window.score)
                    )
                    .foregroundStyle(scoreGradient)
                    .lineStyle(StrokeStyle(lineWidth: 3))

                    AreaMark(
                        x: .value("Heure", window.startTime),
                        y: .value("Score", window.score)
                    )
                    .foregroundStyle(scoreGradient.opacity(0.3))

                    // Mark recommended windows
                    if window.isRecommended {
                        PointMark(
                            x: .value("Heure", window.startTime),
                            y: .value("Score", window.score)
                        )
                        .foregroundStyle(Color.green)
                        .symbolSize(100)
                    }
                }

                // Reference lines
                RuleMark(y: .value("Excellent", 80))
                    .foregroundStyle(Color.green.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                RuleMark(y: .value("Acceptable", 60))
                    .foregroundStyle(Color.yellow.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                RuleMark(y: .value("Marginal", 40))
                    .foregroundStyle(Color.orange.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }
            .frame(height: 250)
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
                    AxisValueLabel(format: .dateTime.hour())
                        .foregroundStyle(Color.white)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
    }

    private var scoreGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [.blue, .cyan]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Window Detail Sheet

struct WindowDetailSheet: View {
    let window: FlightWindow

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // En-tête
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(window.timeRange)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)

                                    Text("Durée: \(window.formattedDuration)")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }

                                Spacer()

                                Text("\(window.score)")
                                    .font(.system(size: 50, weight: .bold))
                                    .foregroundColor(statusColor(window.status))
                            }

                            HStack(spacing: 4) {
                                Text(window.status.emoji)
                                Text(window.status.description)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(statusColor(window.status))
                            .cornerRadius(8)
                            .frame(maxWidth: .infinity)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(12)

                        // Facteurs détaillés
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Facteurs d'Analyse")
                                .font(.headline)
                                .foregroundColor(.white)

                            ForEach(window.conditions.factors, id: \.description) { factor in
                                FactorRow(factor: factor)
                            }
                        }

                        // Restrictions
                        if !window.conditions.restrictions.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Restrictions")
                                    .font(.headline)
                                    .foregroundColor(.white)

                                ForEach(window.conditions.restrictions, id: \.self) { restriction in
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        Text(restriction)
                                            .font(.subheadline)
                                            .foregroundColor(.orange)
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.orange.opacity(0.2))
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Détails Fenêtre")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func statusColor(_ status: WindowStatus) -> Color {
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

struct FactorRow: View {
    let factor: ConditionFactor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: factor.impact.icon)
                .foregroundColor(impactColor(factor.impact.color))
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(factor.description)
                    .font(.subheadline)
                    .foregroundColor(.white)

                if factor.points != 0 {
                    Text("\(factor.points > 0 ? "+" : "")\(factor.points) pts")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
    }

    private func impactColor(_ colorName: String) -> Color {
        switch colorName {
        case "green": return .green
        case "gray": return .gray
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        default: return .gray
        }
    }
}

// MARK: - Empty State & Error

struct WindowEmptyState: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 80))
                .foregroundColor(.gray)

            Text("Aucune analyse en cours")
                .font(.headline)
                .foregroundColor(.white)

            Text("Recherchez un aérodrome et sélectionnez votre type de vol")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }
}

struct WindowErrorCard: View {
    let error: FlightWindowError

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

struct FlightWindowView_Previews: PreviewProvider {
    static var previews: some View {
        FlightWindowView()
            .preferredColorScheme(.dark)
    }
}
