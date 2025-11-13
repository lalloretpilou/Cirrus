import SwiftUI
import CoreLocation

/// Vue principale pour les données météo aéronautiques
struct AviationView: View {
    @StateObject private var viewModel = AviationViewModel()
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    @EnvironmentObject var premiumManager: PremiumManager

    var body: some View {
        NavigationView {
            ZStack {
                // Fond dégradé aviation
                aviationBackground
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 20) {
                        if viewModel.isLoading {
                            AviationLoadingCard()
                        } else if let aviationData = viewModel.aviationData {
                            aviationContent(aviationData)
                        } else {
                            AviationSetupCard(viewModel: viewModel)
                        }

                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationTitle("Aviation")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    refreshButton
                }
            }
            .sheet(isPresented: $viewModel.showingAirportSearch) {
                AirportSearchSheet(viewModel: viewModel)
            }
        }
        .task {
            await loadInitialData()
        }
    }

    @ViewBuilder
    private func aviationContent(_ data: AviationWeatherData) -> some View {
        // En-tête avec aéroport
        if let airport = data.airport {
            AirportHeaderCard(airport: airport)
        }

        // Recommandation de vol
        FlightRecommendationCard(recommendation: data.recommendation)

        // METAR
        if let metar = data.metar {
            METARCard(metar: metar)
        }

        // TAF
        if let taf = data.taf {
            TAFCard(taf: taf)
        }

        // Aéroports à proximité
        if !data.nearbyAirports.isEmpty {
            NearbyAirportsCard(airports: data.nearbyAirports, viewModel: viewModel)
        }
    }

    private var aviationBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.1, green: 0.2, blue: 0.4),
                Color(red: 0.2, green: 0.3, blue: 0.5)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var refreshButton: some View {
        Button(action: {
            Task {
                await viewModel.refreshData()
            }
        }) {
            Image(systemName: "arrow.clockwise")
                .font(.title3)
                .foregroundColor(.white)
        }
    }

    private func loadInitialData() async {
        // Utiliser la position de l'utilisateur si disponible
        if let userLocation = weatherViewModel.userLocation {
            await viewModel.loadAviationData(for: userLocation)
        }
    }
}

// MARK: - Aviation ViewModel

@MainActor
class AviationViewModel: ObservableObject {
    @Published var aviationData: AviationWeatherData?
    @Published var nearbyAirports: [Airport] = []
    @Published var selectedAirport: Airport?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingAirportSearch = false

    private let aviationService = AviationWeatherService.shared
    private var currentLocation: CLLocation?

    func loadAviationData(for location: CLLocation) async {
        currentLocation = location
        isLoading = true
        errorMessage = nil

        do {
            // Rechercher les aéroports à proximité
            nearbyAirports = try await aviationService.searchNearbyAirports(location: location, radiusKm: 50)

            // Utiliser le plus proche aéroport
            if let closestAirport = nearbyAirports.first {
                selectedAirport = closestAirport

                // Charger les données aviation
                let data = try await aviationService.getAviationWeatherData(
                    for: closestAirport.icaoCode,
                    location: closestAirport.location
                )

                aviationData = data
            } else {
                errorMessage = "Aucun aéroport trouvé à proximité"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadAviationDataForAirport(_ airport: Airport) async {
        isLoading = true
        errorMessage = nil
        selectedAirport = airport

        do {
            let data = try await aviationService.getAviationWeatherData(
                for: airport.icaoCode,
                location: airport.location
            )
            aviationData = data
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refreshData() async {
        if let airport = selectedAirport {
            await loadAviationDataForAirport(airport)
        } else if let location = currentLocation {
            await loadAviationData(for: location)
        }
    }
}

// MARK: - Flight Recommendation Card

struct FlightRecommendationCard: View {
    let recommendation: FlightRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // En-tête avec niveau de sécurité
            safetyHeader

            // Type de vol recommandé
            flightTypeSection

            // Altitude recommandée
            altitudeSection

            // Avertissements
            if !recommendation.warnings.isEmpty {
                warningsSection
            }

            // Conseils
            if !recommendation.advisories.isEmpty {
                advisoriesSection
            }

            // Résumé météo
            weatherSummarySection

            // Fenêtre de départ recommandée
            if let window = recommendation.recommendedDepartureWindow {
                departureWindowSection(window)
            }
        }
        .padding(20)
        .background(cardBackground)
        .cornerRadius(20)
        .shadow(color: safetyColor.opacity(0.3), radius: 10, y: 5)
    }

    private var safetyHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recommandation de vol")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .textCase(.uppercase)
                    .tracking(1)

                Text(recommendation.overallSafety.rawValue)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(safetyColor)
            }

            Spacer()

            safetyIndicator
        }
    }

    private var safetyIndicator: some View {
        ZStack {
            Circle()
                .fill(safetyColor.opacity(0.2))
                .frame(width: 60, height: 60)

            Image(systemName: safetyIcon)
                .font(.title)
                .foregroundColor(safetyColor)
        }
    }

    private var safetyIcon: String {
        switch recommendation.overallSafety {
        case .safe: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .notRecommended: return "xmark.circle.fill"
        case .dangerous: return "xmark.octagon.fill"
        }
    }

    private var safetyColor: Color {
        Color(hex: recommendation.overallSafety.color) ?? .green
    }

    private var flightTypeSection: some View {
        HStack {
            Image(systemName: recommendation.flightType.icon)
                .font(.title2)
                .foregroundColor(.cyan)

            VStack(alignment: .leading, spacing: 4) {
                Text("Type de vol")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))

                Text(recommendation.flightType.rawValue)
                    .font(.headline)
                    .foregroundColor(.white)
            }

            Spacer()
        }
        .padding(16)
        .background(sectionBackground)
        .cornerRadius(12)
    }

    private var altitudeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.up.and.down")
                    .foregroundColor(.orange)

                Text("Altitude recommandée")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }

            HStack {
                altitudePill("Min", value: recommendation.recommendedAltitude.minimumAltitude)
                altitudePill("Optimal", value: recommendation.recommendedAltitude.optimalAltitude)
                altitudePill("Max", value: recommendation.recommendedAltitude.maximumAltitude)
            }

            Text(recommendation.recommendedAltitude.reason)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(16)
        .background(sectionBackground)
        .cornerRadius(12)
    }

    private func altitudePill(_ label: String, value: Int) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))

            Text("\(value)ft")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
    }

    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)

                Text("Avertissements")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }

            ForEach(recommendation.warnings) { warning in
                WarningRow(warning: warning)
            }
        }
        .padding(16)
        .background(sectionBackground)
        .cornerRadius(12)
    }

    private var advisoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)

                Text("Conseils")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }

            ForEach(recommendation.advisories) { advisory in
                AdvisoryRow(advisory: advisory)
            }
        }
        .padding(16)
        .background(sectionBackground)
        .cornerRadius(12)
    }

    private var weatherSummarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Résumé météo")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Text(recommendation.weatherSummary)
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
                .lineSpacing(4)
        }
        .padding(16)
        .background(sectionBackground)
        .cornerRadius(12)
    }

    private func departureWindowSection(_ window: DateInterval) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.green)

                Text("Fenêtre de départ optimale")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }

            HStack {
                Text(formatTime(window.start))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Image(systemName: "arrow.right")
                    .foregroundColor(.white.opacity(0.5))

                Text(formatTime(window.end))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
        .padding(16)
        .background(sectionBackground)
        .cornerRadius(12)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
    }

    private var sectionBackground: some View {
        Color.white.opacity(0.05)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Warning Row

struct WarningRow: View {
    let warning: FlightWarning

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(severityColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(warning.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(warning.description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))

                if let altitudes = warning.affectedAltitudes {
                    Text("Altitudes: \(altitudes.lowerBound)ft - \(altitudes.upperBound)ft")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            Spacer()
        }
    }

    private var severityColor: Color {
        Color(hex: warning.severity.color) ?? .red
    }
}

// MARK: - Advisory Row

struct AdvisoryRow: View {
    let advisory: FlightAdvisory

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: advisory.category.icon)
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 20)

            Text(advisory.message)
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))

            Spacer()
        }
    }
}

// MARK: - METAR Card

struct METARCard: View {
    let metar: METAR

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // En-tête
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2)
                    .foregroundColor(.cyan)

                VStack(alignment: .leading, spacing: 4) {
                    Text("METAR")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(metar.station)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                flightRulesBadge(metar.flightRules)
            }

            // Texte brut
            Text(metar.rawText)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .padding(12)
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)

            // Données décodées
            metarDataGrid
        }
        .padding(20)
        .background(cardBackground)
        .cornerRadius(20)
    }

    private var metarDataGrid: some View {
        VStack(spacing: 12) {
            HStack {
                metarDataItem("Vent", value: "\(metar.windDirection)° / \(Int(metar.windSpeed))kt", icon: "wind")
                Spacer()
                metarDataItem("Visibilité", value: "\(Int(metar.visibility/1000))km", icon: "eye.fill")
            }

            HStack {
                metarDataItem("Température", value: "\(Int(metar.temperature))°C", icon: "thermometer")
                Spacer()
                metarDataItem("QNH", value: "\(Int(metar.altimeter))hPa", icon: "gauge")
            }

            if !metar.clouds.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couverture nuageuse:")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))

                    ForEach(metar.clouds) { cloud in
                        Text("\(cloud.coverage.rawValue) à \(cloud.altitude)ft")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
            }
        }
    }

    private func metarDataItem(_ label: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.cyan)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))

                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
        }
    }

    private func flightRulesBadge(_ rules: FlightRules) -> some View {
        Text(rules.rawValue)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(hex: rules.color) ?? .green)
            .cornerRadius(8)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - TAF Card

struct TAFCard: View {
    let taf: TAF

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // En-tête
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .foregroundColor(.purple)

                VStack(alignment: .leading, spacing: 4) {
                    Text("TAF (Prévisions)")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(taf.station)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                Text("Valide \(formatHours(from: taf.validFrom, to: taf.validTo))h")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            // Texte brut
            Text(taf.rawText)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .padding(12)
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)

            // Périodes de prévision
            if !taf.forecast.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Périodes:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    ForEach(taf.forecast) { period in
                        TAFForecastPeriodRow(period: period)
                    }
                }
            }
        }
        .padding(20)
        .background(cardBackground)
        .cornerRadius(20)
    }

    private func formatHours(from: Date, to: Date) -> String {
        let hours = Calendar.current.dateComponents([.hour], from: from, to: to).hour ?? 0
        return "\(hours)"
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
    }
}

struct TAFForecastPeriodRow: View {
    let period: TAFForecastPeriod

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(formatTime(period.validFrom))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))

                Text(formatTime(period.validTo))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Spacer()

                if let indicator = period.changeIndicator {
                    Text(indicator.rawValue)
                        .font(.caption2)
                        .foregroundColor(.orange)
                }

                flightRulesBadge(period.flightRules)
            }

            Text("Vent \(period.windDirection)°/\(Int(period.windSpeed))kt - Vis \(Int(period.visibility/1000))km")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func flightRulesBadge(_ rules: FlightRules) -> some View {
        Text(rules.rawValue)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(hex: rules.color) ?? .green)
            .cornerRadius(6)
    }
}

// MARK: - Airport Header Card

struct AirportHeaderCard: View {
    let airport: Airport

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(airport.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                HStack {
                    Text(airport.icaoCode)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.cyan)

                    if let iata = airport.iataCode {
                        Text("·")
                            .foregroundColor(.white.opacity(0.5))

                        Text(iata)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Text("Élévation: \(airport.elevation)ft")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            Image(systemName: "airplane.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.cyan)
        }
        .padding(20)
        .background(cardBackground)
        .cornerRadius(20)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - Nearby Airports Card

struct NearbyAirportsCard: View {
    let airports: [Airport]
    let viewModel: AviationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aéroports à proximité")
                .font(.headline)
                .foregroundColor(.white)

            ForEach(airports.prefix(5)) { airport in
                Button(action: {
                    Task {
                        await viewModel.loadAviationDataForAirport(airport)
                    }
                }) {
                    NearbyAirportRow(airport: airport)
                }
            }
        }
        .padding(20)
        .background(cardBackground)
        .cornerRadius(20)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
    }
}

struct NearbyAirportRow: View {
    let airport: Airport

    var body: some View {
        HStack {
            Image(systemName: "airplane")
                .foregroundColor(.cyan)

            VStack(alignment: .leading, spacing: 2) {
                Text(airport.icaoCode)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text(airport.name)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Loading and Setup Cards

struct AviationLoadingCard: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                .scaleEffect(1.5)

            Text("Chargement des données aviation...")
                .font(.headline)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(cardBackground)
        .cornerRadius(20)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
    }
}

struct AviationSetupCard: View {
    let viewModel: AviationViewModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "airplane.departure")
                .font(.system(size: 60))
                .foregroundColor(.cyan)

            VStack(spacing: 8) {
                Text("Données aviation")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Recherchez un aéroport pour voir les METAR, TAF et recommandations")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }

            Button(action: {
                viewModel.showingAirportSearch = true
            }) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("Rechercher un aéroport")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.cyan)
                .cornerRadius(12)
            }
        }
        .padding(32)
        .background(cardBackground)
        .cornerRadius(20)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
    }
}

struct AirportSearchSheet: View {
    @Environment(\.dismiss) var dismiss
    let viewModel: AviationViewModel
    @State private var searchText = ""

    var body: some View {
        NavigationView {
            List {
                ForEach(filteredAirports) { airport in
                    Button(action: {
                        Task {
                            await viewModel.loadAviationDataForAirport(airport)
                            dismiss()
                        }
                    }) {
                        NearbyAirportRow(airport: airport)
                    }
                }
            }
            .navigationTitle("Rechercher un aéroport")
            .searchable(text: $searchText, prompt: "Code ICAO ou nom")
        }
    }

    private var filteredAirports: [Airport] {
        if searchText.isEmpty {
            return viewModel.nearbyAirports
        } else {
            return viewModel.nearbyAirports.filter {
                $0.icaoCode.localizedCaseInsensitiveContains(searchText) ||
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    AviationView()
        .environmentObject(WeatherViewModel())
        .environmentObject(PremiumManager.shared)
}
