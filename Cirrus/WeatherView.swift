import SwiftUI
import CoreLocation

struct WeatherView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @EnvironmentObject var premiumManager: PremiumManager
    @State private var animationOffset: CGFloat = 0
    @State private var showingSearchBar = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Animated weather background
                WeatherAnimatedBackground(weather: viewModel.currentWeather)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Custom navigation bar with search
                    CustomNavigationBar(showingSearchBar: $showingSearchBar)
                    
                    ScrollView {
                        LazyVStack(spacing: 28) {
                            // Main content based on state
                            mainContent
                            
                            // Additional content when weather is loaded
                            if viewModel.currentWeather != nil {
                                additionalContent
                            }
                            
                            Spacer(minLength: 140)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                    }
                }
            }
            .refreshable {
                await viewModel.refreshWeather()
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $viewModel.showingLocationPicker) {
                IntelligentLocationPickerSheet()
            }
            .sheet(isPresented: $viewModel.showingPremiumSheet) {
                PremiumSheet()
            }
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        if let weather = viewModel.currentWeather {
            ImprovedHeroWeatherCard(weather: weather)
                .transition(.opacity.combined(with: .scale))
        } else if viewModel.isLoading {
            ImprovedLoadingCard()
        } else {
            ImprovedLocationSetupCard()
        }
    }
    
    @ViewBuilder
    private var additionalContent: some View {
        if let weather = viewModel.currentWeather {
            ImprovedWeatherMetricsGrid(weather: weather)
            ImprovedForecastSection(weather: weather)
            TravelInsightsCard(weather: weather)
        }
        
        if !premiumManager.isPremium {
            ImprovedPremiumShowcase()
        }
    }
}

// MARK: - Custom Navigation Bar
struct CustomNavigationBar: View {
    @Binding var showingSearchBar: Bool
    @EnvironmentObject var viewModel: WeatherViewModel
    @EnvironmentObject var premiumManager: PremiumManager
    
    var body: some View {
        HStack {
            // App title
            HStack(spacing: 8) {
                Text("Cirrus")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(appTitleGradient)
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 16) {
                if premiumManager.isPremium {
                    PremiumStatusIcon()
                }
                
                searchButton
                locationButton
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }
    
    private var searchButton: some View {
        Button(action: {
            showingSearchBar.toggle()
            viewModel.showingLocationPicker = true
        }) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundColor(.primary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.ultraThinMaterial))
                .shadow(color: .black.opacity(0.1), radius: 4)
        }
    }
    
    private var locationButton: some View {
        Button(action: {
            Task {
                await viewModel.requestLocationPermission()
                await viewModel.loadWeatherForCurrentLocation()
            }
        }) {
            Image(systemName: "location.fill")
                .font(.title2)
                .foregroundColor(locationButtonColor)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.ultraThinMaterial))
                .shadow(color: .black.opacity(0.1), radius: 4)
        }
    }
    
    private var locationButtonColor: Color {
        switch viewModel.locationPermissionStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return .green
        case .denied, .restricted:
            return .red
        default:
            return .orange
        }
    }
    
    private var appIconGradient: LinearGradient {
        LinearGradient(
            colors: [.blue, .purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var appTitleGradient: LinearGradient {
        LinearGradient(
            colors: [.primary, .primary.opacity(0.8)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct PremiumStatusIcon: View {
    @State private var isGlowing = false
    
    var body: some View {
        ZStack {
            Circle()
                .fill(premiumGlowGradient)
                .frame(width: 44, height: 44)
                .scaleEffect(isGlowing ? 1.2 : 1.0)
                .opacity(isGlowing ? 0.6 : 0.3)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isGlowing)
            
            Image(systemName: "crown.fill")
                .font(.title2)
                .foregroundStyle(crownGradient)
        }
        .onAppear {
            isGlowing = true
        }
    }
    
    private var premiumGlowGradient: RadialGradient {
        RadialGradient(
            colors: [.orange, .clear],
            center: .center,
            startRadius: 5,
            endRadius: 22
        )
    }
    
    private var crownGradient: LinearGradient {
        LinearGradient(
            colors: [.orange, .red],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Improved Hero Weather Card
struct ImprovedHeroWeatherCard: View {
    let weather: WeatherData
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var cardScale: CGFloat = 0.9
    
    var body: some View {
        VStack(spacing: 0) {
            ImprovedLocationHeader(weather: weather)
            
            VStack(spacing: 32) {
                temperatureDisplay
                
                if let todayForecast = weather.forecast.first {
                    ImprovedTravelComfort(score: todayForecast.comfortScore)
                }
                
                quickWeatherStats
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 36)
        }
        .background(improvedHeroBackground)
        .scaleEffect(cardScale)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
                cardScale = 1.0
            }
        }
    }
    
    @ViewBuilder
    private var temperatureDisplay: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                temperatureText
                conditionDescription
                feelsLikeText
            }
            
            Spacer()
            
            ImprovedWeatherIcon(condition: weather.current.condition.main, size: 90)
        }
    }
    
    private var temperatureText: some View {
        Text(viewModel.formatTemperature(weather.current.temperature))
            .font(.system(size: 84, weight: .ultraLight, design: .rounded))
            .foregroundStyle(temperatureGradient)
    }
    
    private var conditionDescription: some View {
        Text(weather.current.condition.description.capitalized)
            .font(.title)
            .fontWeight(.medium)
            .foregroundColor(.white.opacity(0.95))
    }
    
    private var feelsLikeText: some View {
        Text("Ressenti \(viewModel.formatTemperature(weather.current.feelsLike))")
            .font(.headline)
            .foregroundColor(.white.opacity(0.75))
    }
    
    private var quickWeatherStats: some View {
        HStack(spacing: 20) {
            QuickStat(icon: "humidity.fill", value: "\(weather.current.humidity)%", color: .blue)
            QuickStat(icon: "wind", value: viewModel.formatWindSpeed(weather.current.windSpeed), color: .green)
            QuickStat(icon: "eye.fill", value: "\(Int(weather.current.visibility))km", color: .purple)
            QuickStat(icon: "sun.max.fill", value: "UV\(weather.current.uvIndex)", color: .orange)
        }
    }
    
    private var temperatureGradient: LinearGradient {
        LinearGradient(
            colors: [.white, .white.opacity(0.9)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var improvedHeroBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
            
            RoundedRectangle(cornerRadius: 28)
                .fill(heroGradientOverlay)
            
            RoundedRectangle(cornerRadius: 28)
                .stroke(heroBorderGradient, lineWidth: 1.5)
        }
        .shadow(color: .black.opacity(0.25), radius: 25, y: 15)
    }
    
    private var heroGradientOverlay: LinearGradient {
        LinearGradient(
            colors: [
                .blue.opacity(0.15),
                .purple.opacity(0.1),
                .clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var heroBorderGradient: LinearGradient {
        LinearGradient(
            colors: [.white.opacity(0.4), .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct QuickStat: View {
    let icon: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Improved Location Header with Geocoding
struct ImprovedLocationHeader: View {
    let weather: WeatherData
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var displayName: String = ""
    @State private var isLoadingLocation = false
    
    var body: some View {
        HStack(spacing: 20) {
            locationInfo
            
            Spacer()
            
            actionButtons
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .onAppear {
            loadLocationName()
        }
    }
    
    private var locationInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                
                if isLoadingLocation {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.6)
                } else {
                    cityNameText
                }
            }
            
            if !weather.location.country.isEmpty {
                countryText
            }
            
            lastUpdatedText
        }
    }
    
    private var cityNameText: some View {
        Text(displayName.isEmpty ? "Chargement..." : displayName)
            .font(.title)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)
    }
    
    private var countryText: some View {
        Text(weather.location.country)
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.7))
    }
    
    private var lastUpdatedText: some View {
        Text("Mise à jour: \(formatUpdateTime(weather.lastUpdated))")
            .font(.caption)
            .foregroundColor(.white.opacity(0.6))
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            favoriteButton
            refreshButton
        }
    }
    
    private var favoriteButton: some View {
        Button(action: {
            viewModel.toggleFavorite(for: weather.location)
        }) {
            Image(systemName: viewModel.isFavorite(weather.location) ? "heart.fill" : "heart")
                .font(.title2)
                .foregroundColor(viewModel.isFavorite(weather.location) ? .red : .white.opacity(0.7))
                .frame(width: 44, height: 44)
                .background(Circle().fill(.white.opacity(0.15)))
                .scaleEffect(viewModel.isFavorite(weather.location) ? 1.1 : 1.0)
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: viewModel.isFavorite(weather.location))
        }
    }
    
    private var refreshButton: some View {
        Button(action: {
            Task {
                await viewModel.refreshWeather()
            }
        }) {
            Image(systemName: "arrow.clockwise")
                .font(.title3)
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 36, height: 36)
                .background(Circle().fill(.white.opacity(0.1)))
        }
    }
    
    private func loadLocationName() {
        // Utiliser directement le nom résolu du viewModel si disponible
        if !viewModel.resolvedLocationName.isEmpty {
            displayName = viewModel.resolvedLocationName
            return
        }
        
        guard isCurrentLocation() else {
            displayName = extractCityName(from: weather.location.name)
            return
        }
        
        // Géocodage inverse pour obtenir le vrai nom de la ville
        isLoadingLocation = true
        
        let geocoder = CLGeocoder()
        let location = CLLocation(
            latitude: weather.location.coordinates.latitude,
            longitude: weather.location.coordinates.longitude
        )
        
        geocoder.reverseGeocodeLocation(location) { [self] placemarks, error in
            DispatchQueue.main.async {
                self.isLoadingLocation = false
                
                if let placemark = placemarks?.first {
                    var locationName = ""
                    
                    if let locality = placemark.locality {
                        locationName = locality
                    } else if let administrativeArea = placemark.administrativeArea {
                        locationName = administrativeArea
                    } else if let country = placemark.country {
                        locationName = country
                    } else {
                        locationName = "Position actuelle"
                    }
                    
                    self.displayName = locationName
                } else {
                    self.displayName = "Position actuelle"
                }
            }
        }
    }
    
    private func isCurrentLocation() -> Bool {
        return weather.location.name.contains("position") ||
               weather.location.name.contains("Position") ||
               weather.location.name == "Ma position"
    }
    
    private func extractCityName(from fullName: String) -> String {
        let components = fullName.components(separatedBy: ",")
        return components.first?.trimmingCharacters(in: .whitespaces) ?? fullName
    }
    
    private func formatUpdateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Improved Weather Icon
struct ImprovedWeatherIcon: View {
    let condition: String
    let size: CGFloat
    @State private var isAnimating = false
    
    var body: some View {
        iconForCondition
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
    
    @ViewBuilder
    private var iconForCondition: some View {
        switch condition.lowercased() {
        case "clear":
            ImprovedSunIcon(size: size, isAnimating: isAnimating)
        case "clouds":
            ImprovedCloudIcon(size: size, isAnimating: isAnimating)
        case "rain", "drizzle":
            ImprovedRainIcon(size: size, isAnimating: isAnimating)
        case "snow":
            ImprovedSnowIcon(size: size, isAnimating: isAnimating)
        default:
            ImprovedCloudIcon(size: size, isAnimating: isAnimating)
        }
    }
}

struct ImprovedSunIcon: View {
    let size: CGFloat
    let isAnimating: Bool
    
    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                sunRay(at: index)
            }
            
            Circle()
                .fill(sunGradient)
                .frame(width: size * 0.7, height: size * 0.7)
                .shadow(color: .yellow.opacity(0.6), radius: isAnimating ? 20 : 15)
        }
        .rotationEffect(.degrees(isAnimating ? 360 : 0))
        .animation(.linear(duration: 12).repeatForever(autoreverses: false), value: isAnimating)
    }
    
    private func sunRay(at index: Int) -> some View {
        Rectangle()
            .fill(Color.yellow.opacity(0.9))
            .frame(width: 4, height: size * 0.25)
            .offset(y: -size * 0.45)
            .rotationEffect(.degrees(Double(index) * 45))
    }
    
    private var sunGradient: RadialGradient {
        RadialGradient(
            colors: [Color.yellow, Color.orange],
            center: .center,
            startRadius: size * 0.1,
            endRadius: size * 0.35
        )
    }
}

struct ImprovedCloudIcon: View {
    let size: CGFloat
    let isAnimating: Bool
    
    var body: some View {
        ZStack {
            mainCloud
            cloudBump1
            cloudBump2
            cloudBump3
        }
        .scaleEffect(isAnimating ? 1.05 : 1.0)
        .opacity(isAnimating ? 0.9 : 1.0)
    }
    
    private var mainCloud: some View {
        RoundedRectangle(cornerRadius: size * 0.25)
            .fill(Color.white.opacity(0.95))
            .frame(width: size * 0.9, height: size * 0.5)
    }
    
    private var cloudBump1: some View {
        Circle()
            .fill(Color.white.opacity(0.95))
            .frame(width: size * 0.35, height: size * 0.35)
            .offset(x: -size * 0.2, y: -size * 0.15)
    }
    
    private var cloudBump2: some View {
        Circle()
            .fill(Color.white.opacity(0.95))
            .frame(width: size * 0.45, height: size * 0.45)
            .offset(x: size * 0.1, y: -size * 0.2)
    }
    
    private var cloudBump3: some View {
        Circle()
            .fill(Color.white.opacity(0.95))
            .frame(width: size * 0.3, height: size * 0.3)
            .offset(x: size * 0.25, y: -size * 0.05)
    }
}

struct ImprovedRainIcon: View {
    let size: CGFloat
    let isAnimating: Bool
    
    var body: some View {
        ZStack {
            ImprovedCloudIcon(size: size * 0.85, isAnimating: isAnimating)
            
            VStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { index in
                    rainDrop(at: index)
                }
            }
        }
    }
    
    private func rainDrop(at index: Int) -> some View {
        Rectangle()
            .fill(Color.blue.opacity(0.8))
            .frame(width: 3, height: size * 0.18)
            .offset(x: CGFloat(Double(index) - 1.5) * 10, y: size * 0.25)
            .offset(y: isAnimating ? 15 : 0)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true).delay(Double(index) * 0.15), value: isAnimating)
    }
}

struct ImprovedSnowIcon: View {
    let size: CGFloat
    let isAnimating: Bool
    
    var body: some View {
        ZStack {
            ImprovedCloudIcon(size: size * 0.85, isAnimating: isAnimating)
            
            ForEach(0..<8, id: \.self) { index in
                snowFlake(at: index)
            }
        }
    }
    
    private func snowFlake(at index: Int) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 5, height: 5)
            .offset(
                x: CGFloat(Double(index % 4) - 1.5) * 15,
                y: CGFloat(index / 4) * 15 + size * 0.25
            )
            .offset(y: isAnimating ? 20 : 0)
            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true).delay(Double(index) * 0.1), value: isAnimating)
    }
}

// MARK: - Improved Travel Comfort
struct ImprovedTravelComfort: View {
    let score: Double
    @EnvironmentObject var viewModel: WeatherViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            comfortHeader
            comfortMeter
        }
        .padding(.horizontal, 4)
    }
    
    private var comfortHeader: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "airplane.departure")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.9))
                
                Text("CONFORT VOYAGE")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.8))
                    .tracking(1)
            }
            
            Spacer()
            
            Text(viewModel.getComfortDescription(score: score))
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
    }
    
    private var comfortMeter: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                backgroundMeter
                progressMeter(width: geometry.size.width)
                scoreIndicator(width: geometry.size.width)
            }
        }
        .frame(height: 16)
    }
    
    private var backgroundMeter: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.white.opacity(0.25))
            .frame(height: 16)
    }
    
    private func progressMeter(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(comfortGradient)
            .frame(width: width * score, height: 16)
            .animation(.easeInOut(duration: 1.5), value: score)
    }
    
    private func scoreIndicator(width: CGFloat) -> some View {
        Circle()
            .fill(.white)
            .frame(width: 20, height: 20)
            .offset(x: (width * score) - 10)
            .shadow(color: .black.opacity(0.3), radius: 4)
            .animation(.easeInOut(duration: 1.5), value: score)
    }
    
    private var comfortGradient: LinearGradient {
        LinearGradient(
            colors: comfortGradientColors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    private var comfortGradientColors: [Color] {
        switch score {
        case 0.8...1.0: return [.green, .green.opacity(0.8)]
        case 0.6..<0.8: return [.yellow, .yellow.opacity(0.8)]
        case 0.4..<0.6: return [.orange, .orange.opacity(0.8)]
        default: return [.red, .red.opacity(0.8)]
        }
    }
}

// MARK: - Placeholder Components (à développer)
struct IntelligentLocationPickerSheet: View {
    var body: some View {
        LocationPickerSheet() // Utilise temporairement l'ancien
    }
}

struct ImprovedWeatherMetricsGrid: View {
    let weather: WeatherData
    
    var body: some View {
        WeatherMetricsGrid(weather: weather) // Utilise temporairement l'ancien
    }
}

struct ImprovedForecastSection: View {
    let weather: WeatherData
    
    var body: some View {
        PremiumForecastSection(weather: weather) // Utilise temporairement l'ancien
    }
}

struct TravelInsightsCard: View {
    let weather: WeatherData
    
    var body: some View {
        EmptyView() // À développer
    }
}

struct ImprovedPremiumShowcase: View {
    var body: some View {
        PremiumShowcaseCard() // Utilise temporairement l'ancien
    }
}

struct ImprovedLoadingCard: View {
    var body: some View {
        LoadingWeatherCard() // Utilise temporairement l'ancien
    }
}

struct ImprovedLocationSetupCard: View {
    var body: some View {
        LocationSetupCard() // Utilise temporairement l'ancien
    }
}

// MARK: - Keep existing background animations
struct WeatherAnimatedBackground: View {
    let weather: WeatherData?
    @State private var cloudOffset1: CGFloat = -100
    @State private var cloudOffset2: CGFloat = -150
    @State private var sunRotation: Double = 0
    
    var body: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: backgroundGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Weather-specific animations
            weatherAnimations
        }
        .onAppear {
            startAnimations()
        }
    }
    
    @ViewBuilder
    private var weatherAnimations: some View {
        if let condition = weather?.current.condition.main.lowercased() {
            switch condition {
            case "clear":
                SunAnimation(rotation: sunRotation)
            case "clouds":
                CloudsAnimation(offset1: cloudOffset1, offset2: cloudOffset2)
            case "rain", "drizzle":
                RainAnimation()
                    .background(CloudsAnimation(offset1: cloudOffset1, offset2: cloudOffset2))
            case "snow":
                SnowAnimation()
                    .background(CloudsAnimation(offset1: cloudOffset1, offset2: cloudOffset2))
            default:
                CloudsAnimation(offset1: cloudOffset1, offset2: cloudOffset2)
            }
        }
    }
    
    private var backgroundGradient: [Color] {
        guard let condition = weather?.current.condition.main.lowercased() else {
            return [Color.blue.opacity(0.3), Color.purple.opacity(0.3)]
        }
        
        switch condition {
        case "clear":
            return [Color.orange.opacity(0.4), Color.yellow.opacity(0.3)]
        case "clouds":
            return [Color.gray.opacity(0.4), Color.blue.opacity(0.3)]
        case "rain", "drizzle":
            return [Color.blue.opacity(0.5), Color.indigo.opacity(0.4)]
        case "snow":
            return [Color.white.opacity(0.4), Color.blue.opacity(0.2)]
        default:
            return [Color.blue.opacity(0.3), Color.purple.opacity(0.3)]
        }
    }
    
    private func startAnimations() {
        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
            cloudOffset1 = UIScreen.main.bounds.width + 100
        }
        withAnimation(.linear(duration: 25).repeatForever(autoreverses: false)) {
            cloudOffset2 = UIScreen.main.bounds.width + 150
        }
        withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
            sunRotation = 360
        }
    }
}

// Garder les autres composants d'animation existants...
struct SunAnimation: View {
    let rotation: Double
    
    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                sunRay(at: index)
            }
            
            Circle()
                .fill(sunGradient)
                .frame(width: 100, height: 100)
                .shadow(color: .yellow.opacity(0.5), radius: 20)
        }
        .position(x: UIScreen.main.bounds.width - 80, y: 120)
    }
    
    private func sunRay(at index: Int) -> some View {
        Rectangle()
            .fill(Color.yellow.opacity(0.6))
            .frame(width: 4, height: 40)
            .offset(y: -80)
            .rotationEffect(.degrees(Double(index) * 45 + rotation))
    }
    
    private var sunGradient: RadialGradient {
        RadialGradient(
            colors: [Color.yellow, Color.orange],
            center: .center,
            startRadius: 20,
            endRadius: 50
        )
    }
}

struct CloudsAnimation: View {
    let offset1: CGFloat
    let offset2: CGFloat
    
    var body: some View {
        ZStack {
            cloudView(offset: offset1, size: CGSize(width: 120, height: 60), y: 100)
            cloudView(offset: offset2, size: CGSize(width: 80, height: 40), y: 160)
            cloudView(offset: offset1 - 200, size: CGSize(width: 100, height: 50), y: 80)
        }
    }
    
    private func cloudView(offset: CGFloat, size: CGSize, y: CGFloat) -> some View {
        CloudShape()
            .fill(Color.white.opacity(0.7))
            .frame(width: size.width, height: size.height)
            .position(x: offset, y: y)
    }
}

struct RainAnimation: View {
    @State private var rainDrops: [CGPoint] = []
    
    var body: some View {
        ZStack {
            ForEach(rainDrops.indices, id: \.self) { index in
                rainDrop(at: rainDrops[index])
            }
        }
        .onAppear {
            generateRainDrops()
            animateRain()
        }
    }
    
    private func rainDrop(at position: CGPoint) -> some View {
        Rectangle()
            .fill(Color.blue.opacity(0.6))
            .frame(width: 2, height: 20)
            .position(position)
    }
    
    private func generateRainDrops() {
        rainDrops = (0..<20).map { _ in
            CGPoint(
                x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                y: CGFloat.random(in: -100...(-50))
            )
        }
    }
    
    private func animateRain() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            for index in rainDrops.indices {
                rainDrops[index].y += 3
                if rainDrops[index].y > UIScreen.main.bounds.height + 50 {
                    rainDrops[index].y = -20
                    rainDrops[index].x = CGFloat.random(in: 0...UIScreen.main.bounds.width)
                }
            }
        }
    }
}

struct SnowAnimation: View {
    @State private var snowFlakes: [CGPoint] = []
    
    var body: some View {
        ZStack {
            ForEach(snowFlakes.indices, id: \.self) { index in
                snowFlake(at: snowFlakes[index])
            }
        }
        .onAppear {
            generateSnowFlakes()
            animateSnow()
        }
    }
    
    private func snowFlake(at position: CGPoint) -> some View {
        Circle()
            .fill(Color.white.opacity(0.8))
            .frame(width: 6, height: 6)
            .position(position)
    }
    
    private func generateSnowFlakes() {
        snowFlakes = (0..<15).map { _ in
            CGPoint(
                x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                y: CGFloat.random(in: -100...(-50))
            )
        }
    }
    
    private func animateSnow() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            for index in snowFlakes.indices {
                snowFlakes[index].y += 1.5
                snowFlakes[index].x += sin(snowFlakes[index].y * 0.01) * 0.5
                if snowFlakes[index].y > UIScreen.main.bounds.height + 50 {
                    snowFlakes[index].y = -20
                    snowFlakes[index].x = CGFloat.random(in: 0...UIScreen.main.bounds.width)
                }
            }
        }
    }
}

struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        path.move(to: CGPoint(x: w * 0.25, y: h * 0.7))
        path.addQuadCurve(to: CGPoint(x: w * 0.1, y: h * 0.4), control: CGPoint(x: w * 0.1, y: h * 0.6))
        path.addQuadCurve(to: CGPoint(x: w * 0.3, y: h * 0.1), control: CGPoint(x: w * 0.1, y: h * 0.2))
        path.addQuadCurve(to: CGPoint(x: w * 0.7, y: h * 0.1), control: CGPoint(x: w * 0.5, y: h * 0.0))
        path.addQuadCurve(to: CGPoint(x: w * 0.9, y: h * 0.4), control: CGPoint(x: w * 0.9, y: h * 0.2))
        path.addQuadCurve(to: CGPoint(x: w * 0.75, y: h * 0.7), control: CGPoint(x: w * 0.9, y: h * 0.6))
        path.addLine(to: CGPoint(x: w * 0.25, y: h * 0.7))
        
        return path
    }
}

// Garder les composants existants temporairement
struct WeatherMetricsGrid: View {
    let weather: WeatherData
    @EnvironmentObject var viewModel: WeatherViewModel
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            WeatherMetricCard(
                icon: "humidity.fill",
                title: "Humidité",
                value: "\(weather.current.humidity)%",
                color: .blue
            )
            
            WeatherMetricCard(
                icon: "wind",
                title: "Vent",
                value: viewModel.formatWindSpeed(weather.current.windSpeed),
                color: .green
            )
            
            WeatherMetricCard(
                icon: "eye.fill",
                title: "Visibilité",
                value: "\(Int(weather.current.visibility)) km",
                color: .purple
            )
            
            WeatherMetricCard(
                icon: "sun.max.fill",
                title: "Index UV",
                value: "\(weather.current.uvIndex)",
                color: .orange
            )
        }
    }
}

struct WeatherMetricCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 12) {
            cardHeader
            cardTitle
        }
        .padding(16)
        .background(cardBackground)
        .onAppear {
            isAnimating = true
        }
    }
    
    private var cardHeader: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .scaleEffect(isAnimating ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)
            
            Spacer()
            
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
    }
    
    private var cardTitle: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.ultraThinMaterial)
            .shadow(color: color.opacity(0.2), radius: 8, y: 4)
    }
}

struct PremiumForecastSection: View {
    let weather: WeatherData
    @EnvironmentObject var premiumManager: PremiumManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader
            forecastScrollView
        }
        .padding(20)
        .background(sectionBackground)
    }
    
    private var sectionHeader: some View {
        HStack {
            Text("Prévisions météo")
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
            
            if premiumManager.isPremium {
                PremiumBadge(text: "30 JOURS")
            } else {
                FreeBadge(text: "7 JOURS")
            }
        }
    }
    
    private var forecastScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                forecastCards
                
                if !premiumManager.canUseFeature(.extendedForecast) {
                    UnlockMoreForecastCard()
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    @ViewBuilder
    private var forecastCards: some View {
        let maxDays = premiumManager.canUseFeature(.extendedForecast) ? 30 : 7
        ForEach(weather.forecast.prefix(maxDays), id: \.id) { forecast in
            PremiumForecastCard(forecast: forecast)
        }
    }
    
    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
    }
}

struct PremiumForecastCard: View {
    let forecast: DailyForecast
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var isAnimating = false
    
    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter
    }
    
    var body: some View {
        VStack(spacing: 12) {
            dayLabel
            weatherIcon
            temperatureInfo
            precipitationInfo
            comfortScore
        }
        .padding(16)
        .frame(width: 100)
        .background(cardBackground)
        .scaleEffect(isAnimating ? 1.05 : 1.0)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).delay(Double.random(in: 0...0.5))) {
                isAnimating = true
            }
        }
    }
    
    private var dayLabel: some View {
        Text(dayFormatter.string(from: forecast.date))
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
    }
    
    private var weatherIcon: some View {
        Text(forecast.condition.emoji)
            .font(.title2)
    }
    
    private var temperatureInfo: some View {
        VStack(spacing: 4) {
            Text(viewModel.formatTemperature(forecast.tempMax))
                .font(.headline)
                .fontWeight(.bold)
            
            Text(viewModel.formatTemperature(forecast.tempMin))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var precipitationInfo: some View {
        HStack(spacing: 4) {
            Image(systemName: "drop.fill")
                .font(.caption)
                .foregroundColor(.blue)
            
            Text("\(forecast.precipitationChance)%")
                .font(.caption)
                .foregroundColor(.blue)
        }
    }
    
    private var comfortScore: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .fill(index < Int(forecast.comfortScore * 5) ? comfortColor(forecast.comfortScore) : Color.gray.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            
            Text(comfortLabel(forecast.comfortScore))
                .font(.caption2)
                .foregroundColor(comfortColor(forecast.comfortScore))
        }
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(cardBorder, lineWidth: 1)
            )
    }
    
    private var cardBorder: LinearGradient {
        LinearGradient(
            colors: [.white.opacity(0.2), .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private func comfortColor(_ score: Double) -> Color {
        switch score {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .yellow
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }
    
    private func comfortLabel(_ score: Double) -> String {
        switch score {
        case 0.8...1.0: return "Parfait"
        case 0.6..<0.8: return "Bon"
        case 0.4..<0.6: return "Correct"
        default: return "Difficile"
        }
    }
}

struct UnlockMoreForecastCard: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var isGlowing = false
    
    var body: some View {
        Button(action: {
            viewModel.showingPremiumSheet = true
        }) {
            VStack(spacing: 12) {
                premiumIcon
                premiumInfo
                unlockButton
            }
        }
        .padding(16)
        .frame(width: 100)
        .background(premiumCardBackground)
        .onAppear {
            isGlowing = true
        }
    }
    
    private var premiumIcon: some View {
        ZStack {
            Circle()
                .fill(premiumIconGradient)
                .frame(width: 60, height: 60)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isGlowing)
            
            Image(systemName: "crown.fill")
                .font(.title2)
                .foregroundStyle(crownGradient)
        }
    }
    
    private var premiumInfo: some View {
        VStack(spacing: 4) {
            Text("Premium")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(premiumTextGradient)
            
            Text("30 jours")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var unlockButton: some View {
        Text("Débloquer")
            .font(.caption)
            .foregroundColor(.orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(unlockButtonBackground)
    }
    
    private var premiumIconGradient: RadialGradient {
        RadialGradient(
            colors: [.orange.opacity(0.3), .clear],
            center: .center,
            startRadius: 10,
            endRadius: isGlowing ? 30 : 20
        )
    }
    
    private var crownGradient: LinearGradient {
        LinearGradient(
            colors: [.orange, .red],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var premiumTextGradient: LinearGradient {
        LinearGradient(
            colors: [.orange, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    private var unlockButtonBackground: some View {
        Capsule()
            .fill(Color.orange.opacity(0.1))
            .overlay(
                Capsule()
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
    }
    
    private var premiumCardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(premiumCardBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
            )
    }
    
    private var premiumCardBorder: LinearGradient {
        LinearGradient(
            colors: [.orange.opacity(0.3), .red.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct PremiumShowcaseCard: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var currentFeatureIndex = 0
    @State private var isAnimating = false
    
    private let premiumFeatures = [
        PremiumFeatureDisplay(
            icon: "calendar",
            title: "Prévisions 30 jours",
            description: "Planifiez vos voyages à l'avance",
            color: .blue
        ),
        PremiumFeatureDisplay(
            icon: "brain.head.profile",
            title: "Assistant IA",
            description: "Recommandations personnalisées",
            color: .purple
        ),
        PremiumFeatureDisplay(
            icon: "dot.radiowaves.left.and.right",
            title: "Radar temps réel",
            description: "Suivi des précipitations",
            color: .green
        ),
        PremiumFeatureDisplay(
            icon: "location.fill",
            title: "Destinations illimitées",
            description: "Comparez autant que vous voulez",
            color: .orange
        )
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            showcaseHeader
            featureCarousel
            pageIndicators
            ctaButton
        }
        .padding(24)
        .background(showcaseBackground)
        .onAppear {
            isAnimating = true
            startFeatureRotation()
        }
    }
    
    private var showcaseHeader: some View {
        HStack {
            premiumIcon
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Cirrus Premium")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Débloquez toutes les fonctionnalités")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    private var premiumIcon: some View {
        ZStack {
            Circle()
                .fill(premiumIconGradient)
                .frame(width: 50, height: 50)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)
            
            Image(systemName: "crown.fill")
                .font(.title)
                .foregroundStyle(crownGradient)
        }
    }
    
    private var featureCarousel: some View {
        TabView(selection: $currentFeatureIndex) {
            ForEach(0..<premiumFeatures.count, id: \.self) { index in
                PremiumFeatureCard(feature: premiumFeatures[index])
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 120)
    }
    
    private var pageIndicators: some View {
        HStack(spacing: 8) {
            ForEach(0..<premiumFeatures.count, id: \.self) { index in
                Circle()
                    .fill(index == currentFeatureIndex ? Color.orange : .gray.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .scaleEffect(index == currentFeatureIndex ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: currentFeatureIndex)
            }
        }
    }
    
    private var ctaButton: some View {
        Button(action: {
            viewModel.showingPremiumSheet = true
        }) {
            HStack {
                Image(systemName: "crown.fill")
                    .font(.headline)
                
                Text("Découvrir Premium")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(ctaButtonGradient)
            .cornerRadius(16)
            .shadow(color: .orange.opacity(0.3), radius: 10, y: 5)
        }
    }
    
    private var premiumIconGradient: RadialGradient {
        RadialGradient(
            colors: [.orange.opacity(0.3), .clear],
            center: .center,
            startRadius: 10,
            endRadius: isAnimating ? 25 : 15
        )
    }
    
    private var crownGradient: LinearGradient {
        LinearGradient(
            colors: [.orange, .red],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var ctaButtonGradient: LinearGradient {
        LinearGradient(
            colors: [.orange, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    private var showcaseBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(showcaseBorder, lineWidth: 1)
            )
    }
    
    private var showcaseBorder: LinearGradient {
        LinearGradient(
            colors: [.orange.opacity(0.3), .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private func startFeatureRotation() {
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                currentFeatureIndex = (currentFeatureIndex + 1) % premiumFeatures.count
            }
        }
    }
}

struct PremiumFeatureDisplay {
    let icon: String
    let title: String
    let description: String
    let color: Color
}

struct PremiumBadge: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(premiumBadgeGradient)
            .cornerRadius(8)
    }
    
    private var premiumBadgeGradient: LinearGradient {
        LinearGradient(
            colors: [.orange, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct FreeBadge: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
    }
}

struct LoadingWeatherCard: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 24) {
            loadingIndicator
            loadingText
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(loadingCardBackground)
        .onAppear {
            isAnimating = true
        }
    }
    
    private var loadingIndicator: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 4)
                .frame(width: 60, height: 60)
            
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(loadingGradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 60, height: 60)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
        }
    }
    
    private var loadingText: some View {
        VStack(spacing: 8) {
            Text("Chargement en cours...")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            Text("Récupération des données météo")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
    }
    
    private var loadingGradient: LinearGradient {
        LinearGradient(
            colors: [.orange, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    private var loadingCardBackground: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
    }
}

struct LocationSetupCard: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            setupHeader
            setupActions
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(setupCardBackground)
    }
    
    private var setupHeader: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(locationIconGradient)
            
            VStack(spacing: 8) {
                Text("Configurons votre météo")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Autorisez la géolocalisation pour des prévisions précises")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private var setupActions: some View {
        VStack(spacing: 16) {
            locationButton
            searchButton
            
            #if DEBUG
            debugButtons
            #endif
        }
    }
    
    private var locationButton: some View {
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
                
                Text(viewModel.isRequestingLocation ? "Localisation..." : "Autoriser la géolocalisation")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(locationButtonGradient)
            .cornerRadius(16)
        }
        .disabled(viewModel.isRequestingLocation)
    }
    
    private var searchButton: some View {
        Button(action: {
            viewModel.showingLocationPicker = true
        }) {
            HStack {
                Image(systemName: "magnifyingglass")
                Text("Rechercher une ville")
                    .fontWeight(.medium)
            }
            .foregroundColor(.white.opacity(0.8))
            .padding()
            .frame(maxWidth: .infinity)
            .background(searchButtonBackground)
        }
    }
    
    #if DEBUG
    private var debugButtons: some View {
        VStack(spacing: 8) {
            Text("Mode Debug")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
            
            HStack(spacing: 8) {
                debugButton(city: "Paris", lat: 48.8566, lon: 2.3522)
                debugButton(city: "Londres", lat: 51.5074, lon: -0.1278)
                debugButton(city: "Tokyo", lat: 35.6762, lon: 139.6503)
            }
        }
    }
    
    private func debugButton(city: String, lat: Double, lon: Double) -> some View {
        Button(city) {
            viewModel.simulateLocationUpdate(latitude: lat, longitude: lon, name: city)
        }
        .font(.caption)
        .foregroundColor(.orange)
    }
    #endif
    
    private var locationIconGradient: LinearGradient {
        LinearGradient(
            colors: [.orange, .red],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var locationButtonGradient: LinearGradient {
        LinearGradient(
            colors: [.orange, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    private var searchButtonBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(.white.opacity(0.3), lineWidth: 1)
    }
    
    private var setupCardBackground: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
    }
}

#Preview {
    WeatherView()
        .environmentObject(WeatherViewModel())
        .environmentObject(PremiumManager.shared)
}
