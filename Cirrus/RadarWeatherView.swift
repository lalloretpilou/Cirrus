//
//  RadarWeatherView.swift
//  Cirrus
//
//  Vue interactive du radar météo avec animation
//

import SwiftUI
import MapKit

struct RadarWeatherView: View {
    @StateObject private var radarService = RadarWeatherService.shared
    @StateObject private var locationManager = LocationManager()

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 46.603354, longitude: 1.888334), // Centre France
        span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
    )

    @State private var mapType: MKMapType = .standard
    @State private var showLegend = true
    @State private var radarOpacity = 0.7

    var body: some View {
        ZStack {
            // Carte avec radar overlay
            RadarMapView(
                region: $region,
                radarService: radarService,
                mapType: mapType,
                radarOpacity: radarOpacity
            )
            .ignoresSafeArea(edges: .all)

            // Contrôles overlay
            VStack {
                // En-tête
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Radar Météo")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        if let frame = radarService.getCurrentFrame() {
                            Text(frame.timeAgo)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(12)

                    Spacer()

                    // Boutons de contrôle
                    VStack(spacing: 12) {
                        // Centrer sur position
                        Button(action: centerOnLocation) {
                            Image(systemName: "location.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                        }

                        // Changer type de carte
                        Button(action: toggleMapType) {
                            Image(systemName: mapType == .standard ? "map" : "map.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                        }

                        // Toggle légende
                        Button(action: { showLegend.toggle() }) {
                            Image(systemName: showLegend ? "info.circle.fill" : "info.circle")
                                .font(.title3)
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                }
                .padding(.top, 50)

                Spacer()

                // Légende des intensités
                if showLegend {
                    IntensityLegend()
                        .padding(.horizontal)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Contrôles d'animation
                AnimationControls(radarService: radarService)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(16)
                    .padding()

                // Slider d'opacité
                OpacityControl(opacity: $radarOpacity)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            // Overlay de chargement
            if radarService.isLoading {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)

                        Text("Chargement du radar...")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                    .padding(24)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(16)
                }
            }
        }
        .task {
            await loadRadarData()
            centerOnLocation()
        }
    }

    private func loadRadarData() async {
        await radarService.fetchRadarData()
    }

    private func centerOnLocation() {
        if let location = locationManager.currentLocation {
            region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 5)
            )
        }
    }

    private func toggleMapType() {
        mapType = mapType == .standard ? .hybrid : .standard
    }
}

// MARK: - Radar Map View

struct RadarMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let radarService: RadarWeatherService
    let mapType: MKMapType
    let radarOpacity: Double

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = mapType
        mapView.showsUserLocation = true
        mapView.setRegion(region, animated: false)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.mapType = mapType

        // Mettre à jour la région si changée
        if mapView.region.center.latitude != region.center.latitude ||
           mapView.region.center.longitude != region.center.longitude {
            mapView.setRegion(region, animated: true)
        }

        // Mettre à jour l'overlay radar
        context.coordinator.updateRadarOverlay(on: mapView, with: radarService, opacity: radarOpacity)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: RadarMapView
        var currentOverlay: MKTileOverlay?

        init(_ parent: RadarMapView) {
            self.parent = parent
        }

        func updateRadarOverlay(on mapView: MKMapView, with service: RadarWeatherService, opacity: Double) {
            // Supprimer l'ancien overlay
            if let overlay = currentOverlay {
                mapView.removeOverlay(overlay)
            }

            // Ajouter le nouveau si disponible
            if let frame = service.getCurrentFrame() {
                let overlay = RadarTileOverlay(radarPath: frame.path)
                overlay.canReplaceMapContent = false
                mapView.addOverlay(overlay, level: .aboveLabels)
                currentOverlay = overlay
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
                renderer.alpha = CGFloat(parent.radarOpacity)
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.region = mapView.region
        }
    }
}

// MARK: - Animation Controls

struct AnimationControls: View {
    @ObservedObject var radarService: RadarWeatherService

    var body: some View {
        VStack(spacing: 12) {
            // Timeline avec frames
            if !radarService.radarFrames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(radarService.radarFrames.enumerated()), id: \.element.id) { index, frame in
                            FrameIndicator(
                                frame: frame,
                                isSelected: index == radarService.currentFrameIndex,
                                onTap: {
                                    radarService.currentFrameIndex = index
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(height: 60)
            }

            // Contrôles lecture
            HStack(spacing: 24) {
                // Bouton lecture/pause
                Button(action: toggleAnimation) {
                    Image(systemName: radarService.isAnimating ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }

                // Bouton précédent
                Button(action: previousFrame) {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                .disabled(radarService.radarFrames.isEmpty)

                // Bouton suivant
                Button(action: nextFrame) {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                .disabled(radarService.radarFrames.isEmpty)

                // Bouton refresh
                Button(action: refreshRadar) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
        }
    }

    private func toggleAnimation() {
        if radarService.isAnimating {
            radarService.stopAnimation()
        } else {
            radarService.startAnimation()
        }
    }

    private func previousFrame() {
        radarService.stopAnimation()
        if radarService.currentFrameIndex > 0 {
            radarService.currentFrameIndex -= 1
        } else {
            radarService.currentFrameIndex = radarService.radarFrames.count - 1
        }
    }

    private func nextFrame() {
        radarService.stopAnimation()
        if radarService.currentFrameIndex < radarService.radarFrames.count - 1 {
            radarService.currentFrameIndex += 1
        } else {
            radarService.currentFrameIndex = 0
        }
    }

    private func refreshRadar() {
        Task {
            await radarService.fetchRadarData()
        }
    }
}

// MARK: - Frame Indicator

struct FrameIndicator: View {
    let frame: RadarFrame
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                // Point indicateur
                Circle()
                    .fill(isSelected ? Color.blue : Color.white.opacity(0.5))
                    .frame(width: 8, height: 8)

                // Timestamp
                Text(frame.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white : .white.opacity(0.7))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(isSelected ? Color.blue.opacity(0.3) : Color.clear)
            .cornerRadius(8)
        }
    }
}

// MARK: - Opacity Control

struct OpacityControl: View {
    @Binding var opacity: Double

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "drop")
                .foregroundColor(.white.opacity(0.6))

            Slider(value: $opacity, in: 0.3...1.0)
                .tint(.blue)

            Text("\(Int(opacity * 100))%")
                .font(.caption)
                .foregroundColor(.white)
                .frame(width: 40)
        }
        .padding()
        .background(Color.black.opacity(0.5))
        .cornerRadius(12)
    }
}

// MARK: - Intensity Legend

struct IntensityLegend: View {
    let intensities: [(color: Color, label: String)] = [
        (.clear, "Rien"),
        (Color(red: 0.6, green: 0.8, blue: 1.0), "Très léger"),
        (.blue, "Léger"),
        (.green, "Modéré"),
        (.yellow, "Fort"),
        (.orange, "Très fort"),
        (.red, "Intense"),
        (.purple, "Extrême")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Intensité des précipitations")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            HStack(spacing: 4) {
                ForEach(intensities.filter { $0.color != .clear }, id: \.label) { intensity in
                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(intensity.color)
                            .frame(width: 30, height: 12)
                            .cornerRadius(2)

                        Text(intensity.label)
                            .font(.system(size: 8))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
    }
}

// MARK: - Thunderstorm Alert Card

struct ThunderstormAlertCard: View {
    let cell: ThunderstormCell

    var body: some View {
        HStack(spacing: 12) {
            // Icône
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 50, height: 50)

                Image(systemName: "cloud.bolt.fill")
                    .font(.title2)
                    .foregroundColor(.red)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("⚠️ Orage")
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    Text(cell.intensity.description)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(intensityColor(cell.intensity))
                        .cornerRadius(4)
                }

                Text("Sommet: \(cell.topHeight) ft")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))

                Text("Déplacement: \(cell.movement.description)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))

                if cell.lightningActivity {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                        Text("Activité électrique")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
    }

    private func intensityColor(_ intensity: ThunderstormCell.Intensity) -> Color {
        switch intensity {
        case .moderate: return .yellow
        case .strong: return .orange
        case .severe: return .red
        }
    }
}

#Preview {
    RadarWeatherView()
}
