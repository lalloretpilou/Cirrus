//
//  RouteWeatherView.swift
//  Cirrus
//
//  Vue interactive des conditions météo en route
//

import SwiftUI
import MapKit

struct RouteWeatherView: View {
    @StateObject private var routeService = RouteWeatherService.shared
    @StateObject private var aviationService = AviationWeatherService.shared

    @State private var departureAerodrome: Aerodrome?
    @State private var arrivalAerodrome: Aerodrome?
    @State private var cruiseAltitude = 5500
    @State private var showAerodromeSearch = false
    @State private var searchingFor: SearchType = .departure

    enum SearchType {
        case departure
        case arrival
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.1, blue: 0.25), Color(red: 0.1, green: 0.15, blue: 0.35)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if routeService.isLoading {
                    LoadingView(message: "Analyse de la route...")
                } else if let summary = routeService.routeSummary {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Résumé de route
                            RouteSummaryCard(summary: summary)
                                .padding(.horizontal)

                            // Visualisation continue de la route
                            RouteVisualization(segments: routeService.routeSegments)
                                .padding(.horizontal)

                            // Détails des segments
                            SegmentsDetailView(segments: routeService.routeSegments)
                                .padding(.horizontal)

                            // Dangers identifiés
                            if !summary.hazards.isEmpty {
                                HazardsSection(hazards: summary.hazards)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                } else {
                    // Configuration initiale
                    RouteSetupView(
                        departureAerodrome: $departureAerodrome,
                        arrivalAerodrome: $arrivalAerodrome,
                        cruiseAltitude: $cruiseAltitude,
                        onSearch: { type in
                            searchingFor = type
                            showAerodromeSearch = true
                        },
                        onAnalyze: analyzeRoute
                    )
                }
            }
            .navigationTitle("Météo en Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: reset) {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(isPresented: $showAerodromeSearch) {
                AerodromeSearchSheet(
                    selectedAerodrome: searchingFor == .departure ? $departureAerodrome : $arrivalAerodrome,
                    title: searchingFor == .departure ? "Aérodrome de départ" : "Aérodrome d'arrivée"
                )
            }
        }
    }

    private func analyzeRoute() {
        guard let departure = departureAerodrome,
              let arrival = arrivalAerodrome else {
            return
        }

        let departurePoint = RoutePoint(
            name: departure.name,
            icaoCode: departure.icaoCode,
            coordinate: departure.location.coordinate
        )

        let arrivalPoint = RoutePoint(
            name: arrival.name,
            icaoCode: arrival.icaoCode,
            coordinate: arrival.location.coordinate
        )

        Task {
            await routeService.analyzeRoute(
                from: departurePoint,
                to: arrivalPoint,
                cruiseAltitude: cruiseAltitude
            )
        }
    }

    private func reset() {
        routeService.routeSegments = []
        routeService.routeSummary = nil
        departureAerodrome = nil
        arrivalAerodrome = nil
        cruiseAltitude = 5500
    }
}

// MARK: - Route Setup View

struct RouteSetupView: View {
    @Binding var departureAerodrome: Aerodrome?
    @Binding var arrivalAerodrome: Aerodrome?
    @Binding var cruiseAltitude: Int

    let onSearch: (RouteWeatherView.SearchType) -> Void
    let onAnalyze: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Titre
            VStack(spacing: 8) {
                Text("🛣️ Analyse Météo de Route")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Conditions météo continues du départ à l'arrivée")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding()

            // Sélection départ
            Button(action: { onSearch(.departure) }) {
                HStack {
                    Image(systemName: "airplane.departure")
                        .font(.title2)
                        .foregroundColor(.green)
                        .frame(width: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Départ")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))

                        if let departure = departureAerodrome {
                            Text("\(departure.icaoCode) - \(departure.name)")
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

            // Sélection arrivée
            Button(action: { onSearch(.arrival) }) {
                HStack {
                    Image(systemName: "airplane.arrival")
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Arrivée")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))

                        if let arrival = arrivalAerodrome {
                            Text("\(arrival.icaoCode) - \(arrival.name)")
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

            // Altitude de croisière
            VStack(alignment: .leading, spacing: 8) {
                Text("Altitude de croisière")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                HStack {
                    Slider(value: Binding(
                        get: { Double(cruiseAltitude) },
                        set: { cruiseAltitude = Int($0) }
                    ), in: 2000...12000, step: 500)
                        .tint(.blue)

                    Text("\(cruiseAltitude) ft")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 80)
                }
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)

            // Bouton analyser
            Button(action: onAnalyze) {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("Analyser la route")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canAnalyze ? Color.blue : Color.gray.opacity(0.5))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!canAnalyze)
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 40)
    }

    private var canAnalyze: Bool {
        departureAerodrome != nil && arrivalAerodrome != nil
    }
}

// MARK: - Route Summary Card

struct RouteSummaryCard: View {
    let summary: RouteSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // En-tête
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(summary.departure.icaoCode ?? "????") → \(summary.arrival.icaoCode ?? "????")")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("\(Int(summary.totalDistance)) NM @ \(summary.cruiseAltitude) ft")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                Text(summary.recommendation.emoji)
                    .font(.system(size: 50))
            }

            Divider()
                .background(Color.white.opacity(0.3))

            // Recommandation
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recommandation")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))

                    Text(summary.recommendation.description)
                        .font(.headline)
                        .foregroundColor(.white)
                }

                Spacer()
            }
            .padding()
            .background(recommendationColor(summary.recommendation).opacity(0.2))
            .cornerRadius(8)

            // Statistiques des segments
            VStack(spacing: 12) {
                Text("Répartition des conditions")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                // Barre de progression
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        if summary.percentageGood > 0 {
                            Rectangle()
                                .fill(Color.green)
                                .frame(width: geometry.size.width * summary.percentageGood / 100)
                        }
                        if summary.percentageCaution > 0 {
                            Rectangle()
                                .fill(Color.yellow)
                                .frame(width: geometry.size.width * summary.percentageCaution / 100)
                        }
                        if summary.percentageMarginal > 0 {
                            Rectangle()
                                .fill(Color.orange)
                                .frame(width: geometry.size.width * summary.percentageMarginal / 100)
                        }
                        if summary.percentageCritical > 0 {
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: geometry.size.width * summary.percentageCritical / 100)
                        }
                    }
                    .cornerRadius(4)
                }
                .frame(height: 20)

                // Légende
                HStack(spacing: 16) {
                    LegendItem(color: .green, label: "Bon", count: summary.goodSegments)
                    LegendItem(color: .yellow, label: "Prudence", count: summary.cautionSegments)
                    LegendItem(color: .orange, label: "Marginal", count: summary.marginalSegments)
                    LegendItem(color: .red, label: "Critique", count: summary.criticalSegments)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }

    private func recommendationColor(_ recommendation: RouteRecommendation) -> Color {
        switch recommendation {
        case .recommended: return .green
        case .caution: return .yellow
        case .ifrOnly: return .orange
        case .notRecommended: return .red
        }
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text("\(label) (\(count))")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

// MARK: - Route Visualization

struct RouteVisualization: View {
    let segments: [RouteSegment]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conditions en route (continue)")
                .font(.headline)
                .foregroundColor(.white)

            // Timeline horizontale
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(segments) { segment in
                        SegmentIndicator(segment: segment)
                    }
                }
            }
            .frame(height: 80)
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}

struct SegmentIndicator: View {
    let segment: RouteSegment

    var body: some View {
        VStack(spacing: 4) {
            // Statut visuel
            Rectangle()
                .fill(statusColor(segment.status))
                .frame(width: 40, height: 40)
                .cornerRadius(6)
                .overlay(
                    Text(segment.status.emoji)
                        .font(.title3)
                )

            // Distance
            Text("\(Int(segment.waypoint.distanceFromDeparture)) NM")
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private func statusColor(_ status: SegmentStatus) -> Color {
        switch status {
        case .good: return .green.opacity(0.8)
        case .caution: return .yellow.opacity(0.8)
        case .marginal: return .orange.opacity(0.8)
        case .critical: return .red.opacity(0.8)
        }
    }
}

// MARK: - Segments Detail View

struct SegmentsDetailView: View {
    let segments: [RouteSegment]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Détails des segments")
                .font(.headline)
                .foregroundColor(.white)

            ForEach(segments.filter { $0.status != .good || !$0.hazards.isEmpty }) { segment in
                SegmentDetailCard(segment: segment)
            }

            if segments.allSatisfy({ $0.status == .good && $0.hazards.isEmpty }) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Excellentes conditions sur toute la route !")
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color.green.opacity(0.2))
                .cornerRadius(8)
            }
        }
    }
}

struct SegmentDetailCard: View {
    let segment: RouteSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // En-tête
            HStack {
                Text("Segment \(segment.segmentNumber)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text("@ \(Int(segment.waypoint.distanceFromDeparture)) NM")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                Text(segment.status.emoji)
                Text(segment.status.description)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(segment.status))
                    .cornerRadius(4)
            }

            // Conditions
            HStack(spacing: 16) {
                ConditionBadge(
                    icon: "thermometer",
                    value: "\(Int(segment.conditions.temperature))°C"
                )

                ConditionBadge(
                    icon: "wind",
                    value: "\(segment.conditions.windDirection)°/\(segment.conditions.windSpeed)kt"
                )

                ConditionBadge(
                    icon: "eye",
                    value: "\(String(format: "%.0f", segment.conditions.visibility)) SM"
                )

                if let ceiling = segment.conditions.ceiling {
                    ConditionBadge(
                        icon: "cloud",
                        value: "\(ceiling) ft"
                    )
                }
            }

            // Dangers
            if !segment.hazards.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(segment.hazards) { hazard in
                        HStack(spacing: 8) {
                            Image(systemName: hazard.type.icon)
                                .foregroundColor(hazardColor(hazard.severity))
                                .frame(width: 20)

                            Text(hazard.description)
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
    }

    private func statusColor(_ status: SegmentStatus) -> Color {
        switch status {
        case .good: return .green
        case .caution: return .yellow
        case .marginal: return .orange
        case .critical: return .red
        }
    }

    private func hazardColor(_ severity: RouteHazard.Severity) -> Color {
        switch severity {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
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
                .foregroundColor(.blue)
            Text(value)
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.1))
        .cornerRadius(6)
    }
}

// MARK: - Hazards Section

struct HazardsSection: View {
    let hazards: [RouteHazard]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("⚠️ Dangers identifiés")
                .font(.headline)
                .foregroundColor(.white)

            let groupedHazards = Dictionary(grouping: hazards, by: { $0.type })

            ForEach(Array(groupedHazards.keys), id: \.self) { type in
                if let hazardsList = groupedHazards[type] {
                    HazardTypeCard(type: type, count: hazardsList.count, hazards: hazardsList)
                }
            }
        }
    }
}

struct HazardTypeCard: View {
    let type: RouteHazard.HazardType
    let count: Int
    let hazards: [RouteHazard]

    var body: some View {
        HStack {
            Image(systemName: type.icon)
                .font(.title2)
                .foregroundColor(.orange)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(typeName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text("\(count) segment(s) affecté(s)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.2))
        .cornerRadius(8)
    }

    private var typeName: String {
        switch type {
        case .strongWind: return "Vent fort"
        case .lowVisibility: return "Visibilité réduite"
        case .lowCeiling: return "Plafond bas"
        case .icing: return "Givrage"
        case .thunderstorm: return "Orages"
        case .turbulence: return "Turbulence"
        case .precipitation: return "Précipitations"
        }
    }
}

// MARK: - Aerodrome Search Sheet

struct AerodromeSearchSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var aviationService = AviationWeatherService.shared
    @Binding var selectedAerodrome: Aerodrome?
    let title: String

    @State private var searchText = ""
    @State private var searchResults: [Aerodrome] = []
    @State private var isSearching = false

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.15, blue: 0.3)
                    .ignoresSafeArea()

                VStack {
                    // Barre de recherche
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.6))

                        TextField("Code OACI ou nom", text: $searchText)
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                            .autocapitalization(.allCharacters)
                            .onChange(of: searchText) { _ in
                                Task {
                                    await performSearch()
                                }
                            }

                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                    .padding()

                    // Résultats
                    if isSearching {
                        ProgressView()
                            .tint(.white)
                    } else if !searchResults.isEmpty {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(searchResults) { aerodrome in
                                    Button(action: {
                                        selectedAerodrome = aerodrome
                                        dismiss()
                                    }) {
                                        AerodromeSearchRow(aerodrome: aerodrome)
                                    }
                                }
                            }
                            .padding()
                        }
                    } else if !searchText.isEmpty {
                        Text("Aucun aérodrome trouvé")
                            .foregroundColor(.white.opacity(0.6))
                            .padding()
                    } else {
                        Text("Entrez un code OACI ou nom")
                            .foregroundColor(.white.opacity(0.6))
                            .padding()
                    }

                    Spacer()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Annuler") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    private func performSearch() async {
        guard searchText.count >= 2 else {
            searchResults = []
            return
        }

        isSearching = true

        do {
            searchResults = try await aviationService.searchAerodromes(query: searchText)
        } catch {
            searchResults = []
        }

        isSearching = false
    }
}

struct AerodromeSearchRow: View {
    let aerodrome: Aerodrome

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(aerodrome.icaoCode)
                    .font(.headline)
                    .foregroundColor(.white)

                Text(aerodrome.name)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))

                Text("\(aerodrome.location.city), \(aerodrome.location.country)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.5))
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Helper View

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
    RouteWeatherView()
}
