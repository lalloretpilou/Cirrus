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

            AviationView()
                .tabItem {
                    Image(systemName: "airplane")
                    Text("Aviation")
                }

            ComparisonView()
                .tabItem {
                    Image(systemName: "rectangle.split.3x1")
                    Text("Comparer")
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

// MARK: - Planner View



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
