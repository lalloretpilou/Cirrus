//
//  CirrusApp.swift
//  Cirrus
//
//  Created by Pierre-Louis L'ALLORET on 25/08/2025.
//

import SwiftUI
import WeatherKit
import CoreLocation

@main
struct CirrusApp: App {
    var body: some Scene {
        WindowGroup {
            StartupView()
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var premiumManager: PremiumManager
    @EnvironmentObject var weatherViewModel: WeatherViewModel
    
    var body: some View {
        TabView {
            WeatherView()
                .tabItem {
                    Image(systemName: "cloud.sun.fill")
                    Text("Météo")
                }
            
            ComparisonView()
                .tabItem {
                    Image(systemName: "rectangle.split.3x1")
                    Text("Comparer")
                }
            
            PlannerView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Planifier")
                }
            
            if premiumManager.canUseFeature(.weatherRadar) {
                RadarView()
                    .tabItem {
                        Image(systemName: "dot.radiowaves.left.and.right") // Corrigé
                        Text("Radar")
                    }
            }
            
            ProfileView()
                .tabItem {
                    Image(systemName: "person.crop.circle")
                    Text("Profil")
                }
        }
        .onAppear {
            handleAppFirstAppearance()
        }
    }
    
    private func handleAppFirstAppearance() {
        print("👋 ContentView appeared - App ready")
        
        // Vérifications supplémentaires si nécessaire
        if weatherViewModel.currentWeather == nil && !weatherViewModel.isLoading {
            print("💡 No weather data loaded, triggering load...")
            Task {
                await weatherViewModel.loadWeatherForCurrentLocation()
            }
        }
    }
}

// MARK: - Comparison View

struct ComparisonView: View {
    @EnvironmentObject var premiumManager: PremiumManager
    @EnvironmentObject var viewModel: WeatherViewModel
    
    var body: some View {
        NavigationView {
            VStack {
                if viewModel.selectedLocationsForComparison.isEmpty {
                    ComparisonEmptyState()
                } else {
                    ComparisonContent()
                }
            }
            .navigationTitle("Comparaison")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Ajouter") {
                        viewModel.showingLocationPicker = true
                    }
                    .disabled(!premiumManager.canUseFeature(.advancedComparison) &&
                             viewModel.selectedLocationsForComparison.count >= 3)
                }
            }
            .sheet(isPresented: $viewModel.showingLocationPicker) {
                LocationPickerSheet()
            }
            .sheet(isPresented: $viewModel.showingPremiumSheet) {
                PremiumSheet()
            }
        }
    }
    
    @ViewBuilder
    private func ComparisonEmptyState() -> some View {
        VStack(spacing: 24) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("Comparateur de destinations")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Comparez la météo de plusieurs destinations pour choisir la meilleure")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Ajouter une destination") {
                viewModel.showingLocationPicker = true
            }
            .buttonStyle(.borderedProminent)
            
            if !premiumManager.isPremium {
                VStack(spacing: 8) {
                    Text("Version gratuite: jusqu'à 3 destinations")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Débloquer Premium pour 10 destinations") {
                        viewModel.showingPremiumSheet = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private func ComparisonContent() -> some View {
        VStack(spacing: 16) {
            // Selected locations
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.selectedLocationsForComparison, id: \.id) { location in
                        ComparisonLocationChip(location: location)
                    }
                    
                    // Add button
                    if premiumManager.canUseFeature(.advancedComparison) ||
                       viewModel.selectedLocationsForComparison.count < 3 {
                        Button(action: {
                            viewModel.showingLocationPicker = true
                        }) {
                            Image(systemName: "plus")
                                .foregroundColor(.blue)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.blue.opacity(0.1)))
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            // Compare button
            Button("Comparer") {
                Task {
                    await viewModel.startComparison()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedLocationsForComparison.count < 2)
            
            // Results
            if viewModel.showingComparison && !viewModel.comparisonResults.isEmpty {
                ComparisonResults()
            }
            
            Spacer()
        }
        .padding()
    }
    
    @ViewBuilder
    private func ComparisonResults() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Résultats de comparaison")
                .font(.title3)
                .fontWeight(.semibold)
            
            LazyVStack(spacing: 12) {
                ForEach(Array(viewModel.comparisonResults.enumerated()), id: \.element.id) { index, weather in
                    ComparisonResultCard(weather: weather, rank: index + 1)
                }
            }
        }
    }
}

// MARK: - Comparison Location Chip

struct ComparisonLocationChip: View {
    let location: Location
    @EnvironmentObject var viewModel: WeatherViewModel
    
    var body: some View {
        HStack(spacing: 8) {
            Text(location.name)
                .font(.subheadline)
                .lineLimit(1)
            
            Button(action: {
                viewModel.removeFromComparison(location)
            }) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Comparison Result Card

struct ComparisonResultCard: View {
    let weather: WeatherData
    let rank: Int
    @EnvironmentObject var viewModel: WeatherViewModel
    
    var body: some View {
        HStack {
            // Rank badge
            ZStack {
                Circle()
                    .fill(rankColor)
                    .frame(width: 32, height: 32)
                
                Text("\(rank)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(weather.location.name)
                    .font(.headline)
                    .fontWeight(.medium)
                
                HStack {
                    Text(weather.current.condition.emoji)
                    Text(viewModel.formatTemperature(weather.current.temperature))
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(weather.current.condition.description)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                
                if let forecast = weather.forecast.first {
                    HStack {
                        Text(viewModel.getComfortDescription(score: forecast.comfortScore))
                            .font(.caption)
                            .foregroundColor(viewModel.getComfortColor(score: forecast.comfortScore))
                        
                        Spacer()
                        
                        ComfortScoreView(score: forecast.comfortScore)
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(viewModel.formatPrecipitationChance(weather.current.humidity))
                    .font(.caption)
                    .foregroundColor(.blue)
                
                Text(viewModel.formatWindSpeed(weather.current.windSpeed))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(rank == 1 ? Color.green.opacity(0.1) : Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(rank == 1 ? Color.green : Color.clear, lineWidth: 2)
                )
        )
    }
    
    private var rankColor: Color {
        switch rank {
        case 1: return .green
        case 2: return .orange
        case 3: return .red
        default: return .gray
        }
    }
}

// MARK: - Planner View

struct PlannerView: View {
    @EnvironmentObject var premiumManager: PremiumManager
    @EnvironmentObject var viewModel: WeatherViewModel
    
    var body: some View {
        NavigationView {
            VStack {
                if !premiumManager.canUseFeature(.aiAssistant) {
                    PlannerLockedState()
                } else if viewModel.plannedTrips.isEmpty {
                    PlannerEmptyState()
                } else {
                    PlannerContent()
                }
            }
            .navigationTitle("Planificateur")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if premiumManager.canUseFeature(.aiAssistant) {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Nouveau voyage") {
                            // Create new trip
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingPremiumSheet) {
                PremiumSheet()
            }
        }
    }
    
    @ViewBuilder
    private func PlannerLockedState() -> some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.2))
                    .frame(width: 120, height: 120)
                
                VStack {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.yellow)
                    
                    Image(systemName: "calendar")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }
            }
            
            VStack(spacing: 12) {
                Text("Planificateur Premium")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Créez des itinéraires intelligents avec l'assistant IA et les prévisions étendues")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                VStack(alignment: .leading, spacing: 8) {
                    PremiumFeatureRow(icon: "brain.head.profile", text: "Assistant IA personnalisé")
                    PremiumFeatureRow(icon: "calendar", text: "Prévisions météo 30 jours")
                    PremiumFeatureRow(icon: "route", text: "Optimisation d'itinéraires")
                    PremiumFeatureRow(icon: "bell.badge", text: "Alertes météo intelligentes")
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
            }
            
            Button("Débloquer Premium") {
                viewModel.showingPremiumSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    @ViewBuilder
    private func PlannerEmptyState() -> some View {
        VStack(spacing: 24) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("Planificateur de voyage")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Créez des itinéraires optimisés avec l'assistant IA")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Créer mon premier voyage") {
                // Start trip creation
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    @ViewBuilder
    private func PlannerContent() -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.plannedTrips, id: \.id) { trip in
                    TripCard(trip: trip)
                }
            }
            .padding()
        }
    }
}

// MARK: - Premium Feature Row

struct PremiumFeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
            
            Spacer()
        }
    }
}

// MARK: - Trip Card

struct TripCard: View {
    let trip: Trip
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("\(trip.destinations.count) destinations • \(trip.duration) jours")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if trip.isActive {
                    Text("ACTIF")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
            }
            
            // Destinations preview
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(trip.destinations.prefix(3), id: \.id) { destination in
                        Text(destination.location.name)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                    }
                    
                    if trip.destinations.count > 3 {
                        Text("+\(trip.destinations.count - 3)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray5))
                            .foregroundColor(.secondary)
                            .cornerRadius(8)
                    }
                }
            }
            
            // Dates
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.secondary)
                
                Text("\(formatDate(trip.startDate)) - \(formatDate(trip.endDate))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM"
        return formatter.string(from: date)
    }
}

// MARK: - Radar View (Premium)

struct RadarView: View {
    @EnvironmentObject var premiumManager: PremiumManager
    
    var body: some View {
        NavigationView {
            VStack {
                if !premiumManager.canUseFeature(.weatherRadar) {
                    RadarLockedState()
                } else {
                    RadarContent()
                }
            }
            .navigationTitle("Radar Météo")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    @ViewBuilder
    private func RadarLockedState() -> some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 120, height: 120)
                
                VStack {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.yellow)
                    
                    Image(systemName: "dot.radiowaves.left.and.right") // Corrigé
                        .font(.system(size: 24))
                        .foregroundColor(.purple)
                }
            }
            
            VStack(spacing: 8) {
                Text("Radar Premium")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Visualisez les précipitations en temps réel avec notre radar météo avancé")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Débloquer Premium") {
                // Show premium sheet
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    @ViewBuilder
    private func RadarContent() -> some View {
        VStack {
            // Radar map would go here
            Text("Radar météo en temps réel")
                .font(.title3)
                .foregroundColor(.secondary)
            
            Text("Cette fonctionnalité nécessiterait l'intégration d'une carte interactive avec les données radar")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
    }
}

// MARK: - Profile View

struct ProfileView: View {
    @EnvironmentObject var premiumManager: PremiumManager
    @State private var showingPremiumSheet = false
    
    var body: some View {
        NavigationView {
            List {
                // Premium status section
                Section {
                    if premiumManager.isPremium {
                        PremiumStatusRow()
                    } else {
                        FreeTierRow()
                    }
                }
                
                // Settings sections
                Section("Paramètres") {
                    SettingsRow(icon: "thermometer", title: "Unités", subtitle: "Celsius, km/h")
                    SettingsRow(icon: "bell", title: "Notifications", subtitle: "Alertes météo")
                    SettingsRow(icon: "location", title: "Localisation", subtitle: "Autorisation accordée")
                }
                
                Section("À propos") {
                    SettingsRow(icon: "info.circle", title: "À propos", subtitle: "Version 1.0")
                    SettingsRow(icon: "envelope", title: "Contact", subtitle: "Support client")
                    SettingsRow(icon: "star", title: "Noter l'app", subtitle: "App Store")
                }
                
                if premiumManager.isPremium {
                    Section("Premium") {
                        SettingsRow(icon: "arrow.clockwise", title: "Restaurer achats", subtitle: nil)
                        SettingsRow(icon: "creditcard", title: "Gérer abonnement", subtitle: nil)
                    }
                }
            }
            .navigationTitle("Profil")
            .sheet(isPresented: $showingPremiumSheet) {
                PremiumSheet()
            }
        }
    }
    
    @ViewBuilder
    private func PremiumStatusRow() -> some View {
        HStack {
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "crown.fill")
                    .foregroundColor(.yellow)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Cirrus Premium")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if let expirationDate = premiumManager.subscriptionInfo.expirationDate {
                    Text("Expire le \(formatDate(expirationDate))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Accès permanent")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func FreeTierRow() -> some View {
        Button(action: {
            showingPremiumSheet = true
        }) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "crown")
                        .foregroundColor(.gray)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version gratuite")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Débloquer toutes les fonctionnalités")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("Premium")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }
            .padding(.vertical, 4)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: date)
    }
}

// MARK: - Settings Row

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    ContentView()
        .environmentObject(PremiumManager.shared)
        .environmentObject(WeatherViewModel())
}
