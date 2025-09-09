import Foundation
import CoreLocation
import Combine
import SwiftUI

@MainActor
class WeatherViewModel: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var currentWeather: WeatherData?
    @Published var favoriteLocations: [Location] = []
    @Published var searchResults: [Location] = []
    @Published var intelligentSuggestions: [LocationSuggestion] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""
    @Published var showingLocationPicker = false
    @Published var showingPremiumSheet = false
    
    // Location display
    @Published var resolvedLocationName: String = ""
    @Published var isResolvingLocation = false
    
    // Comparison feature
    @Published var selectedLocationsForComparison: [Location] = []
    @Published var comparisonResults: [WeatherData] = []
    @Published var showingComparison = false
    
    // Trip planning
    @Published var currentTrip: Trip?
    @Published var plannedTrips: [Trip] = []
    
    // User location
    @Published var userLocation: CLLocation?
    @Published var locationPermissionStatus: CLAuthorizationStatus = .notDetermined
    @Published var isRequestingLocation = false
    @Published var hasTriedLocationRequest = false
    
    // MARK: - Services
    private let weatherService = WeatherService.shared
    private let premiumManager = PremiumManager.shared
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let userDefaults = UserDefaults.standard
    
    // MARK: - Combine
    private var cancellables = Set<AnyCancellable>()
    private var geocodingTask: Task<Void, Never>?
    
    // MARK: - Constants
    private let maxFreeDestinations = 3
    private let maxFreeComparisons = 3
    
    override init() {
        super.init()
        
        setupLocationManager()
        setupBindings()
        loadFavoriteLocations()
        loadPlannedTrips()
        generateIntelligentSuggestions()
    }
    
    // MARK: - Setup
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 100
        
        print("🔍 Location services enabled: \(CLLocationManager.locationServicesEnabled())")
    }
    
    func checkInitialLocationStatus() {
        print("🔍 Checking initial location status...")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self else { return }
            
            if self.userLocation == nil && !self.isRequestingLocation {
                print("🏙️ No location obtained after 3 seconds, using default")
                self.setDefaultLocation()
            }
        }
    }
    
    private func startLocationUpdates() {
        guard CLLocationManager.locationServicesEnabled() else {
            print("❌ Location services not enabled")
            setDefaultLocation()
            return
        }
        
        print("▶️ Starting location updates...")
        isRequestingLocation = true
        locationManager.startUpdatingLocation()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.stopLocationUpdates()
        }
    }
    
    private func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
        isRequestingLocation = false
        print("⏹️ Stopped location updates")
    }
    
    private func setDefaultLocation() {
        let defaultLocation = CLLocation(latitude: 48.8566, longitude: 2.3522)
        userLocation = defaultLocation
        resolvedLocationName = "Paris" // Nom par défaut
        print("🏙️ Using default location: Paris")
        
        Task {
            await loadWeatherForCurrentLocation()
        }
    }
    
    private func setupBindings() {
        $searchText
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] searchText in
                Task {
                    await self?.performIntelligentSearch(query: searchText)
                }
            }
            .store(in: &cancellables)
        
        premiumManager.$isPremium
            .sink { [weak self] isPremium in
                self?.handlePremiumStatusChange(isPremium)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Enhanced Location Resolution
    
    private func resolveLocationName(for coordinates: CLLocationCoordinate2D) async {
        print("🌍 Resolving location name for coordinates: \(coordinates.latitude), \(coordinates.longitude)")
        
        isResolvingLocation = true
        
        // Annuler la tâche précédente si elle existe
        geocodingTask?.cancel()
        
        geocodingTask = Task {
            let location = CLLocation(latitude: coordinates.latitude, longitude: coordinates.longitude)
            
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    if let placemark = placemarks.first {
                        self.resolvedLocationName = self.formatLocationName(from: placemark)
                        print("✅ Resolved location name: \(self.resolvedLocationName)")
                    } else {
                        self.resolvedLocationName = "Position actuelle"
                    }
                    self.isResolvingLocation = false
                }
            } catch {
                await MainActor.run {
                    self.resolvedLocationName = "Position actuelle"
                    self.isResolvingLocation = false
                    print("❌ Geocoding error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func formatLocationName(from placemark: CLPlacemark) -> String {
        // Ordre de priorité pour le nom de lieu
        if let locality = placemark.locality {
            return locality
        } else if let subAdministrativeArea = placemark.subAdministrativeArea {
            return subAdministrativeArea
        } else if let administrativeArea = placemark.administrativeArea {
            return administrativeArea
        } else if let country = placemark.country {
            return country
        } else {
            return "Position actuelle"
        }
    }
    
    // MARK: - Intelligent Search
    
    private func performIntelligentSearch(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        print("🔍 Performing intelligent search for: \(query)")
        
        do {
            // Recherche normale
            let normalResults = try await weatherService.searchLocations(query: query)
            
            // Recherche contextuelle
            let contextualResults = await getContextualSuggestions(for: query)
            
            // Combiner et déduplicquer
            var combinedResults = normalResults
            
            for suggestion in contextualResults {
                if !combinedResults.contains(where: { $0.name.lowercased() == suggestion.name.lowercased() }) {
                    combinedResults.append(suggestion)
                }
            }
            
            searchResults = Array(combinedResults.prefix(8)) // Limiter à 8 résultats
            
        } catch {
            print("Search error: \(error)")
            searchResults = []
        }
    }
    
    private func getContextualSuggestions(for query: String) async -> [Location] {
        let queryLower = query.lowercased()
        var suggestions: [Location] = []
        
        // Suggestions basées sur la proximité géographique
        if let userLocation = userLocation {
            suggestions.append(contentsOf: getNearbyDestinations(from: userLocation, matching: queryLower))
        }
        
        // Suggestions saisonnières
        suggestions.append(contentsOf: getSeasonalSuggestions(matching: queryLower))
        
        // Suggestions par type de voyage
        suggestions.append(contentsOf: getTravelTypeSuggestions(matching: queryLower))
        
        return suggestions
    }
    
    private func getNearbyDestinations(from location: CLLocation, matching query: String) -> [Location] {
        let nearbyDestinations = [
            ("Nice", 43.7102, 7.2620),
            ("Marseille", 43.2965, 5.3698),
            ("Lyon", 45.7640, 4.8357),
            ("Bordeaux", 44.8378, -0.5792),
            ("Toulouse", 43.6047, 1.4442),
            ("Strasbourg", 48.5734, 7.7521),
            ("Nantes", 47.2184, -1.5536),
            ("Lille", 50.6292, 3.0573)
        ]
        
        return nearbyDestinations.compactMap { (name, lat, lon) in
            if name.lowercased().contains(query) || query.contains(name.lowercased()) {
                return Location(
                    name: name,
                    country: "France",
                    coordinates: Location.Coordinates(latitude: lat, longitude: lon),
                    timezone: "Europe/Paris",
                    isFavorite: false,
                    isPremium: false
                )
            }
            return nil
        }
    }
    
    private func getSeasonalSuggestions(matching query: String) -> [Location] {
        let month = Calendar.current.component(.month, from: Date())
        let seasonalDestinations = getSeasonalDestinations(for: month)
        
        return seasonalDestinations.compactMap { destination in
            if destination.name.lowercased().contains(query) || query.contains(destination.name.lowercased()) {
                return destination
            }
            return nil
        }
    }
    
    private func getTravelTypeSuggestions(matching query: String) -> [Location] {
        let travelTypes: [String: [Location]] = [
            "plage": [
                Location(name: "Nice", country: "France", coordinates: Location.Coordinates(latitude: 43.7102, longitude: 7.2620), timezone: nil, isFavorite: false, isPremium: false),
                Location(name: "Cannes", country: "France", coordinates: Location.Coordinates(latitude: 43.5528, longitude: 7.0174), timezone: nil, isFavorite: false, isPremium: false)
            ],
            "montagne": [
                Location(name: "Chamonix", country: "France", coordinates: Location.Coordinates(latitude: 45.9237, longitude: 6.8694), timezone: nil, isFavorite: false, isPremium: false),
                Location(name: "Annecy", country: "France", coordinates: Location.Coordinates(latitude: 45.8992, longitude: 6.1294), timezone: nil, isFavorite: false, isPremium: false)
            ],
            "ski": [
                Location(name: "Val d'Isère", country: "France", coordinates: Location.Coordinates(latitude: 45.4486, longitude: 6.9806), timezone: nil, isFavorite: false, isPremium: false),
                Location(name: "Courchevel", country: "France", coordinates: Location.Coordinates(latitude: 45.4167, longitude: 6.6333), timezone: nil, isFavorite: false, isPremium: false)
            ]
        ]
        
        for (type, destinations) in travelTypes {
            if query.contains(type) {
                return destinations
            }
        }
        
        return []
    }
    
    private func getSeasonalDestinations(for month: Int) -> [Location] {
        switch month {
        case 12, 1, 2: // Hiver
            return [
                Location(name: "Marrakech", country: "Maroc", coordinates: Location.Coordinates(latitude: 31.6295, longitude: -7.9811), timezone: nil, isFavorite: false, isPremium: false),
                Location(name: "Dubai", country: "Émirats Arabes Unis", coordinates: Location.Coordinates(latitude: 25.2048, longitude: 55.2708), timezone: nil, isFavorite: false, isPremium: false),
                Location(name: "Bangkok", country: "Thaïlande", coordinates: Location.Coordinates(latitude: 13.7563, longitude: 100.5018), timezone: nil, isFavorite: false, isPremium: false)
            ]
        case 3, 4, 5: // Printemps
            return [
                Location(name: "Tokyo", country: "Japon", coordinates: Location.Coordinates(latitude: 35.6762, longitude: 139.6503), timezone: nil, isFavorite: false, isPremium: false),
                Location(name: "Athènes", country: "Grèce", coordinates: Location.Coordinates(latitude: 37.9838, longitude: 23.7275), timezone: nil, isFavorite: false, isPremium: false),
                Location(name: "Istanbul", country: "Turquie", coordinates: Location.Coordinates(latitude: 41.0082, longitude: 28.9784), timezone: nil, isFavorite: false, isPremium: false)
            ]
        case 6, 7, 8: // Été
            return [
                Location(name: "Oslo", country: "Norvège", coordinates: Location.Coordinates(latitude: 59.9139, longitude: 10.7522), timezone: nil, isFavorite: false, isPremium: false),
                Location(name: "Reykjavik", country: "Islande", coordinates: Location.Coordinates(latitude: 64.1466, longitude: -21.9426), timezone: nil, isFavorite: false, isPremium: false),
                Location(name: "Édimbourg", country: "Écosse", coordinates: Location.Coordinates(latitude: 55.9533, longitude: -3.1883), timezone: nil, isFavorite: false, isPremium: false)
            ]
        case 9, 10, 11: // Automne
            return [
                Location(name: "Delhi", country: "Inde", coordinates: Location.Coordinates(latitude: 28.7041, longitude: 77.1025), timezone: nil, isFavorite: false, isPremium: false),
                Location(name: "Katmandou", country: "Népal", coordinates: Location.Coordinates(latitude: 27.7172, longitude: 85.3240), timezone: nil, isFavorite: false, isPremium: false),
                Location(name: "Amman", country: "Jordanie", coordinates: Location.Coordinates(latitude: 31.9454, longitude: 35.9284), timezone: nil, isFavorite: false, isPremium: false)
            ]
        default:
            return []
        }
    }
    
    private func generateIntelligentSuggestions() {
        let currentMonth = Calendar.current.component(.month, from: Date())
        let seasonalDests = getSeasonalDestinations(for: currentMonth)
        
        intelligentSuggestions = seasonalDests.prefix(3).map { destination in
            LocationSuggestion(
                location: destination,
                reason: getSuggestionReason(for: destination, month: currentMonth),
                priority: .seasonal
            )
        }
        
        // Ajouter des suggestions populaires
        let popularDestinations = [
            Location(name: "Paris", country: "France", coordinates: Location.Coordinates(latitude: 48.8566, longitude: 2.3522), timezone: nil, isFavorite: false, isPremium: false),
            Location(name: "Londres", country: "Royaume-Uni", coordinates: Location.Coordinates(latitude: 51.5074, longitude: -0.1278), timezone: nil, isFavorite: false, isPremium: false),
            Location(name: "New York", country: "États-Unis", coordinates: Location.Coordinates(latitude: 40.7128, longitude: -74.0060), timezone: nil, isFavorite: false, isPremium: false)
        ]
        
        intelligentSuggestions.append(contentsOf: popularDestinations.map { destination in
            LocationSuggestion(
                location: destination,
                reason: "Destination populaire",
                priority: .popular
            )
        })
    }
    
    private func getSuggestionReason(for location: Location, month: Int) -> String {
        switch month {
        case 12, 1, 2:
            return "Climat idéal en hiver"
        case 3, 4, 5:
            return "Parfait au printemps"
        case 6, 7, 8:
            return "Fraîcheur estivale"
        case 9, 10, 11:
            return "Excellente saison"
        default:
            return "Recommandé"
        }
    }
    
    // MARK: - Weather Data Methods
    
    func loadWeatherForCurrentLocation() async {
        print("🌤️ Loading weather for current location...")
        
        guard let userLocation = userLocation else {
            print("📍 No user location available")
            
            if !hasTriedLocationRequest {
                hasTriedLocationRequest = true
                await requestLocationPermission()
            } else {
                print("🔄 Already tried location request, using default location")
                setDefaultLocation()
            }
            return
        }
        
        print("📍 Using location: \(userLocation.coordinate.latitude), \(userLocation.coordinate.longitude)")
        
        // Résoudre le nom de lieu si ce n'est pas déjà fait
        if resolvedLocationName.isEmpty {
            await resolveLocationName(for: userLocation.coordinate)
        }
        
        let location = Location(
            name: resolvedLocationName.isEmpty ? "Ma position" : resolvedLocationName,
            country: "",
            coordinates: Location.Coordinates(
                latitude: userLocation.coordinate.latitude,
                longitude: userLocation.coordinate.longitude
            ),
            timezone: TimeZone.current.identifier,
            isFavorite: false,
            isPremium: false
        )
        
        await loadWeather(for: location)
    }
    
    func loadWeather(for location: Location) async {
        print("🌤️ Loading weather for: \(location.name)")
        isLoading = true
        errorMessage = nil
        
        do {
            let weatherData = try await weatherService.getWeatherData(for: location)
            currentWeather = weatherData
            print("✅ Weather data loaded successfully")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Weather loading error: \(error)")
        }
        
        isLoading = false
    }
    
    func refreshWeather() async {
        guard let currentLocation = currentWeather?.location else {
            await loadWeatherForCurrentLocation()
            return
        }
        await loadWeather(for: currentLocation)
    }
    
    // MARK: - Location Permission Management
    
    func requestLocationPermission() async {
        print("🔑 Requesting location permission...")
        
        let currentStatus = locationPermissionStatus
        print("📍 Current status from property: \(currentStatus.rawValue)")
        
        switch currentStatus {
        case .notDetermined:
            print("❓ Permission not determined, requesting...")
            hasTriedLocationRequest = true
            locationManager.requestWhenInUseAuthorization()
            
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            
        case .authorizedWhenInUse, .authorizedAlways:
            print("✅ Already authorized, starting location updates")
            startLocationUpdates()
            
        case .denied, .restricted:
            print("❌ Location denied/restricted")
            showLocationPermissionAlert()
            setDefaultLocation()
            
        @unknown default:
            print("🤷‍♂️ Unknown status")
            setDefaultLocation()
        }
        
        if userLocation == nil {
            print("⏰ No location after timeout, using default")
            setDefaultLocation()
        }
    }
    
    private func showLocationPermissionAlert() {
        errorMessage = "Pour obtenir la météo de votre position, activez la géolocalisation dans Réglages > Confidentialité > Services de localisation > Cirrus"
    }
    
    // MARK: - Test Methods
    
    #if DEBUG
    func loadTestWeatherData() async {
        print("🧪 Loading test weather data (Paris)")
        let testLocation = Location(
            name: "Paris (Test)",
            country: "France",
            coordinates: Location.Coordinates(
                latitude: 48.8566,
                longitude: 2.3522
            ),
            timezone: "Europe/Paris",
            isFavorite: false,
            isPremium: false
        )
        
        await loadWeather(for: testLocation)
    }
    
    func simulateLocationUpdate(latitude: Double, longitude: Double, name: String = "Position simulée") {
        print("🎯 Simulating location: \(name) (\(latitude), \(longitude))")
        let simulatedLocation = CLLocation(latitude: latitude, longitude: longitude)
        userLocation = simulatedLocation
        resolvedLocationName = name
        hasTriedLocationRequest = true
        
        Task {
            await loadWeatherForCurrentLocation()
        }
    }
    #endif
    
    // MARK: - Location Selection
    
    func selectLocation(_ location: Location) async {
        searchText = ""
        searchResults = []
        showingLocationPicker = false
        
        await loadWeather(for: location)
    }
    
    // MARK: - Favorites Management
    
    func toggleFavorite(for location: Location) {
        if isFavorite(location) {
            removeFavorite(location)
        } else {
            addFavorite(location)
        }
    }
    
    private func addFavorite(_ location: Location) {
        if !premiumManager.isPremium && favoriteLocations.count >= maxFreeDestinations {
            showingPremiumSheet = true
            return
        }
        
        let favoriteLocation = Location(
            name: location.name,
            country: location.country,
            coordinates: location.coordinates,
            timezone: location.timezone,
            isFavorite: true,
            isPremium: location.isPremium
        )
        
        favoriteLocations.append(favoriteLocation)
        saveFavoriteLocations()
        
        if !premiumManager.isPremium {
            premiumManager.incrementFavoriteDestinations()
        }
    }
    
    private func removeFavorite(_ location: Location) {
        favoriteLocations.removeAll { $0.id == location.id }
        saveFavoriteLocations()
    }
    
    func isFavorite(_ location: Location) -> Bool {
        return favoriteLocations.contains { fav in
            abs(fav.coordinates.latitude - location.coordinates.latitude) < 0.001 &&
            abs(fav.coordinates.longitude - location.coordinates.longitude) < 0.001
        }
    }
    
    // MARK: - Comparison Feature
    
    func addToComparison(_ location: Location) {
        let maxComparisons = premiumManager.isPremium ? 10 : maxFreeComparisons
        
        guard selectedLocationsForComparison.count < maxComparisons else {
            if !premiumManager.isPremium {
                showingPremiumSheet = true
            }
            return
        }
        
        if !selectedLocationsForComparison.contains(where: { $0.id == location.id }) {
            selectedLocationsForComparison.append(location)
        }
        
        if !premiumManager.isPremium {
            premiumManager.incrementComparisonCount()
        }
    }
    
    func removeFromComparison(_ location: Location) {
        selectedLocationsForComparison.removeAll { $0.id == location.id }
        comparisonResults.removeAll { $0.location.id == location.id }
    }
    
    func startComparison() async {
        guard !selectedLocationsForComparison.isEmpty else { return }
        
        isLoading = true
        comparisonResults = []
        
        do {
            let results = try await weatherService.getMultipleWeatherData(for: selectedLocationsForComparison)
            comparisonResults = results.sorted { $0.forecast.first?.comfortScore ?? 0 > $1.forecast.first?.comfortScore ?? 0 }
            showingComparison = true
        } catch {
            if case WeatherError.premiumRequired = error {
                showingPremiumSheet = true
            } else {
                errorMessage = error.localizedDescription
            }
        }
        
        isLoading = false
    }
    
    func clearComparison() {
        selectedLocationsForComparison.removeAll()
        comparisonResults.removeAll()
        showingComparison = false
    }
    
    // MARK: - Trip Planning
    
    func createTrip(name: String, destinations: [Location], startDate: Date, endDate: Date) -> Trip {
        let tripDestinations = destinations.map { location in
            TripDestination(
                location: location,
                arrivalDate: startDate,
                departureDate: endDate,
                weatherData: nil,
                notes: nil,
                activities: []
            )
        }
        
        let trip = Trip(
            name: name,
            destinations: tripDestinations,
            startDate: startDate,
            endDate: endDate,
            createdAt: Date(),
            isActive: true
        )
        
        plannedTrips.append(trip)
        savePlannedTrips()
        
        return trip
    }
    
    func loadTripWeatherData(_ trip: Trip) async {
        guard premiumManager.canUseFeature(.extendedForecast) else {
            showingPremiumSheet = true
            return
        }
        
        for destination in trip.destinations {
            do {
                _ = try await weatherService.getWeatherData(for: destination.location)
            } catch {
                print("Error loading weather for trip destination: \(error)")
            }
        }
    }
    
    // MARK: - Premium Features
    
    private func handlePremiumStatusChange(_ isPremium: Bool) {
        if !isPremium {
            if favoriteLocations.count > maxFreeDestinations {
                // Informer l'utilisateur qu'il doit choisir ses favorites
            }
            
            if selectedLocationsForComparison.count > maxFreeComparisons {
                selectedLocationsForComparison = Array(selectedLocationsForComparison.prefix(maxFreeComparisons))
            }
        }
    }
    
    func getAvailableForecastDays() -> Int {
        return premiumManager.canUseFeature(.extendedForecast) ? 30 : 7
    }
    
    // MARK: - Persistence
    
    private func saveFavoriteLocations() {
        if let data = try? JSONEncoder().encode(favoriteLocations) {
            userDefaults.set(data, forKey: "FavoriteLocations")
        }
    }
    
    private func loadFavoriteLocations() {
        if let data = userDefaults.data(forKey: "FavoriteLocations"),
           let locations = try? JSONDecoder().decode([Location].self, from: data) {
            favoriteLocations = locations
        }
    }
    
    private func savePlannedTrips() {
        if let data = try? JSONEncoder().encode(plannedTrips) {
            userDefaults.set(data, forKey: "PlannedTrips")
        }
    }
    
    private func loadPlannedTrips() {
        if let data = userDefaults.data(forKey: "PlannedTrips"),
           let trips = try? JSONDecoder().decode([Trip].self, from: data) {
            plannedTrips = trips
        }
    }
    
    // MARK: - Utility Methods
    
    func formatTemperature(_ temperature: Double) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .temperatureWithoutUnit
        let temp = Measurement(value: temperature, unit: UnitTemperature.celsius)
        return "\(Int(temp.value))°"
    }
    
    func formatWindSpeed(_ speed: Double) -> String {
        return "\(Int(speed)) km/h"
    }
    
    func formatPrecipitationChance(_ chance: Int) -> String {
        return "\(chance)%"
    }
    
    func getComfortDescription(score: Double) -> String {
        switch score {
        case 0.8...1.0:
            return "Parfait pour voyager"
        case 0.6..<0.8:
            return "Conditions favorables"
        case 0.4..<0.6:
            return "Conditions correctes"
        case 0.2..<0.4:
            return "Conditions difficiles"
        default:
            return "Conditions défavorables"
        }
    }
    
    func getComfortColor(score: Double) -> Color {
        switch score {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .yellow
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }
    
    func requestLocationPermissionForced() async {
        print("🔑 FORCED location permission request...")
        hasTriedLocationRequest = false
        locationManager.requestWhenInUseAuthorization()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        print("📍 After forced request, status: \(locationPermissionStatus.rawValue)")
    }
}

// MARK: - CLLocationManagerDelegate

extension WeatherViewModel: CLLocationManagerDelegate {
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        print("📍 Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        print("📍 Accuracy: \(location.horizontalAccuracy)m, Age: \(abs(location.timestamp.timeIntervalSinceNow))s")
        
        guard location.horizontalAccuracy < 100,
              abs(location.timestamp.timeIntervalSinceNow) < 60 else {
            print("⚠️ Location ignored due to poor accuracy or age")
            return
        }
        
        Task { @MainActor in
            self.userLocation = location
            self.stopLocationUpdates()
            
            // Résoudre le nom de lieu
            await self.resolveLocationName(for: location.coordinate)
            
            await self.loadWeatherForCurrentLocation()
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error.localizedDescription)")
        
        Task { @MainActor in
            self.isRequestingLocation = false
            self.stopLocationUpdates()
            
            if let clError = error as? CLError {
                switch clError.code {
                case .denied:
                    self.errorMessage = "Géolocalisation refusée. Activez-la dans les Réglages."
                case .locationUnknown:
                    self.errorMessage = "Position introuvable. Vérifiez votre connexion."
                case .network:
                    self.errorMessage = "Erreur réseau lors de la géolocalisation."
                default:
                    self.errorMessage = "Erreur de géolocalisation: \(error.localizedDescription)"
                }
            } else {
                self.errorMessage = "Erreur de géolocalisation: \(error.localizedDescription)"
            }
            
            self.setDefaultLocation()
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("🔄 Authorization status changed to: \(status.rawValue)")
        print("📊 Status meanings: 0=notDetermined, 1=restricted, 2=denied, 3=authorizedAlways, 4=authorizedWhenInUse")
        
        Task { @MainActor in
            self.locationPermissionStatus = status
            
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                print("✅ Location authorized - starting location updates")
                self.startLocationUpdates()
                
            case .denied, .restricted:
                print("❌ Location denied or restricted")
                self.showLocationPermissionAlert()
                self.setDefaultLocation()
                
            case .notDetermined:
                print("❓ Location permission not determined")
                
            @unknown default:
                print("🤷‍♂️ Unknown location authorization status")
                self.setDefaultLocation()
            }
        }
    }
}

// MARK: - Supporting Models

struct LocationSuggestion: Identifiable {
    let id = UUID()
    let location: Location
    let reason: String
    let priority: SuggestionPriority
}

enum SuggestionPriority {
    case nearby
    case seasonal
    case popular
    case recent
}
