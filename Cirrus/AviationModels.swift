//
//  AviationModels.swift
//  Cirrus
//
//  Aviation weather models for professional pilot use
//

import Foundation
import CoreLocation

// MARK: - METAR (Aviation Routine Weather Report)
struct METAR: Codable, Identifiable {
    let id = UUID()
    let station: String           // ICAO code (e.g., "LFPG")
    let observationTime: Date
    let rawText: String           // Raw METAR text
    let flightRules: FlightRules
    let wind: Wind
    let visibility: Visibility
    let temperature: Temperature
    let dewpoint: Double          // °C
    let altimeter: Altimeter
    let clouds: [CloudLayer]
    let weatherPhenomena: [WeatherPhenomenon]
    let remarks: String?

    enum CodingKeys: String, CodingKey {
        case station, observationTime, rawText, flightRules
        case wind, visibility, temperature, dewpoint, altimeter
        case clouds, weatherPhenomena, remarks
    }

    struct Wind: Codable {
        let direction: Int?       // Degrees (nil if variable)
        let speed: Int            // Knots
        let gust: Int?            // Knots
        let variable: Bool
        let variableFrom: Int?    // Degrees
        let variableTo: Int?      // Degrees
    }

    struct Visibility: Codable {
        let value: Double         // Statute miles or meters
        let unit: String          // "SM" or "M"
        let isGreaterThan: Bool   // For "P6SM" (greater than 6SM)
    }

    struct Temperature: Codable {
        let celsius: Double
        let fahrenheit: Double
    }

    struct Altimeter: Codable {
        let inHg: Double          // Inches of Mercury
        let hPa: Double           // Hectopascals (QNH)
    }

    struct CloudLayer: Codable, Identifiable {
        let id = UUID()
        let coverage: CloudCoverage
        let altitude: Int         // Feet AGL
        let type: String?         // CB, TCU, etc.

        enum CodingKeys: String, CodingKey {
            case coverage, altitude, type
        }
    }

    enum CloudCoverage: String, Codable {
        case clear = "CLR"
        case few = "FEW"           // 1-2 oktas
        case scattered = "SCT"     // 3-4 oktas
        case broken = "BKN"        // 5-7 oktas
        case overcast = "OVC"      // 8 oktas
        case vertical = "VV"       // Vertical visibility (obscured)

        var description: String {
            switch self {
            case .clear: return "Ciel clair"
            case .few: return "Quelques nuages (1-2/8)"
            case .scattered: return "Nuages épars (3-4/8)"
            case .broken: return "Nuages fragmentés (5-7/8)"
            case .overcast: return "Couvert (8/8)"
            case .vertical: return "Visibilité verticale"
            }
        }
    }
}

// MARK: - TAF (Terminal Aerodrome Forecast)
struct TAF: Codable, Identifiable {
    let id = UUID()
    let station: String
    let issueTime: Date
    let validFrom: Date
    let validTo: Date
    let rawText: String
    let forecasts: [ForecastPeriod]

    enum CodingKeys: String, CodingKey {
        case station, issueTime, validFrom, validTo, rawText, forecasts
    }

    struct ForecastPeriod: Codable, Identifiable {
        let id = UUID()
        let type: ForecastType
        let startTime: Date
        let endTime: Date
        let wind: METAR.Wind
        let visibility: METAR.Visibility
        let clouds: [METAR.CloudLayer]
        let weatherPhenomena: [WeatherPhenomenon]
        let probability: Int?     // Percentage (for PROB forecasts)
        let changePeriod: String? // TEMPO, BECMG, etc.

        enum CodingKeys: String, CodingKey {
            case type, startTime, endTime, wind, visibility
            case clouds, weatherPhenomena, probability, changePeriod
        }
    }

    enum ForecastType: String, Codable {
        case base = "BASE"
        case tempo = "TEMPO"       // Temporary fluctuations
        case becmg = "BECMG"       // Becoming
        case prob = "PROB"         // Probability
        case from = "FM"           // From (permanent change)
    }
}

// MARK: - Weather Phenomena
struct WeatherPhenomenon: Codable, Identifiable {
    let id = UUID()
    let intensity: Intensity
    let descriptor: Descriptor?
    let precipitation: [PrecipitationType]
    let obscuration: [ObscurationType]
    let other: [OtherType]

    enum CodingKeys: String, CodingKey {
        case intensity, descriptor, precipitation, obscuration, other
    }

    enum Intensity: String, Codable {
        case light = "-"
        case moderate = ""
        case heavy = "+"
        case vicinity = "VC"

        var description: String {
            switch self {
            case .light: return "Léger"
            case .moderate: return "Modéré"
            case .heavy: return "Fort"
            case .vicinity: return "À proximité"
            }
        }
    }

    enum Descriptor: String, Codable {
        case shallow = "MI"
        case patches = "BC"
        case partial = "PR"
        case drifting = "DR"
        case blowing = "BL"
        case showers = "SH"
        case thunderstorm = "TS"
        case freezing = "FZ"

        var description: String {
            switch self {
            case .shallow: return "Peu épais"
            case .patches: return "Bancs"
            case .partial: return "Partiel"
            case .drifting: return "Chasse"
            case .blowing: return "Soufflé"
            case .showers: return "Averses"
            case .thunderstorm: return "Orage"
            case .freezing: return "Givrant"
            }
        }
    }

    enum PrecipitationType: String, Codable {
        case drizzle = "DZ"
        case rain = "RA"
        case snow = "SN"
        case snowGrains = "SG"
        case iceCrystals = "IC"
        case icePellets = "PL"
        case hail = "GR"
        case snowPellets = "GS"
        case unknown = "UP"

        var emoji: String {
            switch self {
            case .drizzle: return "🌧️"
            case .rain: return "🌧️"
            case .snow: return "❄️"
            case .snowGrains: return "❄️"
            case .iceCrystals: return "🧊"
            case .icePellets: return "🧊"
            case .hail: return "🧊"
            case .snowPellets: return "❄️"
            case .unknown: return "💧"
            }
        }
    }

    enum ObscurationType: String, Codable {
        case mist = "BR"
        case fog = "FG"
        case smoke = "FU"
        case volcanic = "VA"
        case dust = "DU"
        case sand = "SA"
        case haze = "HZ"

        var emoji: String {
            switch self {
            case .mist, .fog: return "🌫️"
            case .smoke: return "💨"
            case .volcanic: return "🌋"
            case .dust, .sand: return "💨"
            case .haze: return "🌫️"
            }
        }
    }

    enum OtherType: String, Codable {
        case squalls = "SQ"
        case funnel = "FC"
        case sandstorm = "SS"
        case duststorm = "DS"

        var emoji: String {
            switch self {
            case .squalls: return "💨"
            case .funnel: return "🌪️"
            case .sandstorm, .duststorm: return "💨"
            }
        }
    }
}

// MARK: - Flight Rules
enum FlightRules: String, Codable {
    case vfr = "VFR"      // Visual Flight Rules: Ceiling > 3000ft, Visibility > 5SM
    case mvfr = "MVFR"    // Marginal VFR: Ceiling 1000-3000ft or Visibility 3-5SM
    case ifr = "IFR"      // Instrument Flight Rules: Ceiling 500-1000ft or Visibility 1-3SM
    case lifr = "LIFR"    // Low IFR: Ceiling < 500ft or Visibility < 1SM

    var color: String {
        switch self {
        case .vfr: return "green"
        case .mvfr: return "blue"
        case .ifr: return "red"
        case .lifr: return "magenta"
        }
    }

    var description: String {
        switch self {
        case .vfr: return "VFR - Conditions visuelles"
        case .mvfr: return "MVFR - Conditions visuelles marginales"
        case .ifr: return "IFR - Conditions aux instruments"
        case .lifr: return "LIFR - Conditions aux instruments basses"
        }
    }

    var emoji: String {
        switch self {
        case .vfr: return "✅"
        case .mvfr: return "⚠️"
        case .ifr: return "⛔"
        case .lifr: return "🚫"
        }
    }
}

// MARK: - Winds Aloft
struct WindsAloft: Codable {
    let station: String
    let validTime: Date
    let levels: [WindLevel]

    struct WindLevel: Codable, Identifiable {
        let id = UUID()
        let altitude: Int         // Feet MSL
        let direction: Int?       // Degrees (nil if calm or light)
        let speed: Int            // Knots
        let temperature: Int      // °C

        enum CodingKeys: String, CodingKey {
            case altitude, direction, speed, temperature
        }
    }
}

// MARK: - Airport/Aerodrome
struct Aerodrome: Codable, Identifiable {
    let id = UUID()
    let icaoCode: String
    let iataCode: String?
    let name: String
    let location: Location
    let elevation: Int            // Feet MSL
    let runways: [Runway]
    let frequencies: Frequencies
    let hasMETAR: Bool
    let hasTAF: Bool

    enum CodingKeys: String, CodingKey {
        case icaoCode, iataCode, name, location, elevation
        case runways, frequencies, hasMETAR, hasTAF
    }

    struct Location: Codable {
        let latitude: Double
        let longitude: Double
        let city: String
        let country: String

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    struct Runway: Codable, Identifiable {
        let id = UUID()
        let name: String          // e.g., "09L/27R"
        let length: Int           // Feet
        let width: Int            // Feet
        let surface: String       // ASPH, CONC, GRVL, etc.
        let lighting: Bool

        enum CodingKeys: String, CodingKey {
            case name, length, width, surface, lighting
        }
    }

    struct Frequencies: Codable {
        let tower: Double?        // MHz
        let ground: Double?       // MHz
        let atis: Double?         // MHz
        let approach: Double?     // MHz
        let departure: Double?    // MHz
    }
}

// MARK: - Aviation Hazards
struct AviationHazard: Codable, Identifiable {
    let id = UUID()
    let type: HazardType
    let severity: Severity
    let area: GeographicArea
    let validFrom: Date
    let validTo: Date
    let description: String

    enum CodingKeys: String, CodingKey {
        case type, severity, area, validFrom, validTo, description
    }

    enum HazardType: String, Codable {
        case turbulence = "TURB"
        case icing = "ICE"
        case thunderstorm = "TS"
        case mountainWave = "MTW"
        case lowLevelWindShear = "LLWS"
        case strongSurfaceWind = "WIND"
        case volcanic = "VA"
        case sandstorm = "SS"

        var emoji: String {
            switch self {
            case .turbulence: return "〰️"
            case .icing: return "🧊"
            case .thunderstorm: return "⛈️"
            case .mountainWave: return "🌊"
            case .lowLevelWindShear: return "💨"
            case .strongSurfaceWind: return "🌬️"
            case .volcanic: return "🌋"
            case .sandstorm: return "💨"
            }
        }

        var description: String {
            switch self {
            case .turbulence: return "Turbulence"
            case .icing: return "Givrage"
            case .thunderstorm: return "Orage"
            case .mountainWave: return "Onde orographique"
            case .lowLevelWindShear: return "Cisaillement bas niveau"
            case .strongSurfaceWind: return "Vent fort en surface"
            case .volcanic: return "Cendres volcaniques"
            case .sandstorm: return "Tempête de sable"
            }
        }
    }

    enum Severity: String, Codable {
        case light = "LIGHT"
        case moderate = "MOD"
        case severe = "SEV"

        var color: String {
            switch self {
            case .light: return "yellow"
            case .moderate: return "orange"
            case .severe: return "red"
            }
        }
    }

    struct GeographicArea: Codable {
        let bottomAltitude: Int   // Feet MSL
        let topAltitude: Int      // Feet MSL
        let coordinates: [CLLocationCoordinate2D]

        enum CodingKeys: String, CodingKey {
            case bottomAltitude, topAltitude
            case latitudes, longitudes
        }

        init(bottomAltitude: Int, topAltitude: Int, coordinates: [CLLocationCoordinate2D]) {
            self.bottomAltitude = bottomAltitude
            self.topAltitude = topAltitude
            self.coordinates = coordinates
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            bottomAltitude = try container.decode(Int.self, forKey: .bottomAltitude)
            topAltitude = try container.decode(Int.self, forKey: .topAltitude)
            let latitudes = try container.decode([Double].self, forKey: .latitudes)
            let longitudes = try container.decode([Double].self, forKey: .longitudes)
            coordinates = zip(latitudes, longitudes).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(bottomAltitude, forKey: .bottomAltitude)
            try container.encode(topAltitude, forKey: .topAltitude)
            try container.encode(coordinates.map { $0.latitude }, forKey: .latitudes)
            try container.encode(coordinates.map { $0.longitude }, forKey: .longitudes)
        }
    }
}

// MARK: - Flight Recommendation
struct FlightRecommendation: Identifiable {
    let id = UUID()
    let recommendedAltitude: AltitudeRange
    let flightType: RecommendedFlightType
    let optimalDepartureWindow: DateInterval?
    let conditions: Conditions
    let warnings: [Warning]
    let favorableFactors: [String]

    struct AltitudeRange {
        let minimum: Int          // Feet MSL
        let optimal: Int          // Feet MSL
        let maximum: Int          // Feet MSL
        let reason: String
    }

    enum RecommendedFlightType {
        case vfrRecommended
        case vfrCaution
        case ifrOnly
        case notRecommended

        var emoji: String {
            switch self {
            case .vfrRecommended: return "✈️"
            case .vfrCaution: return "⚠️"
            case .ifrOnly: return "🛩️"
            case .notRecommended: return "⛔"
            }
        }

        var description: String {
            switch self {
            case .vfrRecommended: return "Vol VFR recommandé"
            case .vfrCaution: return "Vol VFR avec prudence"
            case .ifrOnly: return "Vol IFR uniquement"
            case .notRecommended: return "Vol non recommandé"
            }
        }
    }

    struct Conditions {
        let ceiling: Int?         // Feet AGL
        let visibility: Double    // Statute miles
        let windSpeed: Int        // Knots
        let gustSpeed: Int?       // Knots
        let turbulenceLevel: String
        let icingLevel: String
        let flightRules: FlightRules
    }

    struct Warning {
        let type: WarningType
        let message: String
        let severity: AviationHazard.Severity

        enum WarningType {
            case wind
            case visibility
            case ceiling
            case turbulence
            case icing
            case thunderstorm
            case crosswind
            case tailwind
            case other

            var emoji: String {
                switch self {
                case .wind: return "🌬️"
                case .visibility: return "🌫️"
                case .ceiling: return "☁️"
                case .turbulence: return "〰️"
                case .icing: return "🧊"
                case .thunderstorm: return "⛈️"
                case .crosswind: return "↔️"
                case .tailwind: return "↓"
                case .other: return "⚠️"
                }
            }
        }
    }
}

// MARK: - Density Altitude Calculation
struct DensityAltitude {
    let pressureAltitude: Int     // Feet
    let densityAltitude: Int      // Feet
    let temperature: Double       // °C
    let dewpoint: Double          // °C
    let altimeter: Double         // inHg
    let relativeHumidity: Double  // Percentage
    let performanceImpact: PerformanceImpact

    enum PerformanceImpact {
        case excellent      // DA < 1000ft
        case good          // DA 1000-3000ft
        case fair          // DA 3000-5000ft
        case poor          // DA 5000-8000ft
        case critical      // DA > 8000ft

        var description: String {
            switch self {
            case .excellent: return "Excellentes performances"
            case .good: return "Bonnes performances"
            case .fair: return "Performances moyennes"
            case .poor: return "Performances réduites"
            case .critical: return "Performances critiques - Attention !"
            }
        }

        var emoji: String {
            switch self {
            case .excellent: return "🟢"
            case .good: return "🟡"
            case .fair: return "🟠"
            case .poor: return "🔴"
            case .critical: return "⛔"
            }
        }
    }
}

// MARK: - Wind Components
struct WindComponents {
    let headwind: Double          // Knots (positive = headwind, negative = tailwind)
    let crosswind: Double         // Knots (absolute value)
    let crosswindDirection: CrosswindDirection
    let effectiveWindSpeed: Double // Knots
    let windDirection: Int        // Degrees
    let runwayHeading: Int        // Degrees

    enum CrosswindDirection {
        case left
        case right
        case none

        var description: String {
            switch self {
            case .left: return "Gauche"
            case .right: return "Droite"
            case .none: return "Aucun"
            }
        }
    }

    var headwindDescription: String {
        if headwind > 0 {
            return "Vent de face: \(Int(headwind)) kt"
        } else if headwind < 0 {
            return "Vent arrière: \(Int(abs(headwind))) kt"
        } else {
            return "Vent de travers pur"
        }
    }

    var crosswindDescription: String {
        if crosswind < 1 {
            return "Pas de vent de travers"
        } else {
            return "Vent de travers: \(Int(crosswind)) kt (\(crosswindDirection.description))"
        }
    }
}
