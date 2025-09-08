import SwiftUI
import CoreLocation

struct WeatherView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @EnvironmentObject var premiumManager: PremiumManager
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient based on weather
                backgroundGradient
                    .ignoresSafeArea()
                
                ScrollView {
                    LazyVStack(spacing: 20) {
                        // Header with current weather
                        if let weather = viewModel.currentWeather {
                            CurrentWeatherCard(weather: weather)
                                .transition(.opacity.combined(with: .scale))
                        } else if viewModel.isLoading {
                            LoadingCard()
                        } else {
                            WelcomeCard()
                        }
                        
                        // Quick actions
                        QuickActionsView()
                        
                        // Forecast section
                        if let weather = viewModel.currentWeather {
                            ForecastSection(weather: weather)
                        }
                        
                        // Favorites section
                        if !viewModel.favoriteLocations.isEmpty {
                            FavoritesSection()
                        }
                        
                        // Premium features teaser
                        if !premiumManager.isPremium {
                            PremiumTeaserCard()
                        }
                        
                        Spacer(minLength: 100) // Space for tab bar
                    }
                    .padding(.horizontal)
                }
            }
            .refreshable {
                await viewModel.refreshWeather()
            }
            .navigationTitle("Cirrus")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        if premiumManager.isPremium {
                            PremiumCrownIcon()
                        }
                        
                        Button(action: {
                            viewModel.showingLocationPicker = true
                        }) {
                            Image(systemName: "location.magnifyingglass")
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingLocationPicker) {
                LocationPickerSheet()
            }
            .sheet(isPresented: $viewModel.showingPremiumSheet) {
                PremiumSheet()
            }
            .alert("Erreur", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: backgroundColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .animation(.easeInOut(duration: 1.0), value: viewModel.currentWeather?.current.condition.main)
    }
    
    private var backgroundColors: [Color] {
        guard let condition = viewModel.currentWeather?.current.condition.main.lowercased() else {
            return [Color.blue.opacity(0.3), Color.purple.opacity(0.3)]
        }
        
        switch condition {
        case "clear":
            return [Color.yellow.opacity(0.3), Color.orange.opacity(0.3)]
        case "clouds":
            return [Color.gray.opacity(0.3), Color.blue.opacity(0.3)]
        case "rain", "drizzle":
            return [Color.blue.opacity(0.4), Color.indigo.opacity(0.4)]
        case "thunderstorm":
            return [Color.purple.opacity(0.4), Color.black.opacity(0.3)]
        case "snow":
            return [Color.white.opacity(0.4), Color.blue.opacity(0.2)]
        default:
            return [Color.blue.opacity(0.3), Color.purple.opacity(0.3)]
        }
    }
}

// MARK: - Premium Crown Icon

struct PremiumCrownIcon: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Glow effect
            Image(systemName: "crown.fill")
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.premiumOrange, .premiumGradientEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blur(radius: isAnimating ? 8 : 4)
                .opacity(isAnimating ? 0.8 : 0.4)
            
            // Main crown
            Image(systemName: "crown.fill")
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.premiumOrange, .premiumGradientEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .scaleEffect(isAnimating ? 1.1 : 1.0)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Current Weather Card

struct CurrentWeatherCard: View {
    let weather: WeatherData
    @EnvironmentObject var viewModel: WeatherViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.secondary)
                        Text(weather.location.name)
                            .font(.title2)
                            .fontWeight(.medium)
                    }
                    
                    Text("Maintenant")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    viewModel.toggleFavorite(for: weather.location)
                }) {
                    Image(systemName: viewModel.isFavorite(weather.location) ? "heart.fill" : "heart")
                        .foregroundColor(viewModel.isFavorite(weather.location) ? .premiumOrange : .secondary)
                        .font(.title2)
                }
            }
            
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(viewModel.formatTemperature(weather.current.temperature))
                            .font(.system(size: 48, weight: .thin))
                        
                        Text(weather.current.condition.emoji)
                            .font(.title)
                    }
                    
                    Text(weather.current.condition.description.capitalized)
                        .font(.title3)
                        .foregroundColor(.secondary)
                    
                    Text("Ressenti \(viewModel.formatTemperature(weather.current.feelsLike))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    WeatherDetailRow(icon: "humidity.fill", value: "\(weather.current.humidity)%")
                    WeatherDetailRow(icon: "wind", value: viewModel.formatWindSpeed(weather.current.windSpeed))
                    WeatherDetailRow(icon: "eye.fill", value: "\(Int(weather.current.visibility)) km")
                    WeatherDetailRow(icon: "sun.max.fill", value: "UV \(weather.current.uvIndex)")
                }
            }
            
            // Comfort score for travelers
            if let todayForecast = weather.forecast.first {
                HStack {
                    Image(systemName: "airplane")
                        .foregroundColor(viewModel.getComfortColor(score: todayForecast.comfortScore))
                    
                    Text(viewModel.getComfortDescription(score: todayForecast.comfortScore))
                        .font(.subheadline)
                        .foregroundColor(viewModel.getComfortColor(score: todayForecast.comfortScore))
                    
                    Spacer()
                    
                    ComfortScoreView(score: todayForecast.comfortScore)
                }
                .padding(.top, 8)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(radius: 10, y: 5)
        )
    }
}

// MARK: - Weather Detail Row

struct WeatherDetailRow: View {
    let icon: String
    let value: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 16)
            
            Text(value)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Loading Card

struct LoadingCard: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            
            Text("Chargement des données météo...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(radius: 10, y: 5)
        )
    }
}

// MARK: - Welcome Card

struct WelcomeCard: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "airplane.departure")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("Bienvenue dans Cirrus")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Découvrez la météo parfaite pour vos voyages")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 12) {
                // Bouton principal de géolocalisation
                Button(action: {
                    Task {
                        await viewModel.requestLocationPermission()
                        await viewModel.loadWeatherForCurrentLocation()
                    }
                }) {
                    HStack {
                        if viewModel.isRequestingLocation {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "location.fill")
                        }
                        Text(viewModel.isRequestingLocation ? "Localisation..." : "Utiliser ma position")
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .disabled(viewModel.isRequestingLocation)
                
                // Vue de debug de la géolocalisation
                LocationDebugView()
                
                // Affichage du statut de la géolocalisation
                LocationStatusView()
                
                #if DEBUG
                // Boutons de test pour développement
                VStack(spacing: 8) {
                    Text("Mode Debug")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        Button("Paris") {
                            viewModel.simulateLocationUpdate(latitude: 48.8566, longitude: 2.3522, name: "Paris")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button("Londres") {
                            viewModel.simulateLocationUpdate(latitude: 51.5074, longitude: -0.1278, name: "Londres")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button("New York") {
                            viewModel.simulateLocationUpdate(latitude: 40.7128, longitude: -74.0060, name: "New York")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Button("Données de test (Paris)") {
                        Task {
                            await viewModel.loadTestWeatherData()
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.premiumOrange)
                }
                .padding(.top, 8)
                #endif
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(radius: 10, y: 5)
        )
    }
}

// MARK: - Location Status View

struct LocationStatusView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
                .font(.caption)
            
            Text(statusText)
                .font(.caption)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(statusColor.opacity(0.1))
        )
    }
    
    private var statusIcon: String {
        switch viewModel.locationPermissionStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return "checkmark.circle.fill"
        case .denied, .restricted:
            return "xmark.circle.fill"
        case .notDetermined:
            return "questionmark.circle.fill"
        @unknown default:
            return "exclamationmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch viewModel.locationPermissionStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }
    
    private var statusText: String {
        if viewModel.isRequestingLocation {
            return "Localisation en cours..."
        }
        
        switch viewModel.locationPermissionStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if let location = viewModel.userLocation {
                return "Position obtenue (±\(Int(location.horizontalAccuracy))m)"
            } else {
                return "Géolocalisation autorisée"
            }
        case .denied:
            return "Géolocalisation refusée"
        case .restricted:
            return "Géolocalisation restreinte"
        case .notDetermined:
            return "Permission non demandée"
        @unknown default:
            return "Statut inconnu"
        }
    }
}

// MARK: - Quick Actions View

struct QuickActionsView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @EnvironmentObject var premiumManager: PremiumManager
    
    var body: some View {
        HStack(spacing: 12) {
            QuickActionButton(
                icon: "magnifyingglass",
                title: "Rechercher",
                color: .blue
            ) {
                viewModel.showingLocationPicker = true
            }
            
            QuickActionButton(
                icon: "rectangle.split.3x1",
                title: "Comparer",
                color: .green,
                isPremium: !premiumManager.canUseFeature(.advancedComparison)
            ) {
                if premiumManager.canUseFeature(.advancedComparison) {
                    // Ouvrir le comparateur
                } else {
                    viewModel.showingPremiumSheet = true
                }
            }
            
            QuickActionButton(
                icon: "calendar",
                title: "Planifier",
                color: .premiumOrange,
                isPremium: !premiumManager.canUseFeature(.aiAssistant)
            ) {
                if premiumManager.canUseFeature(.aiAssistant) {
                    // Ouvrir le planificateur
                } else {
                    viewModel.showingPremiumSheet = true
                }
            }
            
            QuickActionButton(
                icon: "dot.radiowaves.left.and.right",
                title: "Radar",
                color: .purple,
                isPremium: !premiumManager.canUseFeature(.weatherRadar)
            ) {
                if premiumManager.canUseFeature(.weatherRadar) {
                    // Ouvrir le radar
                } else {
                    viewModel.showingPremiumSheet = true
                }
            }
        }
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let isPremium: Bool
    let action: () -> Void
    
    init(icon: String, title: String, color: Color, isPremium: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.color = color
        self.isPremium = isPremium
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(color)
                    
                    if isPremium {
                        PremiumBadge()
                            .offset(x: 16, y: -16)
                    }
                }
                
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Premium Badge

struct PremiumBadge: View {
    @State private var isGlowing = false
    
    var body: some View {
        ZStack {
            // Glow effect
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.premiumOrange.opacity(0.8), .clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: isGlowing ? 12 : 8
                    )
                )
                .frame(width: 20, height: 20)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isGlowing)
            
            // Badge background
            Circle()
                .fill(.white)
                .frame(width: 16, height: 16)
                .shadow(radius: 2)
            
            // Crown icon
            Image(systemName: "crown.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.premiumOrange, .premiumGradientEnd],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .onAppear {
            isGlowing = true
        }
    }
}

// MARK: - Forecast Section

struct ForecastSection: View {
    let weather: WeatherData
    @EnvironmentObject var premiumManager: PremiumManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Prévisions")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if !premiumManager.isPremium {
                    Text("7 jours")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(weather.forecast.prefix(premiumManager.canUseFeature(.extendedForecast) ? weather.forecast.count : 7), id: \.id) { forecast in
                        ForecastCard(forecast: forecast)
                    }
                    
                    if !premiumManager.canUseFeature(.extendedForecast) && weather.forecast.count > 7 {
                        PremiumForecastCard()
                    }
                }
                .padding(.horizontal)
            }
            .padding(.horizontal, -16)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Forecast Card

struct ForecastCard: View {
    let forecast: DailyForecast
    @EnvironmentObject var viewModel: WeatherViewModel
    
    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text(dayFormatter.string(from: forecast.date))
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(forecast.condition.emoji)
                .font(.title2)
            
            VStack(spacing: 2) {
                Text(viewModel.formatTemperature(forecast.tempMax))
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(viewModel.formatTemperature(forecast.tempMin))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(viewModel.formatPrecipitationChance(forecast.precipitationChance))
                .font(.caption2)
                .foregroundColor(.blue)
            
            ComfortScoreView(score: forecast.comfortScore)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.05))
        )
        .frame(width: 80)
    }
}

// MARK: - Premium Forecast Card

struct PremiumForecastCard: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var isAnimating = false
    
    var body: some View {
        Button(action: {
            viewModel.showingPremiumSheet = true
        }) {
            VStack(spacing: 8) {
                ZStack {
                    // Animated glow
                    Image(systemName: "crown.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.premiumOrange, .premiumGradientEnd],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blur(radius: isAnimating ? 6 : 2)
                        .opacity(isAnimating ? 0.8 : 0.4)
                    
                    // Main crown
                    Image(systemName: "crown.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.premiumOrange, .premiumGradientEnd],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .scaleEffect(isAnimating ? 1.1 : 1.0)
                
                Text("Premium")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.premiumOrange, .premiumGradientEnd],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text("+23 jours")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [.premiumOrange.opacity(0.1), .premiumGradientEnd.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                LinearGradient(
                                    colors: [.premiumOrange.opacity(0.5), .premiumGradientEnd.opacity(0.5)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 1, dash: [5])
                            )
                    )
            )
            .frame(width: 80)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Favorites Section

struct FavoritesSection: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mes destinations")
                .font(.title2)
                .fontWeight(.semibold)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.favoriteLocations, id: \.id) { location in
                        FavoriteLocationCard(location: location)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.horizontal, -16)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Favorite Location Card

struct FavoriteLocationCard: View {
    let location: Location
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var weatherData: WeatherData?
    
    var body: some View {
        Button(action: {
            Task {
                await viewModel.selectLocation(location)
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(location.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    if let weather = weatherData {
                        Text(weather.current.condition.emoji)
                            .font(.title3)
                    }
                }
                
                if let weather = weatherData {
                    Text(viewModel.formatTemperature(weather.current.temperature))
                        .font(.title2)
                        .fontWeight(.light)
                    
                    Text(weather.current.condition.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            .foregroundColor(.primary)
            .padding(12)
            .frame(width: 120, height: 100)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.05))
            )
        }
        .task {
            do {
                weatherData = try await WeatherService.shared.getWeatherData(for: location)
            } catch {
                print("Error loading weather for favorite: \(error)")
            }
        }
    }
}

// MARK: - Premium Teaser Card

struct PremiumTeaserCard: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var isAnimating = false
    
    var body: some View {
        Button(action: {
            viewModel.showingPremiumSheet = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    // Animated glow
                    Image(systemName: "crown.fill")
                        .font(.title)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.premiumOrange, .premiumGradientEnd],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blur(radius: isAnimating ? 8 : 4)
                        .opacity(isAnimating ? 0.8 : 0.4)
                    
                    // Main crown
                    Image(systemName: "crown.fill")
                        .font(.title)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.premiumOrange, .premiumGradientEnd],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .scaleEffect(isAnimating ? 1.1 : 1.0)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Débloquez Premium")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Prévisions 30 jours • Destinations illimitées • Assistant IA")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.primary)
            .padding(20)
            .background(
                ZStack {
                    // Base background
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                    
                    // Premium gradient overlay
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .premiumOrange.opacity(0.1),
                                    .premiumGradientEnd.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Animated border
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .premiumOrange.opacity(isAnimating ? 0.8 : 0.4),
                                    .premiumGradientEnd.opacity(isAnimating ? 0.8 : 0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isAnimating ? 2 : 1
                        )
                }
            )
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - ComfortScoreView

struct ComfortScoreView: View {
    let score: Double
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(index < Int(score * 5) ? scoreColor : Color.gray.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }
    
    private var scoreColor: Color {
        switch score {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .yellow
        case 0.4..<0.6: return .premiumOrange
        case 0.2..<0.4: return .red
        default: return .red
        }
    }
}
