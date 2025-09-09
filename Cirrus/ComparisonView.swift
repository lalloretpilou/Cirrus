import SwiftUI
import WeatherKit
import CoreLocation

struct ComparisonView: View {
    @EnvironmentObject var premiumManager: PremiumManager
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var selectedSortOption: SortOption = .comfort
    @State private var showingFilters = false
    @State private var activeFilters = ComparisonFilters()
    @State private var showingExportSheet = false
    
    enum SortOption: String, CaseIterable {
        case comfort = "Confort"
        case temperature = "Température"
        case precipitation = "Précipitations"
        case wind = "Vent"
        
        var icon: String {
            switch self {
            case .comfort: return "airplane.departure"
            case .temperature: return "thermometer"
            case .precipitation: return "drop.fill"
            case .wind: return "wind"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        if viewModel.selectedLocationsForComparison.isEmpty {
                            ComparisonEmptyState()
                        } else {
                            ComparisonContent()
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Comparateur")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !viewModel.selectedLocationsForComparison.isEmpty {
                        Button(action: {
                            showingFilters.toggle()
                        }) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .foregroundColor(.primary)
                        }
                    }
                    
                    Button("Ajouter") {
                        viewModel.showingLocationPicker = true
                    }
                    .disabled(!premiumManager.canUseFeature(.advancedComparison) &&
                             viewModel.selectedLocationsForComparison.count >= 3)
                }
            }
            .sheet(isPresented: $viewModel.showingLocationPicker) {
                LocationPickerSheetForComparison()
            }
            .sheet(isPresented: $viewModel.showingPremiumSheet) {
                PremiumSheet()
            }
            .sheet(isPresented: $showingFilters) {
                ComparisonFiltersSheet(filters: $activeFilters, sortOption: $selectedSortOption)
            }
            .sheet(isPresented: $showingExportSheet) {
                ComparisonExportSheet(results: viewModel.comparisonResults)
            }
        }
    }
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Empty State
struct ComparisonEmptyState: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @EnvironmentObject var premiumManager: PremiumManager
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 32) {
            animatedIcon
            contentText
            actionButtons
            premiumInfo
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
    
    private var animatedIcon: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.blue.opacity(0.2), Color.clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: isAnimating ? 60 : 40
                    )
                )
                .frame(width: 120, height: 120)
            
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(isAnimating ? 1.1 : 1.0)
        }
    }
    
    private var contentText: some View {
        VStack(spacing: 12) {
            Text("Comparateur Intelligent")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Comparez la météo de plusieurs destinations et trouvez la parfaite pour votre voyage")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            
            featuresList
        }
    }
    
    private var featuresList: some View {
        VStack(alignment: .leading, spacing: 8) {
            featureRow(icon: "airplane.departure", text: "Score de confort voyage")
            featureRow(icon: "chart.bar.fill", text: "Analyse comparative détaillée")
            featureRow(icon: "slider.horizontal.3", text: "Filtres personnalisés")
        }
        .padding(.top, 16)
    }
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: {
                viewModel.showingLocationPicker = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Ajouter des destinations")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            
            Button("Utiliser ma position") {
                Task {
                    await viewModel.requestLocationPermission()
                    if let userLocation = viewModel.userLocation {
                        let location = Location(
                            name: "Ma position",
                            country: "",
                            coordinates: Location.Coordinates(
                                latitude: userLocation.coordinate.latitude,
                                longitude: userLocation.coordinate.longitude
                            ),
                            timezone: TimeZone.current.identifier,
                            isFavorite: false,
                            isPremium: false
                        )
                        viewModel.addToComparison(location)
                    }
                }
            }
            .foregroundColor(.blue)
        }
    }
    
    private var premiumInfo: some View {
        Group {
            if !premiumManager.isPremium {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.orange)
                        Text("Version gratuite: 3 destinations max")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    Button("Débloquer Premium - 10 destinations") {
                        viewModel.showingPremiumSheet = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
    }
}

// MARK: - Comparison Content
struct ComparisonContent: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @EnvironmentObject var premiumManager: PremiumManager
    @State private var selectedSortOption: ComparisonView.SortOption = .comfort
    @State private var showingExportSheet = false
    
    var body: some View {
        VStack(spacing: 20) {
            selectedLocationsSection
            comparisonControls
            
            if viewModel.showingComparison && !viewModel.comparisonResults.isEmpty {
                comparisonResults
            } else if viewModel.isLoading {
                loadingView
            }
        }
    }
    
    private var selectedLocationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Destinations sélectionnées")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(viewModel.selectedLocationsForComparison.count)/\(premiumManager.canUseFeature(.advancedComparison) ? 10 : 3)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            selectedLocationsGrid
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
    
    private var selectedLocationsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(viewModel.selectedLocationsForComparison, id: \.id) { location in
                ComparisonLocationCard(location: location)
            }
            
            if premiumManager.canUseFeature(.advancedComparison) ||
               viewModel.selectedLocationsForComparison.count < 3 {
                addLocationCard
            }
        }
    }
    
    private var addLocationCard: some View {
        Button(action: {
            viewModel.showingLocationPicker = true
        }) {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.title)
                    .foregroundColor(.blue)
                
                Text("Ajouter")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
                    )
            )
        }
    }
    
    private var comparisonControls: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Button(action: {
                    Task {
                        await viewModel.startComparison()
                    }
                }) {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "chart.bar.fill")
                        }
                        
                        Text(viewModel.isLoading ? "Analyse..." : "Comparer")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                .disabled(viewModel.selectedLocationsForComparison.count < 2 || viewModel.isLoading)
                
                Button("Reset") {
                    viewModel.clearComparison()
                }
                .foregroundColor(.red)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
            }
            
            if !viewModel.comparisonResults.isEmpty {
                sortAndExportControls
            }
        }
    }
    
    private var sortAndExportControls: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(ComparisonView.SortOption.allCases, id: \.rawValue) { option in
                    Button(action: {
                        selectedSortOption = option
                        sortResults(by: option)
                    }) {
                        HStack {
                            Image(systemName: option.icon)
                            Text(option.rawValue)
                            if selectedSortOption == option {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.up.arrow.down")
                    Text("Trier par \(selectedSortOption.rawValue)")
                        .font(.subheadline)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                )
            }
            
            Spacer()
            
            if premiumManager.canUseFeature(.exportData) {
                Button(action: {
                    showingExportSheet = true
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Exporter")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.1))
                    )
                }
                .sheet(isPresented: $showingExportSheet) {
                    ComparisonExportSheet(results: viewModel.comparisonResults)
                }
            }
        }
    }
    
    private var comparisonResults: some View {
        VStack(alignment: .leading, spacing: 16) {
            resultsHeader
            resultsList
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        )
    }
    
    private var resultsHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Résultats de comparaison")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Trié par \(selectedSortOption.rawValue.lowercased())")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "trophy.fill")
                .foregroundColor(.yellow)
                .font(.title2)
        }
    }
    
    private var resultsList: some View {
        LazyVStack(spacing: 12) {
            ForEach(Array(sortedResults.enumerated()), id: \.element.id) { index, weather in
                ComparisonResultCard(weather: weather, rank: index + 1)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
            }
        }
    }
    
    private var sortedResults: [WeatherData] {
        let results = viewModel.comparisonResults
        
        switch selectedSortOption {
        case .comfort:
            return results.sorted { first, second in
                let firstScore = first.forecast.first?.comfortScore ?? 0
                let secondScore = second.forecast.first?.comfortScore ?? 0
                return firstScore > secondScore
            }
        case .temperature:
            return results.sorted { $0.current.temperature > $1.current.temperature }
        case .precipitation:
            return results.sorted { first, second in
                let firstChance = first.forecast.first?.precipitationChance ?? 100
                let secondChance = second.forecast.first?.precipitationChance ?? 100
                return firstChance < secondChance
            }
        case .wind:
            return results.sorted { $0.current.windSpeed < $1.current.windSpeed }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                .scaleEffect(1.5)
            
            Text("Analyse des conditions météo...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
    
    private func sortResults(by option: ComparisonView.SortOption) {
        withAnimation(.easeInOut(duration: 0.5)) {
            selectedSortOption = option
        }
    }
}

// MARK: - Location Card for Comparison
struct ComparisonLocationCard: View {
    let location: Location
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var weatherData: WeatherData?
    @State private var isLoading = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardHeader
            
            if isLoading {
                loadingContent
            } else if let weather = weatherData {
                weatherContent(weather)
            } else {
                placeholderContent
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.primary.opacity(0.1), lineWidth: 1)
                )
        )
        .task {
            await loadWeatherData()
        }
    }
    
    private var cardHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(location.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text(location.country)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                withAnimation(.spring()) {
                    viewModel.removeFromComparison(location)
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title3)
            }
        }
    }
    
    private var loadingContent: some View {
        HStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                .scaleEffect(0.7)
            
            Text("Chargement...")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .frame(height: 40)
    }
    
    private func weatherContent(_ weather: WeatherData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(weather.current.condition.emoji)
                    .font(.title2)
                
                Text(viewModel.formatTemperature(weather.current.temperature))
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            HStack {
                weatherDetail(
                    icon: "drop.fill",
                    value: "\(weather.forecast.first?.precipitationChance ?? 0)%",
                    color: .blue
                )
                
                Spacer()
                
                weatherDetail(
                    icon: "wind",
                    value: viewModel.formatWindSpeed(weather.current.windSpeed),
                    color: .green
                )
            }
            
            if let forecast = weather.forecast.first {
                ComfortScoreBar(score: forecast.comfortScore)
            }
        }
    }
    
    private var placeholderContent: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "cloud.slash")
                    .foregroundColor(.secondary)
                
                Text("Données indisponibles")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 20)
                .cornerRadius(4)
        }
        .frame(height: 60)
    }
    
    private func weatherDetail(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)
            
            Text(value)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func loadWeatherData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            weatherData = try await WeatherService.shared.getWeatherData(for: location)
        } catch {
            print("Error loading weather data for comparison: \(error)")
            weatherData = nil
        }
    }
}

// MARK: - Enhanced Comparison Result Card
struct ComparisonResultCard: View {
    let weather: WeatherData
    let rank: Int
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var isExpanded = false
    var isSelected: Bool = false   // ✅ ajouté

    var body: some View {
        VStack(spacing: 0) {
            mainContent
            
            if isExpanded {
                expandedContent
                    .transition(.asymmetric(
                        insertion: .scale(scale: 1.0, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 1.0, anchor: .top).combined(with: .opacity)
                    ))
            }
        }
        .background(cardBackground)
        .onTapGesture {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
    }
    
    private var mainContent: some View {
        HStack(spacing: 12) {
            rankBadge
            locationInfo
            Spacer()
            weatherSummary
            expandButton
        }
        .padding(16)
    }
    
    private var rankBadge: some View {
        ZStack {
            Circle()
                .fill(rankGradient)
                .frame(width: 40, height: 40)
            
            if rank <= 3 {
                Image(systemName: rank == 1 ? "crown.fill" : "medal.fill")
                    .foregroundColor(.white)
                    .font(.title3)
            } else {
                Text("\(rank)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
        .shadow(color: rankColor.opacity(0.3), radius: 4, y: 2)
    }
    
    private var locationInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(weather.location.name)
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack(spacing: 8) {
                Text(weather.current.condition.emoji)
                Text(viewModel.formatTemperature(weather.current.temperature))
                    .fontWeight(.medium)
                Text("•")
                    .foregroundColor(.secondary)
                Text(weather.current.condition.description)
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
    }
    
    private var weatherSummary: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let forecast = weather.forecast.first {
                ComfortScoreIndicator(score: forecast.comfortScore)
            }
            
            HStack(spacing: 8) {
                weatherMetric(
                    icon: "drop.fill",
                    value: "\(weather.forecast.first?.precipitationChance ?? 0)%",
                    color: .blue
                )
                
                weatherMetric(
                    icon: "wind",
                    value: viewModel.formatWindSpeed(weather.current.windSpeed),
                    color: .green
                )
            }
        }
    }
    
    private var expandButton: some View {
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .foregroundColor(.secondary)
            .font(.caption)
    }
    
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
            
            detailedWeatherInfo
            
            if weather.forecast.count > 1 {
                forecastPreview
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
    
    private var detailedWeatherInfo: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            detailCard(
                title: "Ressenti",
                value: viewModel.formatTemperature(weather.current.feelsLike),
                icon: "thermometer",
                color: .orange
            )
            
            detailCard(
                title: "Humidité",
                value: "\(weather.current.humidity)%",
                icon: "humidity.fill",
                color: .blue
            )
            
            detailCard(
                title: "Visibilité",
                value: "\(Int(weather.current.visibility)) km",
                icon: "eye.fill",
                color: .purple
            )
        }
    }
    
    private var forecastPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prévisions 3 jours")
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack(spacing: 12) {
                ForEach(weather.forecast.prefix(3), id: \.id) { forecast in
                    forecastDay(forecast)
                }
            }
        }
    }
    
    private func forecastDay(_ forecast: DailyForecast) -> some View {
        VStack(spacing: 4) {
            Text(dayName(for: forecast.date))
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(forecast.condition.emoji)
                .font(.title3)
            
            VStack(spacing: 2) {
                Text(viewModel.formatTemperature(forecast.tempMax))
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text(viewModel.formatTemperature(forecast.tempMin))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
        )
    }
    
    private func detailCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
    }
    
    private func weatherMetric(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)
            
            Text(value)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(isSelected ? Color.green.opacity(0.1) : Color(.systemGray6))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(rank == 1 ? Color.green : Color.clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }
    
    private var rankColor: Color {
        switch rank {
        case 1: return .green
        case 2: return .orange
        case 3: return .red
        default: return .gray
        }
    }
    
    private var rankGradient: LinearGradient {
        LinearGradient(
            colors: [rankColor, rankColor.opacity(0.7)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private func dayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Views
struct ComfortScoreBar: View {
    let score: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Confort voyage")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(comfortLabel)
                    .font(.caption2)
                    .foregroundColor(comfortColor)
                    .fontWeight(.medium)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 4)
                        .cornerRadius(2)
                    
                    Rectangle()
                        .fill(comfortColor)
                        .frame(width: geometry.size.width * score, height: 4)
                        .cornerRadius(2)
                        .animation(.easeInOut(duration: 0.8), value: score)
                }
            }
            .frame(height: 4)
        }
    }
    
    private var comfortColor: Color {
        switch score {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .yellow
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }
    
    private var comfortLabel: String {
        switch score {
        case 0.8...1.0: return "Excellent"
        case 0.6..<0.8: return "Bon"
        case 0.4..<0.6: return "Correct"
        default: return "Difficile"
        }
    }
}

struct ComfortScoreIndicator: View {
    let score: Double
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "airplane.departure")
                .font(.caption)
                .foregroundColor(comfortColor)
            
            Text(comfortLabel)
                .font(.caption)
                .foregroundColor(comfortColor)
                .fontWeight(.medium)
            
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .fill(index < Int(score * 5) ? comfortColor : Color.gray.opacity(0.3))
                        .frame(width: 4, height: 4)
                }
            }
        }
    }
    
    private var comfortColor: Color {
        switch score {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .yellow
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }
    
    private var comfortLabel: String {
        switch score {
        case 0.8...1.0: return "Excellent"
        case 0.6..<0.8: return "Bon"
        case 0.4..<0.6: return "Correct"
        default: return "Difficile"
        }
    }
}

// MARK: - Location Picker for Comparison
struct LocationPickerSheetForComparison: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @EnvironmentObject var premiumManager: PremiumManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                SearchBar(text: $searchText)
                    .padding()
                
                if searchText.isEmpty {
                    ComparisonLocationPickerDefault()
                } else {
                    ComparisonLocationPickerResults()
                }
            }
            .navigationTitle("Ajouter une destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text("\(viewModel.selectedLocationsForComparison.count)/\(premiumManager.canUseFeature(.advancedComparison) ? 10 : 3)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            viewModel.searchText = newValue
        }
    }
}

struct ComparisonLocationPickerDefault: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                currentLocationSection
                favoritesSection
                popularDestinationsSection
                Spacer(minLength: 100)
            }
            .padding()
        }
    }
    
    private var currentLocationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Position actuelle")
                .font(.headline)
                .fontWeight(.semibold)
            
            Button(action: {
                Task {
                    await addCurrentLocation()
                }
            }) {
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ajouter ma position")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("Utiliser la géolocalisation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if viewModel.selectedLocationsForComparison.contains(where: { $0.name.contains("Ma position") }) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "plus.circle")
                            .foregroundColor(.blue)
                    }
                }
                .foregroundColor(.primary)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
            }
            .disabled(viewModel.selectedLocationsForComparison.contains(where: { $0.name.contains("Ma position") }))
        }
    }
    
    private var favoritesSection: some View {
        Group {
            if !viewModel.favoriteLocations.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Mes destinations favorites")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(viewModel.favoriteLocations, id: \.id) { location in
                            ComparisonLocationOption(location: location)
                        }
                    }
                }
            }
        }
    }
    
    private var popularDestinationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Destinations populaires")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(popularDestinations, id: \.id) { location in
                    ComparisonLocationOption(location: location)
                }
            }
        }
    }
    
    private var popularDestinations: [Location] {
        [
            Location(name: "Paris", country: "France", coordinates: Location.Coordinates(latitude: 48.8566, longitude: 2.3522), timezone: nil, isFavorite: false, isPremium: false),
            Location(name: "Londres", country: "Royaume-Uni", coordinates: Location.Coordinates(latitude: 51.5074, longitude: -0.1278), timezone: nil, isFavorite: false, isPremium: false),
            Location(name: "New York", country: "États-Unis", coordinates: Location.Coordinates(latitude: 40.7128, longitude: -74.0060), timezone: nil, isFavorite: false, isPremium: false),
            Location(name: "Tokyo", country: "Japon", coordinates: Location.Coordinates(latitude: 35.6762, longitude: 139.6503), timezone: nil, isFavorite: false, isPremium: false),
            Location(name: "Barcelona", country: "Espagne", coordinates: Location.Coordinates(latitude: 41.3851, longitude: 2.1734), timezone: nil, isFavorite: false, isPremium: false),
            Location(name: "Rome", country: "Italie", coordinates: Location.Coordinates(latitude: 41.9028, longitude: 12.4964), timezone: nil, isFavorite: false, isPremium: false)
        ]
    }
    
    private func addCurrentLocation() async {
        await viewModel.requestLocationPermission()
        if let userLocation = viewModel.userLocation {
            let location = Location(
                name: "Ma position",
                country: "",
                coordinates: Location.Coordinates(
                    latitude: userLocation.coordinate.latitude,
                    longitude: userLocation.coordinate.longitude
                ),
                timezone: TimeZone.current.identifier,
                isFavorite: false,
                isPremium: false
            )
            viewModel.addToComparison(location)
            dismiss()
        }
    }
}

struct ComparisonLocationPickerResults: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    
    var body: some View {
        if viewModel.isLoading {
            loadingView
        } else if viewModel.searchResults.isEmpty {
            emptyResults
        } else {
            searchResults
        }
    }
    
    private var loadingView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Recherche en cours...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }
    
    private var emptyResults: some View {
        VStack(spacing: 12) {
            Image(systemName: "location.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("Aucun résultat")
                .font(.headline)
            
            Text("Aucune destination trouvée pour '\(viewModel.searchText)'")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var searchResults: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.searchResults, id: \.id) { location in
                    ComparisonLocationSearchResult(location: location)
                    
                    if location.id != viewModel.searchResults.last?.id {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct ComparisonLocationOption: View {
    let location: Location
    @EnvironmentObject var viewModel: WeatherViewModel
    @EnvironmentObject var premiumManager: PremiumManager
    @Environment(\.dismiss) private var dismiss
    @State private var weatherData: WeatherData?
    
    private var isSelected: Bool {
        viewModel.selectedLocationsForComparison.contains { $0.id == location.id }
    }
    
    private var canAdd: Bool {
        premiumManager.canUseFeature(.advancedComparison) ||
        viewModel.selectedLocationsForComparison.count < 3
    }
    
    var body: some View {
        Button(action: {
            if isSelected {
                viewModel.removeFromComparison(location)
            } else if canAdd {
                viewModel.addToComparison(location)
                dismiss()
            } else {
                viewModel.showingPremiumSheet = true
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(location.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else if canAdd {
                        Image(systemName: "plus.circle")
                            .foregroundColor(.blue)
                    } else {
                        Image(systemName: "crown.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
                
                Text(location.country)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let weather = weatherData {
                    HStack {
                        Text(weather.current.condition.emoji)
                        Text(viewModel.formatTemperature(weather.current.temperature))
                            .fontWeight(.medium)
                        Spacer()
                        Text(weather.current.condition.description)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                }
            }
            .foregroundColor(.primary)
            .padding(12)
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.green.opacity(0.1) : Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.green : Color.clear, lineWidth: 1)
                    )
            )
        }
        .disabled(isSelected)
        .task {
            do {
                weatherData = try await WeatherService.shared.getWeatherData(for: location)
            } catch {
                // Handle silently for UI
            }
        }
    }
}

struct ComparisonLocationSearchResult: View {
    let location: Location
    @EnvironmentObject var viewModel: WeatherViewModel
    @EnvironmentObject var premiumManager: PremiumManager
    @Environment(\.dismiss) private var dismiss
    @State private var weatherData: WeatherData?
    
    private var isSelected: Bool {
        viewModel.selectedLocationsForComparison.contains { $0.id == location.id }
    }
    
    private var canAdd: Bool {
        premiumManager.canUseFeature(.advancedComparison) ||
        viewModel.selectedLocationsForComparison.count < 3
    }
    
    var body: some View {
        Button(action: {
            if isSelected {
                viewModel.removeFromComparison(location)
            } else if canAdd {
                viewModel.addToComparison(location)
                dismiss()
            } else {
                viewModel.showingPremiumSheet = true
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: "location.circle.fill")
                    .font(.title2)
                    .foregroundColor(isSelected ? .green : .blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(location.country)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let weather = weatherData {
                        Text(weather.current.condition.description)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if let weather = weatherData {
                    HStack(spacing: 8) {
                        Text(weather.current.condition.emoji)
                            .font(.title3)
                        
                        Text(viewModel.formatTemperature(weather.current.temperature))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if !canAdd {
                    Image(systemName: "crown.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                } else {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
        .task {
            do {
                weatherData = try await WeatherService.shared.getWeatherData(for: location)
            } catch {
                // Handle silently
            }
        }
    }
}

// MARK: - Filters and Export
struct ComparisonFilters {
    var minTemperature: Double = -20
    var maxTemperature: Double = 40
    var maxPrecipitationChance: Int = 100
    var maxWindSpeed: Double = 50
    var minComfortScore: Double = 0.0
    var weatherConditions: Set<String> = []
}

struct ComparisonFiltersSheet: View {
    @Binding var filters: ComparisonFilters
    @Binding var sortOption: ComparisonView.SortOption
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                temperatureSection
                precipitationSection
                windSection
                comfortSection
                sortingSection
            }
            .navigationTitle("Filtres & Tri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Réinitialiser") {
                        filters = ComparisonFilters()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var temperatureSection: some View {
        Section("Température") {
            HStack {
                Text("Min:")
                Spacer()
                Text("\(Int(filters.minTemperature))°C")
            }
            Slider(value: $filters.minTemperature, in: -20...40, step: 1)
            
            HStack {
                Text("Max:")
                Spacer()
                Text("\(Int(filters.maxTemperature))°C")
            }
            Slider(value: $filters.maxTemperature, in: -20...40, step: 1)
        }
    }
    
    private var precipitationSection: some View {
        Section("Précipitations") {
            HStack {
                Text("Chance max:")
                Spacer()
                Text("\(filters.maxPrecipitationChance)%")
            }
            Slider(value: Binding(
                get: { Double(filters.maxPrecipitationChance) },
                set: { filters.maxPrecipitationChance = Int($0) }
            ), in: 0...100, step: 5)
        }
    }
    
    private var windSection: some View {
        Section("Vent") {
            HStack {
                Text("Vitesse max:")
                Spacer()
                Text("\(Int(filters.maxWindSpeed)) km/h")
            }
            Slider(value: $filters.maxWindSpeed, in: 0...100, step: 5)
        }
    }
    
    private var comfortSection: some View {
        Section("Confort voyage") {
            HStack {
                Text("Score minimum:")
                Spacer()
                Text("\(Int(filters.minComfortScore * 100))%")
            }
            Slider(value: $filters.minComfortScore, in: 0...1, step: 0.1)
        }
    }
    
    private var sortingSection: some View {
        Section("Tri") {
            Picker("Trier par", selection: $sortOption) {
                ForEach(ComparisonView.SortOption.allCases, id: \.rawValue) { option in
                    HStack {
                        Image(systemName: option.icon)
                        Text(option.rawValue)
                    }
                    .tag(option)
                }
            }
            .pickerStyle(.menu)
        }
    }
}

struct ComparisonExportSheet: View {
    let results: [WeatherData]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .pdf
    @State private var isExporting = false
    
    enum ExportFormat: String, CaseIterable {
        case pdf = "PDF"
        case csv = "CSV"
        case json = "JSON"
        
        var icon: String {
            switch self {
            case .pdf: return "doc.fill"
            case .csv: return "tablecells.fill"
            case .json: return "curlybraces"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                exportHeader
                formatSelection
                exportPreview
                Spacer()
                exportButton
            }
            .padding()
            .navigationTitle("Exporter les résultats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var exportHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("Exporter la comparaison")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("\(results.count) destinations à exporter")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var formatSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Format d'export")
                .font(.headline)
            
            HStack(spacing: 12) {
                ForEach(ExportFormat.allCases, id: \.rawValue) { format in
                    formatOption(format)
                }
            }
        }
    }
    
    private func formatOption(_ format: ExportFormat) -> some View {
        Button(action: {
            selectedFormat = format
        }) {
            VStack(spacing: 8) {
                Image(systemName: format.icon)
                    .font(.title2)
                    .foregroundColor(selectedFormat == format ? .white : .blue)
                
                Text(format.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(selectedFormat == format ? .white : .primary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedFormat == format ? Color.blue : Color.blue.opacity(0.1))
            )
        }
    }
    
    private var exportPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Contenu inclus")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                previewItem(icon: "location.fill", text: "Informations des destinations")
                previewItem(icon: "thermometer", text: "Conditions météo actuelles")
                previewItem(icon: "calendar", text: "Prévisions 3 jours")
                previewItem(icon: "airplane.departure", text: "Scores de confort voyage")
                previewItem(icon: "chart.bar.fill", text: "Classement et comparaison")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
    }
    
    private func previewItem(icon: String, text: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
            
            Spacer()
        }
    }
    
    private var exportButton: some View {
        Button(action: {
            exportResults()
        }) {
            HStack {
                if isExporting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
                
                Text(isExporting ? "Export en cours..." : "Exporter au format \(selectedFormat.rawValue)")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
        }
        .disabled(isExporting)
    }
    
    private func exportResults() {
        isExporting = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isExporting = false
            // Here you would implement actual export functionality
            // For now, we'll just dismiss
            dismiss()
        }
    }
}



extension ShapeStyle where Self == AnyShapeStyle {
    static var compatibleThinMaterial: AnyShapeStyle {
        if #available(iOS 15.0, macOS 12.0, *) {
            return AnyShapeStyle(.thinMaterial)
        } else {
            return AnyShapeStyle(Color.white.opacity(0.6))
        }
    }
}


#Preview {
    ComparisonView()
        .environmentObject(PremiumManager.shared)
        .environmentObject(WeatherViewModel())
}
