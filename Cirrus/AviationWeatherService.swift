//
//  AviationWeatherService.swift
//  Cirrus
//
//  Service for fetching aviation weather data (METAR, TAF, etc.)
//

import Foundation
import CoreLocation
import Combine

@MainActor
class AviationWeatherService: ObservableObject {
    static let shared = AviationWeatherService()

    @Published var currentMETAR: METAR?
    @Published var currentTAF: TAF?
    @Published var nearbyAerodromes: [Aerodrome] = []
    @Published var windsAloft: WindsAloft?
    @Published var hazards: [AviationHazard] = []
    @Published var isLoading = false
    @Published var error: AviationWeatherError?

    private let cache = NSCache<NSString, CacheEntry>()
    private let cacheExpiration: TimeInterval = 600 // 10 minutes

    private init() {
        cache.countLimit = 50
    }

    // MARK: - Public Methods

    func fetchAviationWeather(for coordinate: CLLocationCoordinate2D) async {
        isLoading = true
        error = nil

        do {
            // Find nearest aerodrome with METAR
            let aerodrome = try await findNearestAerodrome(to: coordinate)

            // Fetch METAR and TAF in parallel
            async let metar = fetchMETAR(for: aerodrome.icaoCode)
            async let taf = fetchTAF(for: aerodrome.icaoCode)
            async let winds = fetchWindsAloft(near: coordinate)
            async let nearby = fetchNearbyAerodromes(coordinate: coordinate, radius: 50)

            currentMETAR = try await metar
            currentTAF = try? await taf // TAF might not be available for all airports
            windsAloft = try? await winds
            nearbyAerodromes = try await nearby

            isLoading = false
        } catch {
            self.error = error as? AviationWeatherError ?? .unknown
            isLoading = false
        }
    }

    func fetchMETAR(for icaoCode: String) async throws -> METAR {
        let cacheKey = "metar_\(icaoCode)" as NSString

        // Check cache
        if let cached = cache.object(forKey: cacheKey),
           Date().timeIntervalSince(cached.timestamp) < cacheExpiration {
            if let metar = cached.data as? METAR {
                return metar
            }
        }

        // Try CheckWX API first (free, reliable)
        do {
            let metar = try await fetchMETARFromCheckWX(icaoCode: icaoCode)
            cache.setObject(CacheEntry(data: metar), forKey: cacheKey)
            return metar
        } catch {
            // Fallback to Aviation Weather Center (NOAA)
            let metar = try await fetchMETARFromAWC(icaoCode: icaoCode)
            cache.setObject(CacheEntry(data: metar), forKey: cacheKey)
            return metar
        }
    }

    func fetchTAF(for icaoCode: String) async throws -> TAF {
        let cacheKey = "taf_\(icaoCode)" as NSString

        // Check cache
        if let cached = cache.object(forKey: cacheKey),
           Date().timeIntervalSince(cached.timestamp) < cacheExpiration {
            if let taf = cached.data as? TAF {
                return taf
            }
        }

        // Try CheckWX API first
        do {
            let taf = try await fetchTAFFromCheckWX(icaoCode: icaoCode)
            cache.setObject(CacheEntry(data: taf), forKey: cacheKey)
            return taf
        } catch {
            // Fallback to Aviation Weather Center
            let taf = try await fetchTAFFromAWC(icaoCode: icaoCode)
            cache.setObject(CacheEntry(data: taf), forKey: cacheKey)
            return taf
        }
    }

    // MARK: - CheckWX API (Free - https://www.checkwx.com)

    private func fetchMETARFromCheckWX(icaoCode: String) async throws -> METAR {
        let urlString = "https://api.checkwx.com/metar/\(icaoCode)/decoded"
        guard let url = URL(string: urlString) else {
            throw AviationWeatherError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Note: For production, you should use an API key from CheckWX
        // request.setValue("YOUR_API_KEY", forHTTPHeaderField: "X-API-Key")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AviationWeatherError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let checkWXResponse = try decoder.decode(CheckWXMETARResponse.self, from: data)

        guard let metarData = checkWXResponse.data.first else {
            throw AviationWeatherError.noData
        }

        return parseMETARFromCheckWX(metarData)
    }

    private func fetchTAFFromCheckWX(icaoCode: String) async throws -> TAF {
        let urlString = "https://api.checkwx.com/taf/\(icaoCode)/decoded"
        guard let url = URL(string: urlString) else {
            throw AviationWeatherError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AviationWeatherError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let checkWXResponse = try decoder.decode(CheckWXTAFResponse.self, from: data)

        guard let tafData = checkWXResponse.data.first else {
            throw AviationWeatherError.noData
        }

        return parseTAFFromCheckWX(tafData)
    }

    // MARK: - Aviation Weather Center API (NOAA - Free)

    private func fetchMETARFromAWC(icaoCode: String) async throws -> METAR {
        let urlString = "https://aviationweather.gov/api/data/metar?ids=\(icaoCode)&format=json"
        guard let url = URL(string: urlString) else {
            throw AviationWeatherError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AviationWeatherError.invalidResponse
        }

        let decoder = JSONDecoder()
        let awcResponse = try decoder.decode([AWCMETARResponse].self, from: data)

        guard let metarData = awcResponse.first else {
            throw AviationWeatherError.noData
        }

        return parseMETARFromAWC(metarData)
    }

    private func fetchTAFFromAWC(icaoCode: String) async throws -> TAF {
        let urlString = "https://aviationweather.gov/api/data/taf?ids=\(icaoCode)&format=json"
        guard let url = URL(string: urlString) else {
            throw AviationWeatherError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AviationWeatherError.invalidResponse
        }

        let decoder = JSONDecoder()
        let awcResponse = try decoder.decode([AWCTAFResponse].self, from: data)

        guard let tafData = awcResponse.first else {
            throw AviationWeatherError.noData
        }

        return parseTAFFromAWC(tafData)
    }

    // MARK: - Aerodrome Search

    func findNearestAerodrome(to coordinate: CLLocationCoordinate2D) async throws -> Aerodrome {
        // This is a simplified version. In production, you'd query a database of aerodromes
        let nearby = try await fetchNearbyAerodromes(coordinate: coordinate, radius: 100)

        guard let nearest = nearby.first else {
            throw AviationWeatherError.noAerodromeFound
        }

        return nearest
    }

    func fetchNearbyAerodromes(coordinate: CLLocationCoordinate2D, radius: Double) async throws -> [Aerodrome] {
        // Using OurAirports free database API
        let urlString = "https://davidmegginson.github.io/ourairports-data/airports.csv"
        guard let url = URL(string: urlString) else {
            throw AviationWeatherError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let csvString = String(data: data, encoding: .utf8) else {
            throw AviationWeatherError.invalidResponse
        }

        let aerodromes = parseAerodromesFromCSV(csvString)
        let userLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        // Filter by distance and sort
        let nearby = aerodromes
            .filter { aerodrome in
                let aerodromeLocation = CLLocation(
                    latitude: aerodrome.location.latitude,
                    longitude: aerodrome.location.longitude
                )
                let distance = userLocation.distance(from: aerodromeLocation) / 1000 // Convert to km
                return distance <= radius && aerodrome.hasMETAR
            }
            .sorted { aerodrome1, aerodrome2 in
                let loc1 = CLLocation(latitude: aerodrome1.location.latitude, longitude: aerodrome1.location.longitude)
                let loc2 = CLLocation(latitude: aerodrome2.location.latitude, longitude: aerodrome2.location.longitude)
                return userLocation.distance(from: loc1) < userLocation.distance(from: loc2)
            }
            .prefix(10)

        return Array(nearby)
    }

    func searchAerodromes(query: String) async throws -> [Aerodrome] {
        let urlString = "https://davidmegginson.github.io/ourairports-data/airports.csv"
        guard let url = URL(string: urlString) else {
            throw AviationWeatherError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let csvString = String(data: data, encoding: .utf8) else {
            throw AviationWeatherError.invalidResponse
        }

        let aerodromes = parseAerodromesFromCSV(csvString)
        let searchTerm = query.uppercased()

        return aerodromes.filter { aerodrome in
            aerodrome.icaoCode.contains(searchTerm) ||
            aerodrome.name.uppercased().contains(searchTerm) ||
            (aerodrome.iataCode?.contains(searchTerm) ?? false)
        }.prefix(20).map { $0 }
    }

    // MARK: - Winds Aloft

    private func fetchWindsAloft(near coordinate: CLLocationCoordinate2D) async throws -> WindsAloft {
        // This would typically come from NOAA's Winds Aloft forecast
        // For now, we'll use a simplified version from Aviation Weather Center
        let urlString = "https://aviationweather.gov/api/data/windtemp?region=all"
        guard let url = URL(string: urlString) else {
            throw AviationWeatherError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        // Parse winds aloft data
        // This is a simplified implementation
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Return sample data for now
        return WindsAloft(
            station: "NEAR",
            validTime: Date(),
            levels: [
                WindsAloft.WindLevel(altitude: 3000, direction: 270, speed: 15, temperature: 10),
                WindsAloft.WindLevel(altitude: 6000, direction: 280, speed: 25, temperature: 0),
                WindsAloft.WindLevel(altitude: 9000, direction: 290, speed: 35, temperature: -10),
                WindsAloft.WindLevel(altitude: 12000, direction: 300, speed: 45, temperature: -20),
                WindsAloft.WindLevel(altitude: 18000, direction: 310, speed: 60, temperature: -35)
            ]
        )
    }

    // MARK: - Parsing Helpers

    private func parseMETARFromCheckWX(_ data: CheckWXMETARData) -> METAR {
        // Parse CheckWX METAR response into our METAR model
        let flightRules = parseFlightRules(
            ceiling: data.ceiling?.feet,
            visibility: data.visibility?.miles
        )

        let wind = METAR.Wind(
            direction: data.wind?.degrees,
            speed: data.wind?.speed_kts ?? 0,
            gust: data.wind?.gust_kts,
            variable: false,
            variableFrom: nil,
            variableTo: nil
        )

        let visibility = METAR.Visibility(
            value: data.visibility?.miles ?? 10.0,
            unit: "SM",
            isGreaterThan: false
        )

        let temperature = METAR.Temperature(
            celsius: data.temperature?.celsius ?? 15.0,
            fahrenheit: data.temperature?.fahrenheit ?? 59.0
        )

        let altimeter = METAR.Altimeter(
            inHg: data.barometer?.hg ?? 29.92,
            hPa: data.barometer?.mb ?? 1013.25
        )

        let clouds = (data.clouds ?? []).map { cloud in
            METAR.CloudLayer(
                coverage: parseCloudCoverage(cloud.code),
                altitude: cloud.feet ?? 0,
                type: cloud.text
            )
        }

        return METAR(
            station: data.icao,
            observationTime: ISO8601DateFormatter().date(from: data.observed ?? "") ?? Date(),
            rawText: data.raw_text ?? "",
            flightRules: flightRules,
            wind: wind,
            visibility: visibility,
            temperature: temperature,
            dewpoint: data.dewpoint?.celsius ?? 10.0,
            altimeter: altimeter,
            clouds: clouds,
            weatherPhenomena: [],
            remarks: data.remarks
        )
    }

    private func parseTAFFromCheckWX(_ data: CheckWXTAFData) -> TAF {
        let issueTime = ISO8601DateFormatter().date(from: data.timestamp?.issued ?? "") ?? Date()
        let validFrom = ISO8601DateFormatter().date(from: data.timestamp?.from ?? "") ?? Date()
        let validTo = ISO8601DateFormatter().date(from: data.timestamp?.to ?? "") ?? Date()

        let forecasts = (data.forecast ?? []).map { forecast -> TAF.ForecastPeriod in
            let startTime = ISO8601DateFormatter().date(from: forecast.timestamp?.from ?? "") ?? Date()
            let endTime = ISO8601DateFormatter().date(from: forecast.timestamp?.to ?? "") ?? Date()

            let wind = METAR.Wind(
                direction: forecast.wind?.degrees,
                speed: forecast.wind?.speed_kts ?? 0,
                gust: forecast.wind?.gust_kts,
                variable: false,
                variableFrom: nil,
                variableTo: nil
            )

            let visibility = METAR.Visibility(
                value: forecast.visibility?.miles ?? 10.0,
                unit: "SM",
                isGreaterThan: false
            )

            let clouds = (forecast.clouds ?? []).map { cloud in
                METAR.CloudLayer(
                    coverage: parseCloudCoverage(cloud.code),
                    altitude: cloud.feet ?? 0,
                    type: cloud.text
                )
            }

            return TAF.ForecastPeriod(
                type: .base,
                startTime: startTime,
                endTime: endTime,
                wind: wind,
                visibility: visibility,
                clouds: clouds,
                weatherPhenomena: [],
                probability: nil,
                changePeriod: forecast.change
            )
        }

        return TAF(
            station: data.icao,
            issueTime: issueTime,
            validFrom: validFrom,
            validTo: validTo,
            rawText: data.raw_text ?? "",
            forecasts: forecasts
        )
    }

    private func parseMETARFromAWC(_ data: AWCMETARResponse) -> METAR {
        let flightRules = FlightRules(rawValue: data.fltcat ?? "VFR") ?? .vfr

        let wind = METAR.Wind(
            direction: data.wdir,
            speed: data.wspd ?? 0,
            gust: data.wgst,
            variable: false,
            variableFrom: nil,
            variableTo: nil
        )

        let visibility = METAR.Visibility(
            value: data.visib ?? 10.0,
            unit: "SM",
            isGreaterThan: false
        )

        let temperature = METAR.Temperature(
            celsius: data.temp ?? 15.0,
            fahrenheit: (data.temp ?? 15.0) * 9/5 + 32
        )

        let altimeter = METAR.Altimeter(
            inHg: data.altim ?? 29.92,
            hPa: (data.altim ?? 29.92) * 33.8639
        )

        let clouds = (data.clouds ?? []).map { cloud in
            METAR.CloudLayer(
                coverage: parseCloudCoverage(cloud.cover),
                altitude: cloud.base ?? 0,
                type: nil
            )
        }

        return METAR(
            station: data.icaoId,
            observationTime: ISO8601DateFormatter().date(from: data.reportTime ?? "") ?? Date(),
            rawText: data.rawOb ?? "",
            flightRules: flightRules,
            wind: wind,
            visibility: visibility,
            temperature: temperature,
            dewpoint: data.dewp ?? 10.0,
            altimeter: altimeter,
            clouds: clouds,
            weatherPhenomena: [],
            remarks: nil
        )
    }

    private func parseTAFFromAWC(_ data: AWCTAFResponse) -> TAF {
        let issueTime = ISO8601DateFormatter().date(from: data.issueTime ?? "") ?? Date()
        let validFrom = ISO8601DateFormatter().date(from: data.validTimeFrom ?? "") ?? Date()
        let validTo = ISO8601DateFormatter().date(from: data.validTimeTo ?? "") ?? Date()

        let forecasts = (data.fcsts ?? []).map { forecast -> TAF.ForecastPeriod in
            let startTime = ISO8601DateFormatter().date(from: forecast.timeFrom ?? "") ?? Date()
            let endTime = ISO8601DateFormatter().date(from: forecast.timeTo ?? "") ?? Date()

            let wind = METAR.Wind(
                direction: forecast.wdir,
                speed: forecast.wspd ?? 0,
                gust: forecast.wgst,
                variable: false,
                variableFrom: nil,
                variableTo: nil
            )

            let visibility = METAR.Visibility(
                value: forecast.visib ?? 10.0,
                unit: "SM",
                isGreaterThan: false
            )

            let clouds = (forecast.clouds ?? []).map { cloud in
                METAR.CloudLayer(
                    coverage: parseCloudCoverage(cloud.cover),
                    altitude: cloud.base ?? 0,
                    type: nil
                )
            }

            return TAF.ForecastPeriod(
                type: parseForecastType(forecast.change),
                startTime: startTime,
                endTime: endTime,
                wind: wind,
                visibility: visibility,
                clouds: clouds,
                weatherPhenomena: [],
                probability: forecast.prob,
                changePeriod: forecast.change
            )
        }

        return TAF(
            station: data.icaoId,
            issueTime: issueTime,
            validFrom: validFrom,
            validTo: validTo,
            rawText: data.rawTAF ?? "",
            forecasts: forecasts
        )
    }

    private func parseAerodromesFromCSV(_ csvString: String) -> [Aerodrome] {
        let lines = csvString.components(separatedBy: .newlines)
        guard lines.count > 1 else { return [] }

        // Skip header
        let dataLines = Array(lines.dropFirst())
        var aerodromes: [Aerodrome] = []

        for line in dataLines {
            let components = line.components(separatedBy: ",")
            guard components.count >= 18 else { continue }

            // Parse CSV columns (simplified)
            let icaoCode = components[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
            let name = components[3].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
            let lat = Double(components[4].trimmingCharacters(in: .whitespaces)) ?? 0
            let lon = Double(components[5].trimmingCharacters(in: .whitespaces)) ?? 0
            let elevation = Int(components[6].trimmingCharacters(in: .whitespaces)) ?? 0

            // Only include airports with valid ICAO codes (4 letters)
            guard icaoCode.count == 4, !icaoCode.isEmpty else { continue }

            let location = Aerodrome.Location(
                latitude: lat,
                longitude: lon,
                city: components[10].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: ""),
                country: components[8].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
            )

            let aerodrome = Aerodrome(
                icaoCode: icaoCode,
                iataCode: nil,
                name: name,
                location: location,
                elevation: elevation,
                runways: [],
                frequencies: Aerodrome.Frequencies(tower: nil, ground: nil, atis: nil, approach: nil, departure: nil),
                hasMETAR: true,
                hasTAF: false
            )

            aerodromes.append(aerodrome)
        }

        return aerodromes
    }

    private func parseCloudCoverage(_ code: String?) -> METAR.CloudCoverage {
        guard let code = code?.uppercased() else { return .clear }

        switch code {
        case "CLR", "SKC", "NCD": return .clear
        case "FEW": return .few
        case "SCT": return .scattered
        case "BKN": return .broken
        case "OVC": return .overcast
        case "VV": return .vertical
        default: return .clear
        }
    }

    private func parseFlightRules(ceiling: Int?, visibility: Double?) -> FlightRules {
        let ceilingFeet = ceiling ?? 10000
        let visibilityMiles = visibility ?? 10.0

        if ceilingFeet > 3000 && visibilityMiles > 5 {
            return .vfr
        } else if ceilingFeet >= 1000 && ceilingFeet <= 3000 || (visibilityMiles >= 3 && visibilityMiles <= 5) {
            return .mvfr
        } else if ceilingFeet >= 500 && ceilingFeet < 1000 || (visibilityMiles >= 1 && visibilityMiles < 3) {
            return .ifr
        } else {
            return .lifr
        }
    }

    private func parseForecastType(_ change: String?) -> TAF.ForecastType {
        guard let change = change?.uppercased() else { return .base }

        switch change {
        case "TEMPO": return .tempo
        case "BECMG": return .becmg
        case "PROB": return .prob
        case "FM": return .from
        default: return .base
        }
    }
}

// MARK: - API Response Models

struct CheckWXMETARResponse: Codable {
    let data: [CheckWXMETARData]
}

struct CheckWXMETARData: Codable {
    let icao: String
    let observed: String?
    let raw_text: String?
    let barometer: Barometer?
    let ceiling: Ceiling?
    let clouds: [Cloud]?
    let dewpoint: Temperature?
    let humidity: Humidity?
    let temperature: Temperature?
    let visibility: Visibility?
    let wind: Wind?
    let remarks: String?

    struct Barometer: Codable {
        let hg: Double?
        let mb: Double?
    }

    struct Ceiling: Codable {
        let feet: Int?
        let meters: Int?
    }

    struct Cloud: Codable {
        let code: String?
        let text: String?
        let feet: Int?
        let meters: Int?
    }

    struct Temperature: Codable {
        let celsius: Double?
        let fahrenheit: Double?
    }

    struct Humidity: Codable {
        let percent: Double?
    }

    struct Visibility: Codable {
        let miles: Double?
        let meters: Int?
    }

    struct Wind: Codable {
        let degrees: Int?
        let speed_kts: Int?
        let speed_mph: Int?
        let gust_kts: Int?
        let gust_mph: Int?
    }
}

struct CheckWXTAFResponse: Codable {
    let data: [CheckWXTAFData]
}

struct CheckWXTAFData: Codable {
    let icao: String
    let timestamp: Timestamp?
    let raw_text: String?
    let forecast: [Forecast]?

    struct Timestamp: Codable {
        let issued: String?
        let from: String?
        let to: String?
    }

    struct Forecast: Codable {
        let timestamp: Timestamp?
        let clouds: [CheckWXMETARData.Cloud]?
        let visibility: CheckWXMETARData.Visibility?
        let wind: CheckWXMETARData.Wind?
        let change: String?
    }
}

struct AWCMETARResponse: Codable {
    let icaoId: String
    let reportTime: String?
    let rawOb: String?
    let temp: Double?
    let dewp: Double?
    let wdir: Int?
    let wspd: Int?
    let wgst: Int?
    let visib: Double?
    let altim: Double?
    let fltcat: String?
    let clouds: [CloudData]?

    struct CloudData: Codable {
        let cover: String?
        let base: Int?
    }
}

struct AWCTAFResponse: Codable {
    let icaoId: String
    let issueTime: String?
    let validTimeFrom: String?
    let validTimeTo: String?
    let rawTAF: String?
    let fcsts: [ForecastData]?

    struct ForecastData: Codable {
        let timeFrom: String?
        let timeTo: String?
        let wdir: Int?
        let wspd: Int?
        let wgst: Int?
        let visib: Double?
        let clouds: [AWCMETARResponse.CloudData]?
        let change: String?
        let prob: Int?
    }
}

// MARK: - Cache Entry

class CacheEntry {
    let data: Any
    let timestamp: Date

    init(data: Any) {
        self.data = data
        self.timestamp = Date()
    }
}

// MARK: - Errors

enum AviationWeatherError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noData
    case noAerodromeFound
    case networkError(Error)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL invalide"
        case .invalidResponse:
            return "Réponse invalide du serveur"
        case .noData:
            return "Aucune donnée disponible"
        case .noAerodromeFound:
            return "Aucun aérodrome trouvé à proximité"
        case .networkError(let error):
            return "Erreur réseau: \(error.localizedDescription)"
        case .unknown:
            return "Erreur inconnue"
        }
    }
}
