//
//  IcingView.swift
//  Cirrus
//
//  Vue 3D interactive du risque de givrage
//

import SwiftUI

struct IcingView: View {
    @StateObject private var icingService = IcingService.shared
    @StateObject private var aviationService = AviationWeatherService.shared
    @StateObject private var locationManager = LocationManager()

    @State private var selectedLayer: IcingLayer?
    @State private var show3DView = true
    @State private var showRecommendations = true

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.1, blue: 0.2), Color(red: 0.1, green: 0.15, blue: 0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if icingService.isLoading {
                    LoadingView(message: "Analyse des conditions de givrage...")
                } else if let error = icingService.error {
                    ErrorView(error: error)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // En-tête
                            IcingHeader()
                                .padding(.horizontal)

                            // Visualisation 3D ou liste
                            if show3DView {
                                Icing3DVisualization(
                                    layers: icingService.icingLayers,
                                    selectedLayer: $selectedLayer
                                )
                                .frame(height: 400)
                                .padding(.horizontal)
                            } else {
                                IcingLayersListView(
                                    layers: icingService.icingLayers,
                                    selectedLayer: $selectedLayer
                                )
                                .padding(.horizontal)
                            }

                            // Toggle 3D/Liste
                            ViewToggleButton(show3D: $show3DView)
                                .padding(.horizontal)

                            // Détails de la couche sélectionnée
                            if let layer = selectedLayer {
                                LayerDetailCard(layer: layer)
                                    .padding(.horizontal)
                            }

                            // Plage d'altitude sûre
                            if let safeRange = icingService.getSafeAltitudeRange(icingLayers: icingService.icingLayers) {
                                SafeAltitudeCard(min: safeRange.min, max: safeRange.max)
                                    .padding(.horizontal)
                            }

                            // Prévisions de givrage
                            if !icingService.icingForecast.isEmpty {
                                ForecastSection(forecasts: icingService.icingForecast)
                                    .padding(.horizontal)
                            }

                            // Recommandations
                            if showRecommendations {
                                let recommendations = icingService.getFlightRecommendations(icingLayers: icingService.icingLayers)
                                if !recommendations.isEmpty {
                                    RecommendationsSection(recommendations: recommendations)
                                        .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Carte de Givrage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: refreshData) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.white)
                    }
                }
            }
            .task {
                await loadIcingData()
            }
        }
    }

    private func loadIcingData() async {
        if let location = locationManager.currentLocation {
            await icingService.analyzeIcingConditions(
                for: location.coordinate,
                metar: aviationService.currentMETAR,
                windsAloft: aviationService.windsAloft
            )
        }
    }

    private func refreshData() {
        Task {
            await loadIcingData()
        }
    }
}

// MARK: - Icing Header

struct IcingHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🧊 Analyse du Givrage")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text("Risque de givrage par altitude - Crucial pour la sécurité")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - 3D Visualization

struct Icing3DVisualization: View {
    let layers: [IcingLayer]
    @Binding var selectedLayer: IcingLayer?

    var body: some View {
        VStack(spacing: 0) {
            // Axes et échelle
            HStack {
                // Axe Y (altitude)
                VStack(spacing: 0) {
                    ForEach(layers.sorted(by: { $0.altitude > $1.altitude }), id: \.id) { layer in
                        Text("\(layer.altitude/1000)k ft")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                            .frame(height: 40)
                    }
                }
                .frame(width: 50)

                // Visualisation des couches
                VStack(spacing: 2) {
                    ForEach(layers.sorted(by: { $0.altitude > $1.altitude }), id: \.id) { layer in
                        Button(action: {
                            selectedLayer = layer
                        }) {
                            IcingLayerBar(
                                layer: layer,
                                isSelected: selectedLayer?.id == layer.id
                            )
                        }
                    }
                }
            }
            .padding()
            .background(Color.black.opacity(0.3))
            .cornerRadius(12)

            // Légende
            IcingRiskLegend()
                .padding(.top, 12)
        }
    }
}

struct IcingLayerBar: View {
    let layer: IcingLayer
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Barre de couleur (risque)
            Rectangle()
                .fill(riskColor(layer.icingRisk))
                .frame(height: 35)
                .cornerRadius(6)
                .overlay(
                    HStack {
                        Text(layer.icingRisk.emoji)
                            .font(.title3)

                        Text(layer.icingRisk.description)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)

                        Spacer()

                        // Indicateurs
                        HStack(spacing: 8) {
                            // Température
                            HStack(spacing: 2) {
                                Image(systemName: "thermometer")
                                    .font(.caption)
                                Text("\(Int(layer.temperature))°C")
                                    .font(.caption)
                            }
                            .foregroundColor(.white.opacity(0.9))

                            // Type de givrage
                            if let type = layer.icingType {
                                Text(type.emoji)
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.white : Color.clear, lineWidth: 3)
                )
        }
    }

    private func riskColor(_ risk: IcingRisk) -> Color {
        switch risk {
        case .none: return Color.green.opacity(0.8)
        case .light: return Color.yellow.opacity(0.8)
        case .moderate: return Color.orange.opacity(0.8)
        case .severe: return Color.red.opacity(0.8)
        case .extreme: return Color.purple.opacity(0.8)
        }
    }
}

// MARK: - List View

struct IcingLayersListView: View {
    let layers: [IcingLayer]
    @Binding var selectedLayer: IcingLayer?

    var body: some View {
        VStack(spacing: 12) {
            ForEach(layers.sorted(by: { $0.altitude > $1.altitude }), id: \.id) { layer in
                Button(action: {
                    selectedLayer = layer
                }) {
                    IcingLayerCard(
                        layer: layer,
                        isSelected: selectedLayer?.id == layer.id
                    )
                }
            }
        }
    }
}

struct IcingLayerCard: View {
    let layer: IcingLayer
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // En-tête
            HStack {
                Text("\(layer.altitude) ft MSL")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Text(layer.icingRisk.emoji)
                    .font(.title2)

                Text(layer.icingRisk.description)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(riskColor(layer.icingRisk))
                    .cornerRadius(8)
            }

            Divider()
                .background(Color.white.opacity(0.3))

            // Détails
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Température")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    Text("\(Int(layer.temperature))°C")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Humidité")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    Text("\(Int(layer.humidity))%")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Nuages")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    Text(layer.cloudCoverage.description)
                        .font(.subheadline)
                        .foregroundColor(.white)
                }

                if let type = layer.icingType {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Type")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        HStack(spacing: 4) {
                            Text(type.emoji)
                            Text(type.description)
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }

    private func riskColor(_ risk: IcingRisk) -> Color {
        switch risk {
        case .none: return .green
        case .light: return .yellow
        case .moderate: return .orange
        case .severe: return .red
        case .extreme: return .purple
        }
    }
}

// MARK: - Layer Detail Card

struct LayerDetailCard: View {
    let layer: IcingLayer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Détails de la couche \(layer.altitude) ft")
                .font(.headline)
                .foregroundColor(.white)

            if let type = layer.icingType {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(type.emoji)
                            .font(.title2)
                        Text(type.description)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }

                    Text(type.details)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding()
                .background(Color.blue.opacity(0.2))
                .cornerRadius(8)
            }

            // Conditions atmosphériques
            VStack(alignment: .leading, spacing: 8) {
                Text("Conditions atmosphériques")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                HStack(spacing: 20) {
                    ConditionItem(
                        icon: "thermometer",
                        label: "Température",
                        value: "\(Int(layer.temperature))°C"
                    )

                    ConditionItem(
                        icon: "humidity",
                        label: "Humidité",
                        value: "\(Int(layer.humidity))%"
                    )

                    ConditionItem(
                        icon: "cloud",
                        label: "Nuages",
                        value: layer.cloudCoverage.description
                    )
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.15))
        .cornerRadius(12)
    }
}

struct ConditionItem: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(.blue)
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

// MARK: - Safe Altitude Card

struct SafeAltitudeCard: View {
    let min: Int
    let max: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 4) {
                Text("Altitude sûre recommandée")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text("\(min) - \(max) ft MSL")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.green)

                Text("Aucun givrage ou givrage léger dans cette plage")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()
        }
        .padding()
        .background(Color.green.opacity(0.2))
        .cornerRadius(12)
    }
}

// MARK: - Forecast Section

struct ForecastSection: View {
    let forecasts: [IcingForecastPeriod]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prévisions de givrage")
                .font(.headline)
                .foregroundColor(.white)

            ForEach(forecasts) { forecast in
                ForecastCard(forecast: forecast)
            }
        }
    }
}

struct ForecastCard: View {
    let forecast: IcingForecastPeriod

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(forecast.label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text("\(forecast.bottomAltitude) - \(forecast.topAltitude) ft")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack {
                    Text(forecast.risk.emoji)
                    Text(forecast.risk.description)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }

                Text("Confiance: \(forecast.confidence)%")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Recommendations Section

struct RecommendationsSection: View {
    let recommendations: [IcingRecommendation]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommandations")
                .font(.headline)
                .foregroundColor(.white)

            ForEach(recommendations.sorted(by: { $0.priority.sortOrder < $1.priority.sortOrder })) { recommendation in
                RecommendationCard(recommendation: recommendation)
            }
        }
    }
}

struct RecommendationCard: View {
    let recommendation: IcingRecommendation

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: recommendation.type.icon)
                .font(.title2)
                .foregroundColor(typeColor(recommendation.type))
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(recommendation.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(recommendation.message)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }

            Spacer()
        }
        .padding()
        .background(typeColor(recommendation.type).opacity(0.2))
        .cornerRadius(12)
    }

    private func typeColor(_ type: IcingRecommendation.RecommendationType) -> Color {
        switch type {
        case .safe: return .green
        case .caution: return .yellow
        case .danger: return .red
        case .equipment: return .blue
        case .flightRules: return .orange
        }
    }
}

// MARK: - View Toggle Button

struct ViewToggleButton: View {
    @Binding var show3D: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { show3D = true }) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                    Text("Vue 3D")
                }
                .font(.subheadline)
                .fontWeight(show3D ? .semibold : .regular)
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(show3D ? Color.blue : Color.white.opacity(0.2))
                .cornerRadius(8)
            }

            Button(action: { show3D = false }) {
                HStack {
                    Image(systemName: "list.bullet")
                    Text("Vue Liste")
                }
                .font(.subheadline)
                .fontWeight(!show3D ? .semibold : .regular)
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(!show3D ? Color.blue : Color.white.opacity(0.2))
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - Icing Risk Legend

struct IcingRiskLegend: View {
    let risks: [(risk: IcingRisk, color: Color)] = [
        (.none, .green),
        (.light, .yellow),
        (.moderate, .orange),
        (.severe, .red),
        (.extreme, .purple)
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(risks, id: \.risk) { item in
                VStack(spacing: 4) {
                    Text(item.risk.emoji)
                        .font(.caption)

                    Rectangle()
                        .fill(item.color.opacity(0.8))
                        .frame(width: 40, height: 8)
                        .cornerRadius(2)

                    Text(item.risk.description)
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
    }
}

// MARK: - Helper Views

struct LoadingView: View {
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text(message)
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

struct ErrorView: View {
    let error: IcingError

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

#Preview {
    IcingView()
}
