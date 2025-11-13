//
//  RadarWeatherService.swift
//  Cirrus
//
//  Radar météo en temps réel avec animation des précipitations
//

import Foundation
import MapKit
import Combine

@MainActor
class RadarWeatherService: ObservableObject {
    static let shared = RadarWeatherService()

    @Published var radarFrames: [RadarFrame] = []
    @Published var isLoading = false
    @Published var error: RadarError?
    @Published var currentFrameIndex = 0
    @Published var isAnimating = false

    // Configuration
    private let radarAPIBase = "https://api.rainviewer.com/public/weather-maps.json"
    private let tileSize = 256
    private let maxFrames = 12 // Dernières 2 heures (frames toutes les 10 min)

    private var animationTimer: Timer?

    private init() {}

    // MARK: - Public Methods

    func fetchRadarData() async {
        isLoading = true
        error = nil

        do {
            let radarData = try await fetchRainViewerData()
            self.radarFrames = radarData.frames
            isLoading = false
        } catch {
            self.error = .networkError(error.localizedDescription)
            isLoading = false
        }
    }

    func startAnimation() {
        guard !radarFrames.isEmpty else { return }

        isAnimating = true
        currentFrameIndex = 0

        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor in
                self.currentFrameIndex = (self.currentFrameIndex + 1) % self.radarFrames.count
            }
        }
    }

    func stopAnimation() {
        isAnimating = false
        animationTimer?.invalidate()
        animationTimer = nil
    }

    func getCurrentFrame() -> RadarFrame? {
        guard !radarFrames.isEmpty, currentFrameIndex < radarFrames.count else {
            return nil
        }
        return radarFrames[currentFrameIndex]
    }

    // MARK: - RainViewer API

    private func fetchRainViewerData() async throws -> RadarData {
        guard let url = URL(string: radarAPIBase) else {
            throw RadarError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw RadarError.invalidResponse
        }

        let decoder = JSONDecoder()
        let rainViewerResponse = try decoder.decode(RainViewerResponse.self, from: data)

        // Convertir les données RainViewer en nos RadarFrames
        let frames = rainViewerResponse.radar.past.suffix(maxFrames).map { past in
            RadarFrame(
                timestamp: Date(timeIntervalSince1970: TimeInterval(past.time)),
                path: past.path,
                coverageURL: "https://tilecache.rainviewer.com\(past.path)/256/{z}/{x}/{y}/2/1_1.png"
            )
        }

        return RadarData(
            host: rainViewerResponse.host,
            frames: frames,
            generatedAt: Date(timeIntervalSince1970: TimeInterval(rainViewerResponse.generated))
        )
    }

    // MARK: - Analyse des Orages

    func detectThunderstorms(in region: MKCoordinateRegion) async -> [ThunderstormCell] {
        // Analyse des zones de forte intensité dans la région
        var cells: [ThunderstormCell] = []

        // Simulation basée sur les données radar (à affiner avec vraies données)
        // Dans une vraie implémentation, on analyserait l'intensité des pixels radar

        return cells
    }

    func getRadarIntensityColor(value: Double) -> String {
        // Échelle de couleur radar standard
        switch value {
        case 0..<0.1: return "clear"
        case 0.1..<1: return "lightBlue"      // Pluie très légère
        case 1..<2: return "blue"             // Pluie légère
        case 2..<5: return "green"            // Pluie modérée
        case 5..<10: return "yellow"          // Pluie forte
        case 10..<20: return "orange"         // Très forte
        case 20..<50: return "red"            // Intense
        default: return "purple"              // Extrême (grêle)
        }
    }
}

// MARK: - Models

struct RadarData {
    let host: String
    let frames: [RadarFrame]
    let generatedAt: Date
}

struct RadarFrame: Identifiable {
    let id = UUID()
    let timestamp: Date
    let path: String
    let coverageURL: String

    var timeAgo: String {
        let interval = Date().timeIntervalSince(timestamp)
        let minutes = Int(interval / 60)

        if minutes < 1 {
            return "Maintenant"
        } else if minutes == 1 {
            return "Il y a 1 minute"
        } else if minutes < 60 {
            return "Il y a \(minutes) minutes"
        } else {
            let hours = minutes / 60
            return "Il y a \(hours)h"
        }
    }
}

struct ThunderstormCell: Identifiable {
    let id = UUID()
    let location: CLLocationCoordinate2D
    let intensity: Intensity
    let topHeight: Int          // Feet
    let movement: Movement
    let lightningActivity: Bool

    enum Intensity {
        case moderate
        case strong
        case severe

        var description: String {
            switch self {
            case .moderate: return "Modéré"
            case .strong: return "Fort"
            case .severe: return "Sévère"
            }
        }

        var color: String {
            switch self {
            case .moderate: return "yellow"
            case .strong: return "orange"
            case .severe: return "red"
            }
        }
    }

    struct Movement {
        let direction: Int      // Degrees
        let speed: Double       // Knots

        var description: String {
            return "\(direction)° à \(Int(speed)) kt"
        }
    }
}

// MARK: - RainViewer API Response

struct RainViewerResponse: Codable {
    let version: String
    let generated: Int
    let host: String
    let radar: RadarInfo

    struct RadarInfo: Codable {
        let past: [RadarTimestamp]
        let nowcast: [RadarTimestamp]

        struct RadarTimestamp: Codable {
            let time: Int
            let path: String
        }
    }
}

// MARK: - Lightning Data Service

class LightningDataService {
    static let shared = LightningDataService()

    private init() {}

    // Récupération des données de foudre (API Blitzortung.org est gratuite)
    func fetchLightningStrikes(in region: MKCoordinateRegion, last minutes: Int = 30) async throws -> [LightningStrike] {
        // API Blitzortung.org pour les impacts de foudre
        // Format: https://data.blitzortung.org/Data/Protected/last_strikes.php

        // Pour l'instant, retourner un tableau vide
        // Dans une vraie implémentation, on interrogerait l'API
        return []
    }
}

struct LightningStrike: Identifiable {
    let id = UUID()
    let location: CLLocationCoordinate2D
    let timestamp: Date
    let intensity: Double       // kA (kiloampères)

    var timeAgo: String {
        let interval = Date().timeIntervalSince(timestamp)
        let seconds = Int(interval)

        if seconds < 60 {
            return "\(seconds)s"
        } else {
            let minutes = seconds / 60
            return "\(minutes)m"
        }
    }
}

// MARK: - Radar Overlay Tile Provider

class RadarTileOverlay: MKTileOverlay {
    let radarPath: String

    init(radarPath: String) {
        self.radarPath = radarPath
        super.init(urlTemplate: "https://tilecache.rainviewer.com\(radarPath)/256/{z}/{x}/{y}/2/1_1.png")
        self.canReplaceMapContent = false
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        let urlString = "https://tilecache.rainviewer.com\(radarPath)/256/\(path.z)/\(path.x)/\(path.y)/2/1_1.png"
        return URL(string: urlString)!
    }
}

// MARK: - Errors

enum RadarError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noData
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL invalide"
        case .invalidResponse:
            return "Réponse invalide du serveur"
        case .noData:
            return "Aucune donnée radar disponible"
        case .networkError(let message):
            return "Erreur réseau: \(message)"
        }
    }
}

// MARK: - Precipitation Intensity Analysis

extension RadarWeatherService {
    /// Analyse l'intensité des précipitations pour un point donné
    func getPrecipitationIntensity(at coordinate: CLLocationCoordinate2D) async -> PrecipitationIntensity {
        // Dans une vraie implémentation, on analyserait les pixels radar
        // Pour l'instant, retourner une valeur par défaut
        return .none
    }

    enum PrecipitationIntensity {
        case none
        case veryLight      // < 0.1 mm/h
        case light          // 0.1 - 2.5 mm/h
        case moderate       // 2.5 - 10 mm/h
        case heavy          // 10 - 50 mm/h
        case veryHeavy      // > 50 mm/h

        var description: String {
            switch self {
            case .none: return "Pas de précipitations"
            case .veryLight: return "Très légères"
            case .light: return "Légères"
            case .moderate: return "Modérées"
            case .heavy: return "Fortes"
            case .veryHeavy: return "Très fortes"
            }
        }

        var color: String {
            switch self {
            case .none: return "clear"
            case .veryLight: return "lightBlue"
            case .light: return "blue"
            case .moderate: return "green"
            case .heavy: return "yellow"
            case .veryHeavy: return "red"
            }
        }

        var emoji: String {
            switch self {
            case .none: return "☀️"
            case .veryLight: return "🌦️"
            case .light: return "🌧️"
            case .moderate: return "🌧️"
            case .heavy: return "⛈️"
            case .veryHeavy: return "⛈️"
            }
        }
    }
}
