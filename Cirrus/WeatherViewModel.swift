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
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""
    @Published var showingLocationPicker = false
    @Published var showingPremiumSheet = false
    
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
    private let userDefaults = UserDefaults.standard
    
    // MARK: - Combine
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Constants
    private let maxFreeDestinations = 3
    private let maxFreeComparisons = 3
    
    override init() {
        super.init()
        
        setupLocationManager()
        setupBindings()
        loadFavoriteLocations()
        loadPlannedTrips()
    }
    
    // MARK: - Setup
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 100
        
        print("🔍 Location services enabled: \(CLLocationManager.locationServicesEnabled())")
        
        // CORRIGÉ - Ne plus appeler authorizationStatus sur le main thread
        // Le statut sera obtenu automatiquement via le delegate
    }
    
    func checkInitialLocationStatus() {
        print("🔍 Checking initial location status...")
        
        // Le statut sera mis à jour automatiquement via locationManagerDidChangeAuthorization
        // Ne rien forcer ici pour éviter les warnings
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self else { return }
            
            if self.userLocation == nil && !self.isRequestingLocation {
                print("🏙️ No location obtained after 3 seconds, using default")
                self.setDefaultLocation()
            }
        }
    }
    
    private func startLocationUpdates() {
        // CORRIGÉ - Vérification sans appel direct à authorizationStatus
        guard CLLocationManager.locationServicesEnabled() else {
            print("❌ Location services not enabled")
            setDefaultLocation()
            return
        }
        
        // Vérifier le statut via notre propriété plutôt que l'API directe
        switch locationPermissionStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            print("▶️ Starting location updates...")
            isRequestingLocation = true
            locationManager.startUpdatingLocation()
            
            // Arrêter après 10 secondes max
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.stopLocationUpdates()
            }
        case .denied, .restricted:
            print("❌ Location permission denied/restricted")
            setDefaultLocation()
        case .notDetermined:
            print("❓ Location permission not determined yet")
            // Attendre que l'autorisation soit demandée
        @unknown default:
            print("🤷‍♂️ Unknown location status")
            setDefaultLocation()
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
                    await self?.searchLocations(query: searchText)
                }
            }
            .store(in: &cancellables)
        
        premiumManager.$isPremium
            .sink { [weak self] isPremium in
                self?.handlePremiumStatusChange(isPremium)
            }
            .store(in: &cancellables)
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
    
    // MARK: - Location Permission Management - CORRIGÉ
    
    func requestLocationPermission() async {
        print("🔑 Requesting location permission...")
        
        // CORRIGÉ - Utiliser notre propriété au lieu de l'API directe
        let currentStatus = locationPermissionStatus
        print("📍 Current status from property: \(currentStatus.rawValue)")
        
        switch currentStatus {
        case .notDetermined:
            print("❓ Permission not determined, requesting...")
            hasTriedLocationRequest = true
            locationManager.requestWhenInUseAuthorization()
            
            // Attendre la réponse via le delegate
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
        hasTriedLocationRequest = true
        
        Task {
            await loadWeatherForCurrentLocation()
        }
    }
    #endif
    
    // MARK: - Location Search
    
    private func searchLocations(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        do {
            let locations = try await weatherService.searchLocations(query: query)
            searchResults = locations
        } catch {
            print("Search error: \(error)")
            searchResults = []
        }
    }
    
    func selectLocation(_ location: Location) async {
        searchText = ""
        searchResults = []
        showingLocationPicker = false
        
        await loadWeather(for: location)
    }
    
    // MARK: - Favorites Management
    
    func toggleFavorite(for location: Location) {
        if location.isFavorite {
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
        return favoriteLocations.contains { $0.coordinates.latitude == location.coordinates.latitude &&
            $0.coordinates.longitude == location.coordinates.longitude }
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
        return "\(Int(temperature.rounded()))°"
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
        case 0.8...1.0:
            return .green
        case 0.6..<0.8:
            return .yellow
        case 0.4..<0.6:
            return .orange
        case 0.2..<0.4:
            return .red
        default:
            return .red
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
