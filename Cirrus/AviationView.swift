//
//  AviationView.swift
//  Cirrus
//
//  Professional aviation weather view for pilots
//

import SwiftUI
import CoreLocation
import MapKit

struct AviationView: View {
    @StateObject private var aviationService = AviationWeatherService.shared
    @StateObject private var recommendationService = FlightRecommendationService.shared
    @StateObject private var locationManager = LocationManager()

    @State private var selectedAerodrome: Aerodrome?
    @State private var searchText = ""
    @State private var showAerodromeSearch = false
    @State private var selectedTab = 0

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.15, blue: 0.3), Color(red: 0.1, green: 0.2, blue: 0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if aviationService.isLoading {
                    LoadingView()
                } else if let error = aviationService.error {
                    ErrorView(error: error)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Header with aerodrome selection
                            AerodromeHeader(
                                selectedAerodrome: selectedAerodrome,
                                onTapSearch: { showAerodromeSearch = true }
                            )
                            .padding(.horizontal)

                            // Flight Rules Indicator
                            if let metar = aviationService.currentMETAR {
                                FlightRulesCard(metar: metar)
                                    .padding(.horizontal)
                            }

                            // Recommendation Card
                            if let recommendation = recommendationService.currentRecommendation {
                                RecommendationCard(recommendation: recommendation)
                                    .padding(.horizontal)
                            }

                            // Quick Access - Fonctionnalités avancées
                            QuickAccessSection()
                                .padding(.horizontal)

                            // Tabs: METAR, TAF, Winds Aloft, Nearby
                            TabSelector(selectedTab: $selectedTab)
                                .padding(.horizontal)

                            // Content based on selected tab
                            Group {
                                switch selectedTab {
                                case 0:
                                    METARView(metar: aviationService.currentMETAR)
                                case 1:
                                    TAFView(taf: aviationService.currentTAF)
                                case 2:
                                    WindsAloftView(winds: aviationService.windsAloft)
                                case 3:
                                    NearbyAerodromesView(aerodromes: aviationService.nearbyAerodromes)
                                default:
                                    EmptyView()
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Météo Aviation")
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
                AerodromeSearchView(selectedAerodrome: $selectedAerodrome)
            }
            .task {
                await loadInitialData()
            }
            .onChange(of: selectedAerodrome) { _ in
                Task {
                    await refreshData()
                }
            }
        }
    }

    private func loadInitialData() async {
        if let location = locationManager.currentLocation {
            await aviationService.fetchAviationWeather(for: location.coordinate)

            if let metar = aviationService.currentMETAR,
               let aerodrome = aviationService.nearbyAerodromes.first {
                let recommendation = recommendationService.generateRecommendation(
                    metar: metar,
                    taf: aviationService.currentTAF,
                    windsAloft: aviationService.windsAloft,
                    aerodrome: aerodrome
                )
            }
        }
    }

    private func refreshData() async {
        if let aerodrome = selectedAerodrome {
            let coordinate = aerodrome.location.coordinate
            await aviationService.fetchAviationWeather(for: coordinate)

            if let metar = aviationService.currentMETAR {
                let recommendation = recommendationService.generateRecommendation(
                    metar: metar,
                    taf: aviationService.currentTAF,
                    windsAloft: aviationService.windsAloft,
                    aerodrome: aerodrome
                )
            }
        } else if let location = locationManager.currentLocation {
            await aviationService.fetchAviationWeather(for: location.coordinate)

            if let metar = aviationService.currentMETAR,
               let aerodrome = aviationService.nearbyAerodromes.first {
                let recommendation = recommendationService.generateRecommendation(
                    metar: metar,
                    taf: aviationService.currentTAF,
                    windsAloft: aviationService.windsAloft,
                    aerodrome: aerodrome
                )
            }
        }
    }
}

// MARK: - Aerodrome Header

struct AerodromeHeader: View {
    let selectedAerodrome: Aerodrome?
    let onTapSearch: () -> Void

    var body: some View {
        Button(action: onTapSearch) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedAerodrome?.icaoCode ?? "Rechercher un aérodrome")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    if let aerodrome = selectedAerodrome {
                        Text(aerodrome.name)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))

                        Text("\(aerodrome.location.city), \(aerodrome.location.country)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }

                Spacer()

                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white)
                    .font(.title3)
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

// MARK: - Flight Rules Card

struct FlightRulesCard: View {
    let metar: METAR

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(metar.flightRules.emoji)
                    .font(.system(size: 40))

                VStack(alignment: .leading) {
                    Text("Conditions de vol")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))

                    Text(metar.flightRules.description)
                        .font(.headline)
                        .foregroundColor(.white)
                }

                Spacer()
            }

            Divider()
                .background(Color.white.opacity(0.3))

            HStack {
                VStack(alignment: .leading) {
                    Text("Observation")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))

                    Text(metar.observationTime, style: .time)
                        .font(.subheadline)
                        .foregroundColor(.white)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("Station")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))

                    Text(metar.station)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Recommendation Card

struct RecommendationCard: View {
    let recommendation: FlightRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Flight Type
            HStack {
                Text(recommendation.flightType.emoji)
                    .font(.system(size: 40))

                VStack(alignment: .leading) {
                    Text("Recommandation")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))

                    Text(recommendation.flightType.description)
                        .font(.headline)
                        .foregroundColor(.white)
                }

                Spacer()
            }

            // Recommended Altitude
            VStack(alignment: .leading, spacing: 8) {
                Text("Altitude recommandée")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                HStack(spacing: 20) {
                    AltitudeInfo(label: "Min", value: recommendation.recommendedAltitude.minimum)
                    AltitudeInfo(label: "Optimal", value: recommendation.recommendedAltitude.optimal, highlighted: true)
                    AltitudeInfo(label: "Max", value: recommendation.recommendedAltitude.maximum)
                }

                Text(recommendation.recommendedAltitude.reason)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }

            // Warnings
            if !recommendation.warnings.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.3))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Alertes")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    ForEach(recommendation.warnings, id: \.message) { warning in
                        HStack {
                            Text(warning.type.emoji)
                            Text(warning.message)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(severityColor(warning.severity).opacity(0.2))
                        .cornerRadius(6)
                    }
                }
            }

            // Favorable Factors
            if !recommendation.favorableFactors.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.3))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Facteurs favorables")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    ForEach(recommendation.favorableFactors, id: \.self) { factor in
                        Text(factor)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }

    private func severityColor(_ severity: AviationHazard.Severity) -> Color {
        switch severity {
        case .light: return .yellow
        case .moderate: return .orange
        case .severe: return .red
        }
    }
}

struct AltitudeInfo: View {
    let label: String
    let value: Int
    var highlighted: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))

            Text("\(value) ft")
                .font(highlighted ? .headline : .subheadline)
                .fontWeight(highlighted ? .bold : .regular)
                .foregroundColor(highlighted ? .green : .white)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(highlighted ? Color.green.opacity(0.2) : Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Tab Selector

struct TabSelector: View {
    @Binding var selectedTab: Int

    var body: some View {
        HStack(spacing: 12) {
            TabButton(title: "METAR", index: 0, selectedTab: $selectedTab)
            TabButton(title: "TAF", index: 1, selectedTab: $selectedTab)
            TabButton(title: "Vents", index: 2, selectedTab: $selectedTab)
            TabButton(title: "Proches", index: 3, selectedTab: $selectedTab)
        }
    }
}

struct TabButton: View {
    let title: String
    let index: Int
    @Binding var selectedTab: Int

    var body: some View {
        Button(action: { selectedTab = index }) {
            Text(title)
                .font(.subheadline)
                .fontWeight(selectedTab == index ? .bold : .regular)
                .foregroundColor(selectedTab == index ? .white : .white.opacity(0.6))
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(selectedTab == index ? Color.blue : Color.white.opacity(0.1))
                .cornerRadius(8)
        }
    }
}

// MARK: - METAR View

struct METARView: View {
    let metar: METAR?

    var body: some View {
        if let metar = metar {
            VStack(alignment: .leading, spacing: 16) {
                // Raw METAR
                VStack(alignment: .leading, spacing: 8) {
                    Text("METAR Brut")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(metar.rawText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.green)
                        .padding()
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(8)
                }

                // Wind
                WeatherDataRow(label: "Vent", value: formatWind(metar.wind), icon: "wind")

                // Visibility
                WeatherDataRow(
                    label: "Visibilité",
                    value: "\(String(format: "%.1f", metar.visibility.value)) \(metar.visibility.unit)",
                    icon: "eye"
                )

                // Temperature & Dewpoint
                WeatherDataRow(
                    label: "Température",
                    value: "\(Int(metar.temperature.celsius))°C / \(Int(metar.temperature.fahrenheit))°F",
                    icon: "thermometer"
                )

                WeatherDataRow(
                    label: "Point de rosée",
                    value: "\(Int(metar.dewpoint))°C",
                    icon: "drop"
                )

                // Altimeter
                WeatherDataRow(
                    label: "Altimètre",
                    value: String(format: "%.2f inHg / %.0f hPa", metar.altimeter.inHg, metar.altimeter.hPa),
                    icon: "gauge"
                )

                // Clouds
                if !metar.clouds.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "cloud")
                                .foregroundColor(.blue)
                            Text("Nuages")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }

                        ForEach(metar.clouds) { cloud in
                            HStack {
                                Text(cloud.coverage.rawValue)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(4)

                                Text("\(cloud.altitude) ft AGL")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))

                                if let type = cloud.type {
                                    Text(type)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }

                                Spacer()

                                Text(cloud.coverage.description)
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                }

                // Density Altitude
                if let aerodrome = AviationWeatherService.shared.nearbyAerodromes.first {
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

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(densityAlt.performanceImpact.emoji)
                            Text("Altitude densité")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }

                        HStack {
                            VStack(alignment: .leading) {
                                Text("Altitude pression")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                                Text("\(densityAlt.pressureAltitude) ft")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }

                            Spacer()

                            VStack(alignment: .trailing) {
                                Text("Altitude densité")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                                Text("\(densityAlt.densityAltitude) ft")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                            }
                        }

                        Text(densityAlt.performanceImpact.description)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        } else {
            Text("Aucun METAR disponible")
                .foregroundColor(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        }
    }

    private func formatWind(_ wind: METAR.Wind) -> String {
        if let dir = wind.direction {
            let gust = wind.gust != nil ? "G\(wind.gust!)kt" : ""
            return "\(String(format: "%03d", dir))° à \(wind.speed)kt \(gust)"
        } else {
            return "Variable à \(wind.speed)kt"
        }
    }
}

// MARK: - TAF View

struct TAFView: View {
    let taf: TAF?

    var body: some View {
        if let taf = taf {
            VStack(alignment: .leading, spacing: 16) {
                // Raw TAF
                VStack(alignment: .leading, spacing: 8) {
                    Text("TAF Brut")
                        .font(.headline)
                        .foregroundColor(.white)

                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(taf.rawText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.green)
                            .padding()
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(8)
                    }
                }

                // Validity
                HStack {
                    Text("Valide de")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    Text(taf.validFrom, style: .time)
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Text("à")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    Text(taf.validTo, style: .time)
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)

                // Forecast periods
                ForEach(taf.forecasts) { forecast in
                    TAFForecastCard(forecast: forecast)
                }
            }
        } else {
            Text("Aucun TAF disponible")
                .foregroundColor(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        }
    }
}

struct TAFForecastCard: View {
    let forecast: TAF.ForecastPeriod

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(forecast.type.rawValue)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(4)

                Text(forecast.startTime, style: .time)
                    .font(.subheadline)
                    .foregroundColor(.white)
                Text("-")
                    .foregroundColor(.white.opacity(0.6))
                Text(forecast.endTime, style: .time)
                    .font(.subheadline)
                    .foregroundColor(.white)

                Spacer()

                if let prob = forecast.probability {
                    Text("\(prob)%")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            // Conditions
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Vent")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                    if let dir = forecast.wind.direction {
                        Text("\(String(format: "%03d", dir))°/\(forecast.wind.speed)kt")
                            .font(.caption)
                            .foregroundColor(.white)
                    } else {
                        Text("VRB/\(forecast.wind.speed)kt")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }

                VStack(alignment: .leading) {
                    Text("Visibilité")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                    Text("\(String(format: "%.0f", forecast.visibility.value)) \(forecast.visibility.unit)")
                        .font(.caption)
                        .foregroundColor(.white)
                }

                if !forecast.clouds.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Nuages")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                        Text(forecast.clouds.first?.coverage.rawValue ?? "CLR")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Winds Aloft View

struct WindsAloftView: View {
    let winds: WindsAloft?

    var body: some View {
        if let winds = winds {
            VStack(alignment: .leading, spacing: 12) {
                Text("Vents en altitude")
                    .font(.headline)
                    .foregroundColor(.white)

                ForEach(winds.levels) { level in
                    HStack {
                        Text("\(level.altitude) ft")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(width: 80, alignment: .leading)

                        if let direction = level.direction {
                            Text("\(String(format: "%03d", direction))°")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 50)
                        } else {
                            Text("CALM")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 50)
                        }

                        Text("\(level.speed) kt")
                            .font(.caption)
                            .foregroundColor(.cyan)
                            .frame(width: 60)

                        Spacer()

                        Text("\(level.temperature)°C")
                            .font(.caption)
                            .foregroundColor(temperatureColor(level.temperature))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        } else {
            Text("Aucune donnée de vents en altitude disponible")
                .foregroundColor(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        }
    }

    private func temperatureColor(_ temp: Int) -> Color {
        if temp > 0 { return .orange }
        else if temp > -10 { return .white }
        else { return .cyan }
    }
}

// MARK: - Nearby Aerodromes View

struct NearbyAerodromesView: View {
    let aerodromes: [Aerodrome]

    var body: some View {
        if !aerodromes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Aérodromes à proximité")
                    .font(.headline)
                    .foregroundColor(.white)

                ForEach(aerodromes) { aerodrome in
                    AerodromeRow(aerodrome: aerodrome)
                }
            }
        } else {
            Text("Aucun aérodrome à proximité")
                .foregroundColor(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        }
    }
}

struct AerodromeRow: View {
    let aerodrome: Aerodrome

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(aerodrome.icaoCode)
                    .font(.headline)
                    .foregroundColor(.white)

                if aerodrome.hasMETAR {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }

                Spacer()

                Text("\(aerodrome.elevation) ft")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }

            Text(aerodrome.name)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))

            Text("\(aerodrome.location.city), \(aerodrome.location.country)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Helper Views

struct WeatherDataRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)

            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text("Chargement des données aviation...")
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

struct ErrorView: View {
    let error: AviationWeatherError

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)

            Text("Erreur")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

// MARK: - Aerodrome Search View

struct AerodromeSearchView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var aviationService = AviationWeatherService.shared
    @Binding var selectedAerodrome: Aerodrome?
    @State private var searchText = ""
    @State private var searchResults: [Aerodrome] = []
    @State private var isSearching = false

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.15, blue: 0.3)
                    .ignoresSafeArea()

                VStack {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.6))

                        TextField("Code OACI ou nom d'aérodrome", text: $searchText)
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

                    // Results
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
                                        AerodromeRow(aerodrome: aerodrome)
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
                        Text("Entrez un code OACI ou un nom d'aérodrome")
                            .foregroundColor(.white.opacity(0.6))
                            .padding()
                    }

                    Spacer()
                }
            }
            .navigationTitle("Rechercher un aérodrome")
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

// MARK: - Quick Access Section

struct QuickAccessSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🚀 Fonctionnalités Avancées")
                .font(.headline)
                .foregroundColor(.white)

            // Première rangée: Radar + Givrage
            HStack(spacing: 12) {
                NavigationLink(destination: RadarWeatherView()) {
                    QuickAccessCard(
                        icon: "dot.radiowaves.left.and.right",
                        title: "Radar Météo",
                        subtitle: "Précipitations en temps réel",
                        color: .blue
                    )
                }

                NavigationLink(destination: IcingView()) {
                    QuickAccessCard(
                        icon: "snowflake",
                        title: "Carte Givrage",
                        subtitle: "Risque par altitude",
                        color: .cyan
                    )
                }
            }

            // Deuxième rangée: Brouillard + Crosswind
            HStack(spacing: 12) {
                NavigationLink(destination: FogForecastView()) {
                    QuickAccessCard(
                        icon: "cloud.fog",
                        title: "Brouillard",
                        subtitle: "Dissipation & risques",
                        color: .gray
                    )
                }

                NavigationLink(destination: CrosswindAnalysisView()) {
                    QuickAccessCard(
                        icon: "arrow.left.and.right",
                        title: "Crosswind",
                        subtitle: "Analyse multi-pistes",
                        color: .orange
                    )
                }
            }

            // Troisième rangée: Route + Fenêtre Optimale
            HStack(spacing: 12) {
                NavigationLink(destination: RouteWeatherView()) {
                    QuickAccessCard(
                        icon: "arrow.triangle.turn.up.right.diamond",
                        title: "Météo en Route",
                        subtitle: "Conditions continues",
                        color: .purple
                    )
                }

                NavigationLink(destination: FlightWindowView()) {
                    QuickAccessCard(
                        icon: "calendar.badge.clock",
                        title: "Fenêtre Optimale",
                        subtitle: "Meilleur moment vol",
                        color: .green
                    )
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

struct QuickAccessCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    var fullWidth: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 50, height: 50)

                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding()
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    AviationView()
}
