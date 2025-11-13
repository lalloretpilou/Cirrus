import Foundation
import CoreLocation

// MARK: - Aviation Weather Models

/// Modèle pour les données METAR (observations météo aéronautiques)
struct METAR: Codable, Identifiable {
    var id = UUID()
    let station: String // Code ICAO de l'aéroport (ex: LFPG pour Paris CDG)
    let observationTime: Date
    let rawText: String // Texte brut du METAR
    let flightRules: FlightRules

    // Conditions météo
    let temperature: Double
    let dewpoint: Double
    let windDirection: Int
    let windSpeed: Double
    let windGust: Double?
    let visibility: Double // en mètres
    let altimeter: Double // QNH en hPa

    // Conditions spéciales
    let clouds: [CloudLayer]
    let weatherPhenomena: [WeatherPhenomenon]

    enum CodingKeys: String, CodingKey {
        case station, observationTime, rawText, flightRules
        case temperature, dewpoint, windDirection, windSpeed, windGust
        case visibility, altimeter, clouds, weatherPhenomena
    }
}

/// Modèle pour les données TAF (prévisions aéronautiques)
struct TAF: Codable, Identifiable {
    var id = UUID()
    let station: String
    let issueTime: Date
    let validFrom: Date
    let validTo: Date
    let rawText: String

    let forecast: [TAFForecastPeriod]

    enum CodingKeys: String, CodingKey {
        case station, issueTime, validFrom, validTo, rawText, forecast
    }
}

/// Période de prévision dans un TAF
struct TAFForecastPeriod: Codable, Identifiable {
    var id = UUID()
    let validFrom: Date
    let validTo: Date
    let changeIndicator: ChangeIndicator? // TEMPO, BECMG, PROB30, etc.

    let windDirection: Int
    let windSpeed: Double
    let windGust: Double?
    let visibility: Double
    let clouds: [CloudLayer]
    let weatherPhenomena: [WeatherPhenomenon]
    let flightRules: FlightRules

    enum ChangeIndicator: String, Codable {
        case tempo = "TEMPO"
        case becoming = "BECMG"
        case probability30 = "PROB30"
        case probability40 = "PROB40"
    }

    enum CodingKeys: String, CodingKey {
        case validFrom, validTo, changeIndicator
        case windDirection, windSpeed, windGust, visibility
        case clouds, weatherPhenomena, flightRules
    }
}

/// Couche de nuages
struct CloudLayer: Codable, Identifiable {
    var id = UUID()
    let coverage: CloudCoverage
    let altitude: Int // en pieds AGL
    let type: CloudType?

    enum CloudCoverage: String, Codable {
        case skyClear = "SKC"
        case clear = "CLR"
        case few = "FEW" // 1-2 oktas
        case scattered = "SCT" // 3-4 oktas
        case broken = "BKN" // 5-7 oktas
        case overcast = "OVC" // 8 oktas
        case verticalVisibility = "VV" // Visibilité verticale
    }

    enum CloudType: String, Codable {
        case cumulonimbus = "CB"
        case toweringCumulus = "TCU"
    }

    enum CodingKeys: String, CodingKey {
        case coverage, altitude, type
    }
}

/// Phénomène météorologique
struct WeatherPhenomenon: Codable, Identifiable {
    var id = UUID()
    let intensity: Intensity
    let descriptor: Descriptor?
    let precipitation: [Precipitation]
    let obscuration: [Obscuration]
    let other: [OtherPhenomenon]

    enum Intensity: String, Codable {
        case light = "-"
        case moderate = ""
        case heavy = "+"
        case vicinity = "VC"
    }

    enum Descriptor: String, Codable {
        case shallow = "MI"
        case partial = "PR"
        case patches = "BC"
        case lowDrifting = "DR"
        case blowing = "BL"
        case shower = "SH"
        case thunderstorm = "TS"
        case freezing = "FZ"
    }

    enum Precipitation: String, Codable {
        case drizzle = "DZ"
        case rain = "RA"
        case snow = "SN"
        case snowGrains = "SG"
        case icePellets = "PL"
        case hail = "GR"
        case smallHail = "GS"
    }

    enum Obscuration: String, Codable {
        case mist = "BR"
        case fog = "FG"
        case smoke = "FU"
        case volcanicAsh = "VA"
        case dust = "DU"
        case sand = "SA"
        case haze = "HZ"
    }

    enum OtherPhenomenon: String, Codable {
        case dustStorm = "DS"
        case sandStorm = "SS"
        case funnel = "FC"
        case squall = "SQ"
    }

    enum CodingKeys: String, CodingKey {
        case intensity, descriptor, precipitation, obscuration, other
    }
}

/// Règles de vol
enum FlightRules: String, Codable {
    case vfr = "VFR"   // Visual Flight Rules - Visibilité > 5km, plafond > 1500ft
    case mvfr = "MVFR" // Marginal VFR - Visibilité 3-5km ou plafond 1000-1500ft
    case ifr = "IFR"   // Instrument Flight Rules - Visibilité 1-3km ou plafond 500-1000ft
    case lifr = "LIFR" // Low IFR - Visibilité < 1km ou plafond < 500ft

    var color: String {
        switch self {
        case .vfr: return "#00FF00"   // Vert
        case .mvfr: return "#0000FF"  // Bleu
        case .ifr: return "#FF0000"   // Rouge
        case .lifr: return "#FF00FF"  // Magenta
        }
    }

    var description: String {
        switch self {
        case .vfr: return "Conditions VFR - Vol à vue autorisé"
        case .mvfr: return "Conditions VFR marginales - Vol à vue possible mais limité"
        case .ifr: return "Conditions IFR - Vol aux instruments requis"
        case .lifr: return "Conditions IFR basses - Conditions difficiles"
        }
    }
}

/// NOTAM (Notice to Airmen) - Informations aéronautiques
struct NOTAM: Codable, Identifiable {
    var id = UUID()
    let notamID: String
    let location: String
    let effectiveStart: Date
    let effectiveEnd: Date?
    let text: String
    let category: NOTAMCategory

    enum NOTAMCategory: String, Codable {
        case runway = "RWY"
        case taxiway = "TWY"
        case airspace = "AIRSPACE"
        case navigation = "NAV"
        case communications = "COM"
        case services = "SVC"
        case obstacles = "OBS"
        case other = "OTHER"
    }

    enum CodingKeys: String, CodingKey {
        case notamID, location, effectiveStart, effectiveEnd, text, category
    }
}

// MARK: - Flight Planning Models

/// Recommandation de vol basée sur la météo
struct FlightRecommendation: Identifiable {
    let id = UUID()
    let overallSafety: SafetyLevel
    let recommendedAltitude: AltitudeRecommendation
    let flightType: RecommendedFlightType
    let warnings: [FlightWarning]
    let advisories: [FlightAdvisory]
    let weatherSummary: String
    let recommendedDepartureWindow: DateInterval?

    enum SafetyLevel: String {
        case safe = "Sûr"
        case caution = "Prudence"
        case notRecommended = "Non recommandé"
        case dangerous = "Dangereux"

        var color: String {
            switch self {
            case .safe: return "#00FF00"
            case .caution: return "#FFA500"
            case .notRecommended: return "#FF4500"
            case .dangerous: return "#FF0000"
            }
        }
    }
}

/// Recommandation d'altitude
struct AltitudeRecommendation: Codable {
    let minimumAltitude: Int // en pieds
    let maximumAltitude: Int // en pieds
    let optimalAltitude: Int // en pieds
    let reason: String

    var altitudeRange: String {
        return "\(minimumAltitude)ft - \(maximumAltitude)ft"
    }
}

/// Type de vol recommandé
enum RecommendedFlightType: String, Codable {
    case localVFR = "Vol local VFR"
    case crossCountryVFR = "Navigation VFR"
    case ifr = "Vol IFR"
    case training = "Vol d'entraînement"
    case postpone = "Reporter le vol"
    case cancel = "Annuler le vol"

    var icon: String {
        switch self {
        case .localVFR: return "airplane.circle"
        case .crossCountryVFR: return "airplane.departure"
        case .ifr: return "cloud.fill"
        case .training: return "graduationcap"
        case .postpone: return "clock"
        case .cancel: return "xmark.circle"
        }
    }
}

/// Avertissement de vol
struct FlightWarning: Identifiable {
    let id = UUID()
    let severity: WarningSeverity
    let title: String
    let description: String
    let affectedAltitudes: ClosedRange<Int>? // en pieds

    enum WarningSeverity: String {
        case critical = "Critique"
        case high = "Élevé"
        case medium = "Moyen"
        case low = "Faible"

        var color: String {
            switch self {
            case .critical: return "#FF0000"
            case .high: return "#FF4500"
            case .medium: return "#FFA500"
            case .low: return "#FFD700"
            }
        }
    }
}

/// Conseil de vol
struct FlightAdvisory: Identifiable {
    let id = UUID()
    let category: AdvisoryCategory
    let message: String
    let priority: Int

    enum AdvisoryCategory: String {
        case wind = "Vent"
        case visibility = "Visibilité"
        case clouds = "Nuages"
        case turbulence = "Turbulence"
        case icing = "Givrage"
        case precipitation = "Précipitations"
        case temperature = "Température"
        case general = "Général"

        var icon: String {
            switch self {
            case .wind: return "wind"
            case .visibility: return "eye.fill"
            case .clouds: return "cloud.fill"
            case .turbulence: return "aqi.medium"
            case .icing: return "snowflake"
            case .precipitation: return "cloud.rain.fill"
            case .temperature: return "thermometer"
            case .general: return "info.circle"
            }
        }
    }
}

// MARK: - Airport Models

/// Informations sur un aéroport
struct Airport: Codable, Identifiable {
    var id = UUID()
    let icaoCode: String
    let iataCode: String?
    let name: String
    let location: Location
    let elevation: Int // en pieds
    let runways: [Runway]
    let hasControlTower: Bool
    let operatingHours: String?

    enum CodingKeys: String, CodingKey {
        case icaoCode, iataCode, name, location, elevation
        case runways, hasControlTower, operatingHours
    }
}

/// Piste d'atterrissage
struct Runway: Codable, Identifiable {
    var id = UUID()
    let identifier: String // ex: "09/27"
    let length: Int // en mètres
    let width: Int // en mètres
    let surface: SurfaceType
    let lighting: Bool

    enum SurfaceType: String, Codable {
        case asphalt = "Asphalte"
        case concrete = "Béton"
        case grass = "Herbe"
        case gravel = "Gravier"
        case dirt = "Terre"
    }

    enum CodingKeys: String, CodingKey {
        case identifier, length, width, surface, lighting
    }
}

// MARK: - Aviation Weather Data Container

/// Conteneur pour toutes les données météo aéronautiques
struct AviationWeatherData: Identifiable {
    let id = UUID()
    let location: Location
    let airport: Airport?
    let metar: METAR?
    let taf: TAF?
    let notams: [NOTAM]
    let recommendation: FlightRecommendation
    let nearbyAirports: [Airport]
    let lastUpdated: Date
}

// MARK: - Wind Components

/// Composantes du vent pour une piste
struct WindComponents {
    let headwind: Double // Composante de face (positive)
    let crosswind: Double // Composante de travers (absolute)
    let tailwind: Double // Composante arrière (positive si vent arrière)
    let runwayHeading: Int

    var isHeadwind: Bool { headwind > 0 }
    var isCrosswind: Bool { abs(crosswind) > 5 }
    var isTailwind: Bool { tailwind > 0 }

    var description: String {
        if isTailwind && tailwind > 5 {
            return "⚠️ Vent arrière: \(Int(tailwind))kt"
        } else if isCrosswind && abs(crosswind) > 10 {
            return "⚠️ Vent de travers: \(Int(abs(crosswind)))kt"
        } else if isHeadwind {
            return "✅ Vent de face: \(Int(headwind))kt"
        } else {
            return "Vent faible"
        }
    }
}
