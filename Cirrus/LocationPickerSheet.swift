import SwiftUI

struct LocationPickerSheet: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                SearchBar(text: $searchText)
                    .padding()
                
                if searchText.isEmpty {
                    // Default view with recent locations and suggestions
                    DefaultLocationView()
                } else {
                    // Search results
                    SearchResultsView()
                }
                
                Spacer()
            }
            .navigationTitle("Choisir une destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: searchText) { _, newValue in // Correction iOS 17
            viewModel.searchText = newValue
        }
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var text: String
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Rechercher une ville...", text: $text)
                .focused($isSearchFocused)
                .textFieldStyle(PlainTextFieldStyle())
                .autocapitalization(.words)
                .disableAutocorrection(true)
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .onAppear {
            isSearchFocused = true
        }
    }
}

// MARK: - Default Location View

struct DefaultLocationView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Current location section
                CurrentLocationSection()
                
                // Favorites section
                if !viewModel.favoriteLocations.isEmpty {
                    FavoritesListSection()
                }
                
                // Popular destinations
                PopularDestinationsSection()
                
                Spacer(minLength: 100)
            }
            .padding()
        }
    }
}

// MARK: - Current Location Section - Corrigée

struct CurrentLocationSection: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Position actuelle")
                .font(.headline)
                .fontWeight(.semibold)
            
            Button(action: {
                Task {
                    await viewModel.requestLocationPermission()
                    await viewModel.loadWeatherForCurrentLocation()
                    dismiss()
                }
            }) {
                HStack {
                    if viewModel.isRequestingLocation {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .scaleEffect(0.8)
                            .frame(width: 24)
                    } else {
                        Image(systemName: "location.fill")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ma position")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text(locationSubtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .foregroundColor(.primary)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
            }
            .disabled(viewModel.isRequestingLocation)
        }
    }
    
    private var locationSubtitle: String {
        if viewModel.isRequestingLocation {
            return "Localisation en cours..."
        }
        
        switch viewModel.locationPermissionStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return "Utiliser la géolocalisation"
        case .denied, .restricted:
            return "Géolocalisation désactivée"
        case .notDetermined:
            return "Autorisation requise"
        @unknown default:
            return "Statut inconnu"
        }
    }
}

// MARK: - Favorites List Section

struct FavoritesListSection: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mes destinations")
                .font(.headline)
                .fontWeight(.semibold)
            
            ForEach(viewModel.favoriteLocations, id: \.id) { location in
                LocationRow(
                    location: location,
                    showFavoriteButton: false,
                    action: {
                        Task {
                            await viewModel.selectLocation(location)
                            dismiss()
                        }
                    }
                )
            }
        }
    }
}

// MARK: - Popular Destinations Section

struct PopularDestinationsSection: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    
    private let popularDestinations = [
        Location(name: "Paris", country: "France", coordinates: Location.Coordinates(latitude: 48.8566, longitude: 2.3522), timezone: nil, isFavorite: false, isPremium: false),
        Location(name: "Londres", country: "Royaume-Uni", coordinates: Location.Coordinates(latitude: 51.5074, longitude: -0.1278), timezone: nil, isFavorite: false, isPremium: false),
        Location(name: "New York", country: "États-Unis", coordinates: Location.Coordinates(latitude: 40.7128, longitude: -74.0060), timezone: nil, isFavorite: false, isPremium: false),
        Location(name: "Tokyo", country: "Japon", coordinates: Location.Coordinates(latitude: 35.6762, longitude: 139.6503), timezone: nil, isFavorite: false, isPremium: false),
        Location(name: "Sydney", country: "Australie", coordinates: Location.Coordinates(latitude: -33.8688, longitude: 151.2093), timezone: nil, isFavorite: false, isPremium: false),
        Location(name: "Rome", country: "Italie", coordinates: Location.Coordinates(latitude: 41.9028, longitude: 12.4964), timezone: nil, isFavorite: false, isPremium: false)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Destinations populaires")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(popularDestinations, id: \.id) { location in
                    PopularDestinationCard(location: location) {
                        Task {
                            await viewModel.selectLocation(location)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Popular Destination Card

struct PopularDestinationCard: View {
    let location: Location
    let action: () -> Void
    @State private var weatherData: WeatherData?
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(location.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if let weather = weatherData {
                        Text(weather.current.condition.emoji)
                            .font(.title3)
                    }
                }
                
                Text(location.country)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let weather = weatherData {
                    HStack {
                        Text(WeatherViewModel().formatTemperature(weather.current.temperature))
                            .font(.title3)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Text(weather.current.condition.description)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .foregroundColor(.primary)
            .padding(12)
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
        }
        .task {
            do {
                weatherData = try await WeatherService.shared.getWeatherData(for: location)
            } catch {
                // Handle error silently for popular destinations
            }
        }
    }
}

// MARK: - Search Results View

struct SearchResultsView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        if viewModel.isLoading {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Recherche en cours...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
        } else if viewModel.searchResults.isEmpty && !viewModel.searchText.isEmpty {
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
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.searchResults, id: \.id) { location in
                        LocationRow(
                            location: location,
                            showFavoriteButton: true,
                            action: {
                                Task {
                                    await viewModel.selectLocation(location)
                                    dismiss()
                                }
                            }
                        )
                        
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
}

// MARK: - Location Row

struct LocationRow: View {
    let location: Location
    let showFavoriteButton: Bool
    let action: () -> Void
    
    @EnvironmentObject var viewModel: WeatherViewModel
    @State private var weatherData: WeatherData?
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Location icon
                Image(systemName: "location.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                // Location info
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
                
                // Weather info
                if let weather = weatherData {
                    HStack(spacing: 8) {
                        Text(weather.current.condition.emoji)
                            .font(.title3)
                        
                        Text(viewModel.formatTemperature(weather.current.temperature))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                
                // Favorite button
                if showFavoriteButton {
                    Button(action: {
                        viewModel.toggleFavorite(for: location)
                    }) {
                        Image(systemName: viewModel.isFavorite(location) ? "heart.fill" : "heart")
                            .foregroundColor(viewModel.isFavorite(location) ? .red : .secondary)
                            .font(.title3)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
        .task {
            // Load weather data for search results
            if showFavoriteButton {
                do {
                    weatherData = try await WeatherService.shared.getWeatherData(for: location)
                } catch {
                    // Handle error silently for search results
                }
            }
        }
    }
}

#Preview {
    LocationPickerSheet()
        .environmentObject(WeatherViewModel())
}
