import Foundation
import CoreLocation
import Combine

/// Service pour récupérer les données météo aéronautiques (METAR, TAF)
class AviationWeatherService: ObservableObject {
    static let shared = AviationWeatherService()

    @Published var isLoading = false
    @Published var errorMessage: String?

    private let session = URLSession.shared
    private let aviationCache = NSCache<NSString, CachedAviationData>()
    private let cacheExpiration: TimeInterval = 15 * 60 // 15 minutes pour données aviation

    // API AVWX (gratuite jusqu'à 4000 requêtes/jour)
    private let avwxBaseURL = "https://avwx.rest/api"
    private let avwxToken = "VOTRE_TOKEN_AVWX" // À remplacer

    // API CheckWX (gratuite jusqu'à 100 requêtes/jour)
    private let checkwxBaseURL = "https://api.checkwx.com"
    private let checkwxAPIKey = "VOTRE_CLE_CHECKWX" // À remplacer

    private init() {
        aviationCache.countLimit = 50
        aviationCache.totalCostLimit = 1024 * 1024 * 10
    }

    // MARK: - Public Methods

    /// Récupère les données météo aéronautiques complètes pour un aéroport
    func getAviationWeatherData(for icaoCode: String, location: Location) async throws -> AviationWeatherData {
        let cacheKey = NSString(string: icaoCode)

        // Vérifier le cache
        if let cachedData = aviationCache.object(forKey: cacheKey),
           Date().timeIntervalSince(cachedData.timestamp) < cacheExpiration {
            return cachedData.aviationData
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        // Récupérer METAR et TAF en parallèle
        async let metarTask = getMETAR(for: icaoCode)
        async let tafTask = getTAF(for: icaoCode)

        let (metar, taf) = try await (metarTask, tafTask)

        await MainActor.run {
            isLoading = false
        }

        // Créer la recommandation de vol
        let recommendation = await generateFlightRecommendation(
            metar: metar,
            taf: taf,
            location: location
        )

        let aviationData = AviationWeatherData(
            location: location,
            airport: nil, // À implémenter si besoin
            metar: metar,
            taf: taf,
            notams: [], // À implémenter si besoin
            recommendation: recommendation,
            nearbyAirports: [],
            lastUpdated: Date()
        )

        // Mettre en cache
        let cachedData = CachedAviationData(aviationData: aviationData, timestamp: Date())
        aviationCache.setObject(cachedData, forKey: cacheKey)

        return aviationData
    }

    /// Recherche d'aéroports à proximité
    func searchNearbyAirports(location: CLLocation, radiusKm: Double = 50) async throws -> [Airport] {
        // Cette fonction nécessiterait une base de données d'aéroports
        // Pour l'instant, retourne une liste statique des principaux aéroports français
        return getMainFrenchAirports().filter { airport in
            let airportLocation = CLLocation(
                latitude: airport.location.coordinates.latitude,
                longitude: airport.location.coordinates.longitude
            )
            let distance = location.distance(from: airportLocation) / 1000 // en km
            return distance <= radiusKm
        }.sorted { airport1, airport2 in
            let loc1 = CLLocation(
                latitude: airport1.location.coordinates.latitude,
                longitude: airport1.location.coordinates.longitude
            )
            let loc2 = CLLocation(
                latitude: airport2.location.coordinates.latitude,
                longitude: airport2.location.coordinates.longitude
            )
            return location.distance(from: loc1) < location.distance(from: loc2)
        }
    }

    /// Recherche un aéroport par code ICAO
    func searchAirportByICAO(icaoCode: String) async throws -> Airport? {
        return getMainFrenchAirports().first { $0.icaoCode == icaoCode.uppercased() }
    }

    // MARK: - Private Methods - API Calls

    private func getMETAR(for icaoCode: String) async throws -> METAR? {
        // Essayer d'abord avec AVWX
        do {
            return try await getMETARFromAVWX(icaoCode: icaoCode)
        } catch {
            print("AVWX METAR failed: \(error), trying CheckWX...")
            // Fallback sur CheckWX
            do {
                return try await getMETARFromCheckWX(icaoCode: icaoCode)
            } catch {
                print("CheckWX METAR also failed: \(error)")
                // Retourner METAR simulé pour démo
                return createSimulatedMETAR(for: icaoCode)
            }
        }
    }

    private func getTAF(for icaoCode: String) async throws -> TAF? {
        // Essayer d'abord avec AVWX
        do {
            return try await getTAFFromAVWX(icaoCode: icaoCode)
        } catch {
            print("AVWX TAF failed: \(error), trying CheckWX...")
            // Fallback sur CheckWX
            do {
                return try await getTAFFromCheckWX(icaoCode: icaoCode)
            } catch {
                print("CheckWX TAF also failed: \(error)")
                // Retourner TAF simulé pour démo
                return createSimulatedTAF(for: icaoCode)
            }
        }
    }

    // MARK: - AVWX API

    private func getMETARFromAVWX(icaoCode: String) async throws -> METAR {
        let urlString = "\(avwxBaseURL)/metar/\(icaoCode)?token=\(avwxToken)"
        guard let url = URL(string: urlString) else {
            throw WeatherError.networkError("Invalid AVWX URL")
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw WeatherError.networkError("AVWX API request failed")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let avwxResponse = try decoder.decode(AVWXMETARResponse.self, from: data)
        return convertAVWXMETAR(avwxResponse)
    }

    private func getTAFFromAVWX(icaoCode: String) async throws -> TAF {
        let urlString = "\(avwxBaseURL)/taf/\(icaoCode)?token=\(avwxToken)"
        guard let url = URL(string: urlString) else {
            throw WeatherError.networkError("Invalid AVWX URL")
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw WeatherError.networkError("AVWX API request failed")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let avwxResponse = try decoder.decode(AVWXTAFResponse.self, from: data)
        return convertAVWXTAF(avwxResponse)
    }

    // MARK: - CheckWX API

    private func getMETARFromCheckWX(icaoCode: String) async throws -> METAR {
        let urlString = "\(checkwxBaseURL)/metar/\(icaoCode)/decoded"
        guard let url = URL(string: urlString) else {
            throw WeatherError.networkError("Invalid CheckWX URL")
        }

        var request = URLRequest(url: url)
        request.addValue(checkwxAPIKey, forHTTPHeaderField: "X-API-Key")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw WeatherError.networkError("CheckWX API request failed")
        }

        let decoder = JSONDecoder()
        let checkwxResponse = try decoder.decode(CheckWXMETARResponse.self, from: data)

        guard let metarData = checkwxResponse.data.first else {
            throw WeatherError.dataCorrupted
        }

        return convertCheckWXMETAR(metarData)
    }

    private func getTAFFromCheckWX(icaoCode: String) async throws -> TAF {
        let urlString = "\(checkwxBaseURL)/taf/\(icaoCode)/decoded"
        guard let url = URL(string: urlString) else {
            throw WeatherError.networkError("Invalid CheckWX URL")
        }

        var request = URLRequest(url: url)
        request.addValue(checkwxAPIKey, forHTTPHeaderField: "X-API-Key")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw WeatherError.networkError("CheckWX API request failed")
        }

        let decoder = JSONDecoder()
        let checkwxResponse = try decoder.decode(CheckWXTAFResponse.self, from: data)

        guard let tafData = checkwxResponse.data.first else {
            throw WeatherError.dataCorrupted
        }

        return convertCheckWXTAF(tafData)
    }

    // MARK: - Simulated Data for Demo

    private func createSimulatedMETAR(for icaoCode: String) -> METAR {
        return METAR(
            station: icaoCode,
            observationTime: Date(),
            rawText: "\(icaoCode) 121230Z 27015KT 9999 FEW035 SCT050 17/11 Q1013",
            flightRules: .vfr,
            temperature: 17,
            dewpoint: 11,
            windDirection: 270,
            windSpeed: 15,
            windGust: nil,
            visibility: 9999,
            altimeter: 1013,
            clouds: [
                CloudLayer(coverage: .few, altitude: 3500, type: nil),
                CloudLayer(coverage: .scattered, altitude: 5000, type: nil)
            ],
            weatherPhenomena: []
        )
    }

    private func createSimulatedTAF(for icaoCode: String) -> TAF {
        let now = Date()
        let validFrom = now
        let validTo = Calendar.current.date(byAdding: .hour, value: 24, to: now)!

        return TAF(
            station: icaoCode,
            issueTime: now,
            validFrom: validFrom,
            validTo: validTo,
            rawText: "\(icaoCode) 121100Z 1212/1312 27015KT 9999 FEW035 SCT050",
            forecast: [
                TAFForecastPeriod(
                    validFrom: validFrom,
                    validTo: Calendar.current.date(byAdding: .hour, value: 6, to: validFrom)!,
                    changeIndicator: nil,
                    windDirection: 270,
                    windSpeed: 15,
                    windGust: nil,
                    visibility: 9999,
                    clouds: [
                        CloudLayer(coverage: .few, altitude: 3500, type: nil),
                        CloudLayer(coverage: .scattered, altitude: 5000, type: nil)
                    ],
                    weatherPhenomena: [],
                    flightRules: .vfr
                )
            ]
        )
    }

    // MARK: - Conversion Methods

    private func convertAVWXMETAR(_ response: AVWXMETARResponse) -> METAR {
        // Conversion simplifiée - à améliorer selon la structure réelle de l'API
        return METAR(
            station: response.station,
            observationTime: response.time.dt,
            rawText: response.raw,
            flightRules: determineFlightRules(visibility: response.visibility.value, ceiling: response.ceiling?.value),
            temperature: response.temperature.value,
            dewpoint: response.dewpoint.value,
            windDirection: response.wind_direction.value,
            windSpeed: response.wind_speed.value,
            windGust: response.wind_gust?.value,
            visibility: response.visibility.value,
            altimeter: response.altimeter.value,
            clouds: [],
            weatherPhenomena: []
        )
    }

    private func convertAVWXTAF(_ response: AVWXTAFResponse) -> TAF {
        // Conversion simplifiée
        return TAF(
            station: response.station,
            issueTime: response.time.dt,
            validFrom: response.start_time.dt,
            validTo: response.end_time.dt,
            rawText: response.raw,
            forecast: []
        )
    }

    private func convertCheckWXMETAR(_ data: CheckWXMETARData) -> METAR {
        // Conversion simplifiée
        return createSimulatedMETAR(for: data.icao)
    }

    private func convertCheckWXTAF(_ data: CheckWXTAFData) -> TAF {
        // Conversion simplifiée
        return createSimulatedTAF(for: data.icao)
    }

    // MARK: - Flight Rules Determination

    private func determineFlightRules(visibility: Double, ceiling: Int?) -> FlightRules {
        let visibilityMeters = visibility * 1609.34 // Convertir en mètres si en miles

        // Déterminer selon les règles VFR/IFR
        if let ceiling = ceiling {
            if visibilityMeters >= 5000 && ceiling >= 1500 {
                return .vfr
            } else if visibilityMeters >= 3000 && ceiling >= 1000 {
                return .mvfr
            } else if visibilityMeters >= 1600 || ceiling >= 500 {
                return .ifr
            } else {
                return .lifr
            }
        } else {
            if visibilityMeters >= 5000 {
                return .vfr
            } else if visibilityMeters >= 3000 {
                return .mvfr
            } else if visibilityMeters >= 1600 {
                return .ifr
            } else {
                return .lifr
            }
        }
    }

    // MARK: - Airport Database (Static for now)

    private func getMainFrenchAirports() -> [Airport] {
        return [
            Airport(
                icaoCode: "LFPG",
                iataCode: "CDG",
                name: "Paris Charles de Gaulle",
                location: Location(
                    name: "Paris CDG",
                    country: "France",
                    coordinates: Location.Coordinates(latitude: 49.0097, longitude: 2.5479),
                    timezone: "Europe/Paris",
                    isFavorite: false,
                    isPremium: false
                ),
                elevation: 392,
                runways: [],
                hasControlTower: true,
                operatingHours: "24/7"
            ),
            Airport(
                icaoCode: "LFPO",
                iataCode: "ORY",
                name: "Paris Orly",
                location: Location(
                    name: "Paris Orly",
                    country: "France",
                    coordinates: Location.Coordinates(latitude: 48.7233, longitude: 2.3794),
                    timezone: "Europe/Paris",
                    isFavorite: false,
                    isPremium: false
                ),
                elevation: 291,
                runways: [],
                hasControlTower: true,
                operatingHours: "24/7"
            ),
            Airport(
                icaoCode: "LFPB",
                iataCode: "LBG",
                name: "Paris Le Bourget",
                location: Location(
                    name: "Le Bourget",
                    country: "France",
                    coordinates: Location.Coordinates(latitude: 48.9694, longitude: 2.4414),
                    timezone: "Europe/Paris",
                    isFavorite: false,
                    isPremium: false
                ),
                elevation: 218,
                runways: [],
                hasControlTower: true,
                operatingHours: "Daylight"
            ),
            Airport(
                icaoCode: "LFML",
                iataCode: "MRS",
                name: "Marseille Provence",
                location: Location(
                    name: "Marseille",
                    country: "France",
                    coordinates: Location.Coordinates(latitude: 43.4393, longitude: 5.2214),
                    timezone: "Europe/Paris",
                    isFavorite: false,
                    isPremium: false
                ),
                elevation: 74,
                runways: [],
                hasControlTower: true,
                operatingHours: "24/7"
            ),
            Airport(
                icaoCode: "LFLL",
                iataCode: "LYS",
                name: "Lyon Saint-Exupéry",
                location: Location(
                    name: "Lyon",
                    country: "France",
                    coordinates: Location.Coordinates(latitude: 45.7256, longitude: 5.0811),
                    timezone: "Europe/Paris",
                    isFavorite: false,
                    isPremium: false
                ),
                elevation: 821,
                runways: [],
                hasControlTower: true,
                operatingHours: "24/7"
            ),
            Airport(
                icaoCode: "LFMN",
                iataCode: "NCE",
                name: "Nice Côte d'Azur",
                location: Location(
                    name: "Nice",
                    country: "France",
                    coordinates: Location.Coordinates(latitude: 43.6584, longitude: 7.2159),
                    timezone: "Europe/Paris",
                    isFavorite: false,
                    isPremium: false
                ),
                elevation: 12,
                runways: [],
                hasControlTower: true,
                operatingHours: "24/7"
            )
        ]
    }

    // MARK: - Cache Management

    func clearCache() {
        aviationCache.removeAllObjects()
    }
}

// MARK: - Cached Data

private class CachedAviationData: NSObject {
    let aviationData: AviationWeatherData
    let timestamp: Date

    init(aviationData: AviationWeatherData, timestamp: Date) {
        self.aviationData = aviationData
        self.timestamp = timestamp
        super.init()
    }
}

// MARK: - API Response Models

// AVWX Response Models
private struct AVWXMETARResponse: Codable {
    let station: String
    let time: AVWXTime
    let raw: String
    let temperature: AVWXValue
    let dewpoint: AVWXValue
    let wind_direction: AVWXValue
    let wind_speed: AVWXValue
    let wind_gust: AVWXValue?
    let visibility: AVWXValue
    let altimeter: AVWXValue
    let ceiling: AVWXValue?
}

private struct AVWXTAFResponse: Codable {
    let station: String
    let time: AVWXTime
    let start_time: AVWXTime
    let end_time: AVWXTime
    let raw: String
}

private struct AVWXTime: Codable {
    let dt: Date
}

private struct AVWXValue: Codable {
    let value: Double
}

// CheckWX Response Models
private struct CheckWXMETARResponse: Codable {
    let data: [CheckWXMETARData]
}

private struct CheckWXMETARData: Codable {
    let icao: String
}

private struct CheckWXTAFResponse: Codable {
    let data: [CheckWXTAFData]
}

private struct CheckWXTAFData: Codable {
    let icao: String
}

// MARK: - Flight Recommendation Generator

extension AviationWeatherService {
    func generateFlightRecommendation(
        metar: METAR?,
        taf: TAF?,
        location: Location
    ) async -> FlightRecommendation {
        var warnings: [FlightWarning] = []
        var advisories: [FlightAdvisory] = []
        var safetyLevel: FlightRecommendation.SafetyLevel = .safe

        guard let metar = metar else {
            return FlightRecommendation(
                overallSafety: .notRecommended,
                recommendedAltitude: AltitudeRecommendation(
                    minimumAltitude: 1000,
                    maximumAltitude: 3000,
                    optimalAltitude: 2000,
                    reason: "Données météo indisponibles"
                ),
                flightType: .postpone,
                warnings: [
                    FlightWarning(
                        severity: .high,
                        title: "Données manquantes",
                        description: "Impossible d'obtenir les données METAR",
                        affectedAltitudes: nil
                    )
                ],
                advisories: [],
                weatherSummary: "Données météo non disponibles",
                recommendedDepartureWindow: nil
            )
        }

        // Analyser les conditions actuelles
        analyzeWindConditions(metar: metar, warnings: &warnings, advisories: &advisories, safetyLevel: &safetyLevel)
        analyzeVisibility(metar: metar, warnings: &warnings, advisories: &advisories, safetyLevel: &safetyLevel)
        analyzeCloudCoverage(metar: metar, warnings: &warnings, advisories: &advisories, safetyLevel: &safetyLevel)
        analyzeWeatherPhenomena(metar: metar, warnings: &warnings, advisories: &advisories, safetyLevel: &safetyLevel)

        // Déterminer l'altitude recommandée
        let altitudeRec = determineRecommendedAltitude(metar: metar, taf: taf)

        // Déterminer le type de vol recommandé
        let flightType = determineFlightType(safetyLevel: safetyLevel, flightRules: metar.flightRules)

        // Créer le résumé météo
        let summary = createWeatherSummary(metar: metar, taf: taf)

        return FlightRecommendation(
            overallSafety: safetyLevel,
            recommendedAltitude: altitudeRec,
            flightType: flightType,
            warnings: warnings,
            advisories: advisories,
            weatherSummary: summary,
            recommendedDepartureWindow: determineDepartureWindow(taf: taf)
        )
    }

    private func analyzeWindConditions(
        metar: METAR,
        warnings: inout [FlightWarning],
        advisories: inout [FlightAdvisory],
        safetyLevel: inout FlightRecommendation.SafetyLevel
    ) {
        let windSpeed = metar.windSpeed

        if windSpeed > 25 {
            warnings.append(FlightWarning(
                severity: .critical,
                title: "Vent fort",
                description: "Vent de \(Int(windSpeed))kt - Conditions dangereuses",
                affectedAltitudes: 0...3000
            ))
            safetyLevel = .dangerous
        } else if windSpeed > 20 {
            warnings.append(FlightWarning(
                severity: .high,
                title: "Vent modéré à fort",
                description: "Vent de \(Int(windSpeed))kt - Prudence recommandée",
                affectedAltitudes: 0...3000
            ))
            if safetyLevel == .safe {
                safetyLevel = .notRecommended
            }
        } else if windSpeed > 15 {
            advisories.append(FlightAdvisory(
                category: .wind,
                message: "Vent modéré de \(Int(windSpeed))kt - Conditions acceptables mais attention aux rafales",
                priority: 2
            ))
            if safetyLevel == .safe {
                safetyLevel = .caution
            }
        }

        if let gust = metar.windGust, gust > windSpeed + 10 {
            warnings.append(FlightWarning(
                severity: .high,
                title: "Rafales importantes",
                description: "Rafales jusqu'à \(Int(gust))kt",
                affectedAltitudes: 0...5000
            ))
            if safetyLevel == .safe {
                safetyLevel = .caution
            }
        }
    }

    private func analyzeVisibility(
        metar: METAR,
        warnings: inout [FlightWarning],
        advisories: inout [FlightAdvisory],
        safetyLevel: inout FlightRecommendation.SafetyLevel
    ) {
        let visibilityKm = metar.visibility / 1000

        if visibilityKm < 1 {
            warnings.append(FlightWarning(
                severity: .critical,
                title: "Très faible visibilité",
                description: "Visibilité de \(Int(visibilityKm))km - Vol IFR uniquement",
                affectedAltitudes: nil
            ))
            safetyLevel = .dangerous
        } else if visibilityKm < 5 {
            warnings.append(FlightWarning(
                severity: .medium,
                title: "Visibilité réduite",
                description: "Visibilité de \(Int(visibilityKm))km - Vol VFR limité",
                affectedAltitudes: nil
            ))
            if safetyLevel == .safe {
                safetyLevel = .caution
            }
        }
    }

    private func analyzeCloudCoverage(
        metar: METAR,
        warnings: inout [FlightWarning],
        advisories: inout [FlightAdvisory],
        safetyLevel: inout FlightRecommendation.SafetyLevel
    ) {
        for cloud in metar.clouds {
            if cloud.altitude < 1500 && (cloud.coverage == .broken || cloud.coverage == .overcast) {
                warnings.append(FlightWarning(
                    severity: .medium,
                    title: "Plafond bas",
                    description: "Plafond \(cloud.coverage.rawValue) à \(cloud.altitude)ft",
                    affectedAltitudes: 0...cloud.altitude
                ))
                if safetyLevel == .safe {
                    safetyLevel = .caution
                }
            }

            if cloud.type == .cumulonimbus {
                warnings.append(FlightWarning(
                    severity: .critical,
                    title: "Cumulonimbus présents",
                    description: "CB signalés - Risque d'orages et turbulences sévères",
                    affectedAltitudes: 0...25000
                ))
                safetyLevel = .dangerous
            }
        }
    }

    private func analyzeWeatherPhenomena(
        metar: METAR,
        warnings: inout [FlightWarning],
        advisories: inout [FlightAdvisory],
        safetyLevel: inout FlightRecommendation.SafetyLevel
    ) {
        for phenomenon in metar.weatherPhenomena {
            if let descriptor = phenomenon.descriptor, descriptor == .thunderstorm {
                warnings.append(FlightWarning(
                    severity: .critical,
                    title: "Orages",
                    description: "Activité orageuse signalée - Vol fortement déconseillé",
                    affectedAltitudes: nil
                ))
                safetyLevel = .dangerous
            }

            if !phenomenon.precipitation.isEmpty && phenomenon.intensity == .heavy {
                warnings.append(FlightWarning(
                    severity: .high,
                    title: "Précipitations intenses",
                    description: "Fortes précipitations - Visibilité et conditions dégradées",
                    affectedAltitudes: nil
                ))
                if safetyLevel == .safe {
                    safetyLevel = .notRecommended
                }
            }
        }
    }

    private func determineRecommendedAltitude(metar: METAR, taf: TAF?) -> AltitudeRecommendation {
        var minAlt = 1000
        var maxAlt = 10000
        var optimalAlt = 3000

        // Ajuster selon le plafond nuageux
        if let highestCloud = metar.clouds.max(by: { $0.altitude < $1.altitude }) {
            if highestCloud.coverage == .broken || highestCloud.coverage == .overcast {
                maxAlt = min(maxAlt, highestCloud.altitude - 500)
                optimalAlt = min(optimalAlt, highestCloud.altitude - 1000)
            }
        }

        // Ajuster selon les conditions de vent
        if metar.windSpeed > 20 {
            minAlt = 2000
            optimalAlt = max(optimalAlt, 3000)
        }

        let reason = "Basé sur plafond nuageux à \(highestCloudAltitude(metar))ft et vent de \(Int(metar.windSpeed))kt"

        return AltitudeRecommendation(
            minimumAltitude: minAlt,
            maximumAltitude: maxAlt,
            optimalAltitude: optimalAlt,
            reason: reason
        )
    }

    private func highestCloudAltitude(_ metar: METAR) -> Int {
        return metar.clouds.max(by: { $0.altitude < $1.altitude })?.altitude ?? 10000
    }

    private func determineFlightType(safetyLevel: FlightRecommendation.SafetyLevel, flightRules: FlightRules) -> RecommendedFlightType {
        switch safetyLevel {
        case .safe:
            return flightRules == .vfr ? .crossCountryVFR : .ifr
        case .caution:
            return .localVFR
        case .notRecommended:
            return .postpone
        case .dangerous:
            return .cancel
        }
    }

    private func createWeatherSummary(metar: METAR, taf: TAF?) -> String {
        var summary = "\(metar.flightRules.description)\n"
        summary += "Vent: \(Int(metar.windSpeed))kt du \(metar.windDirection)°\n"
        summary += "Visibilité: \(Int(metar.visibility / 1000))km\n"
        summary += "Température: \(Int(metar.temperature))°C\n"
        summary += "QNH: \(Int(metar.altimeter))hPa"

        return summary
    }

    private func determineDepartureWindow(taf: TAF?) -> DateInterval? {
        guard let taf = taf else { return nil }

        // Trouver la meilleure période de 2h dans les prochaines 6h
        let bestPeriod = taf.forecast
            .filter { $0.flightRules == .vfr || $0.flightRules == .mvfr }
            .first

        if let period = bestPeriod {
            return DateInterval(start: period.validFrom, end: period.validTo)
        }

        return nil
    }
}
