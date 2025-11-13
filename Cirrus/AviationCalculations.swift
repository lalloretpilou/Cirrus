//
//  AviationCalculations.swift
//  Cirrus
//
//  Aviation calculation utilities for pilots
//

import Foundation
import CoreLocation

struct AviationCalculations {

    // MARK: - Density Altitude

    /// Calculate density altitude based on pressure altitude, temperature, and humidity
    /// Density altitude affects aircraft performance significantly
    static func calculateDensityAltitude(
        pressureAltitude: Int,
        temperature: Double,
        dewpoint: Double,
        altimeter: Double
    ) -> DensityAltitude {
        // Calculate ISA (International Standard Atmosphere) temperature at pressure altitude
        let isaTemp = 15.0 - (pressureAltitude / 1000.0 * 2.0)

        // Temperature difference from ISA
        let tempDiff = temperature - isaTemp

        // Density altitude approximation (simplified formula)
        // DA = PA + (120 * (OAT - ISA))
        let densityAltitude = pressureAltitude + Int(120.0 * tempDiff)

        // Calculate relative humidity
        let relativeHumidity = calculateRelativeHumidity(temperature: temperature, dewpoint: dewpoint)

        // Determine performance impact
        let performanceImpact = determinePerformanceImpact(densityAltitude: densityAltitude)

        return DensityAltitude(
            pressureAltitude: pressureAltitude,
            densityAltitude: densityAltitude,
            temperature: temperature,
            dewpoint: dewpoint,
            altimeter: altimeter,
            relativeHumidity: relativeHumidity,
            performanceImpact: performanceImpact
        )
    }

    /// Calculate pressure altitude from field elevation and altimeter setting
    static func calculatePressureAltitude(fieldElevation: Int, altimeter: Double) -> Int {
        // Standard pressure: 29.92 inHg
        let standardPressure = 29.92
        let pressureDiff = standardPressure - altimeter

        // Approximately 1 inch Hg = 1000 feet
        let correction = Int(pressureDiff * 1000.0)

        return fieldElevation + correction
    }

    private static func calculateRelativeHumidity(temperature: Double, dewpoint: Double) -> Double {
        // Magnus formula for relative humidity
        let a = 17.625
        let b = 243.04

        let gamma_t = (a * temperature) / (b + temperature)
        let gamma_dp = (a * dewpoint) / (b + dewpoint)

        let rh = 100.0 * exp(gamma_dp - gamma_t)
        return min(100.0, max(0.0, rh))
    }

    private static func determinePerformanceImpact(densityAltitude: Int) -> DensityAltitude.PerformanceImpact {
        switch densityAltitude {
        case ..<1000:
            return .excellent
        case 1000..<3000:
            return .good
        case 3000..<5000:
            return .fair
        case 5000..<8000:
            return .poor
        default:
            return .critical
        }
    }

    // MARK: - Wind Components

    /// Calculate headwind and crosswind components for a given runway
    static func calculateWindComponents(
        windDirection: Int,
        windSpeed: Int,
        runwayHeading: Int
    ) -> WindComponents {
        guard windSpeed > 0 else {
            return WindComponents(
                headwind: 0,
                crosswind: 0,
                crosswindDirection: .none,
                effectiveWindSpeed: 0,
                windDirection: windDirection,
                runwayHeading: runwayHeading
            )
        }

        // Calculate angle between wind and runway
        var angle = Double(windDirection - runwayHeading)

        // Normalize angle to -180 to 180
        while angle > 180 { angle -= 360 }
        while angle < -180 { angle += 360 }

        let angleRadians = angle * .pi / 180.0

        // Calculate components
        let headwind = Double(windSpeed) * cos(angleRadians)
        let crosswind = abs(Double(windSpeed) * sin(angleRadians))

        // Determine crosswind direction
        let crosswindDirection: WindComponents.CrosswindDirection
        if crosswind < 1 {
            crosswindDirection = .none
        } else if angle > 0 {
            crosswindDirection = .right
        } else {
            crosswindDirection = .left
        }

        return WindComponents(
            headwind: headwind,
            crosswind: crosswind,
            crosswindDirection: crosswindDirection,
            effectiveWindSpeed: Double(windSpeed),
            windDirection: windDirection,
            runwayHeading: runwayHeading
        )
    }

    // MARK: - True Airspeed (TAS)

    /// Calculate True Airspeed from Indicated Airspeed
    static func calculateTrueAirspeed(
        indicatedAirspeed: Int,
        pressureAltitude: Int,
        temperature: Double
    ) -> Int {
        // TAS = IAS * sqrt(ρ0/ρ)
        // Simplified formula: TAS ≈ IAS + (IAS * 0.02 * altitude/1000)

        let altitudeFactor = Double(pressureAltitude) / 1000.0
        let tempFactor = (temperature + 273.15) / 288.15 // Temperature correction

        let tas = Double(indicatedAirspeed) * (1.0 + 0.02 * altitudeFactor) * sqrt(tempFactor)

        return Int(tas)
    }

    /// Calculate Ground Speed from True Airspeed and wind
    static func calculateGroundSpeed(
        trueAirspeed: Int,
        windDirection: Int,
        windSpeed: Int,
        heading: Int
    ) -> Int {
        let windComponents = calculateWindComponents(
            windDirection: windDirection,
            windSpeed: windSpeed,
            runwayHeading: heading
        )

        let groundSpeed = Double(trueAirspeed) + windComponents.headwind

        return max(0, Int(groundSpeed))
    }

    // MARK: - Cloud Base

    /// Estimate cloud base altitude using temperature-dewpoint spread
    static func estimateCloudBase(
        temperature: Double,
        dewpoint: Double,
        fieldElevation: Int
    ) -> Int {
        // Temperature-dewpoint spread method
        // Cloud base ≈ (Temperature - Dewpoint) / 2.5 * 1000 + field elevation

        let spread = temperature - dewpoint
        let cloudBaseAGL = (spread / 2.5) * 1000.0

        return fieldElevation + Int(cloudBaseAGL)
    }

    // MARK: - Visibility Conversion

    /// Convert visibility from statute miles to meters
    static func statuteMilesToMeters(_ miles: Double) -> Int {
        return Int(miles * 1609.34)
    }

    /// Convert visibility from meters to statute miles
    static func metersToStatuteMiles(_ meters: Int) -> Double {
        return Double(meters) / 1609.34
    }

    // MARK: - Temperature Conversion

    /// Convert Celsius to Fahrenheit
    static func celsiusToFahrenheit(_ celsius: Double) -> Double {
        return celsius * 9.0 / 5.0 + 32.0
    }

    /// Convert Fahrenheit to Celsius
    static func fahrenheitToCelsius(_ fahrenheit: Double) -> Double {
        return (fahrenheit - 32.0) * 5.0 / 9.0
    }

    // MARK: - Pressure Conversion

    /// Convert inHg to hPa
    static func inHgToHPa(_ inHg: Double) -> Double {
        return inHg * 33.8639
    }

    /// Convert hPa to inHg
    static func hPaToInHg(_ hPa: Double) -> Double {
        return hPa / 33.8639
    }

    // MARK: - Distance and Bearing

    /// Calculate distance between two coordinates in nautical miles
    static func distanceNauticalMiles(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> Double {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)

        let distanceMeters = fromLocation.distance(from: toLocation)
        return distanceMeters / 1852.0 // Convert to nautical miles
    }

    /// Calculate bearing between two coordinates
    static func bearing(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> Double {
        let lat1 = from.latitude * .pi / 180.0
        let lon1 = from.longitude * .pi / 180.0
        let lat2 = to.latitude * .pi / 180.0
        let lon2 = to.longitude * .pi / 180.0

        let dLon = lon2 - lon1

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)

        var bearing = atan2(y, x) * 180.0 / .pi
        bearing = (bearing + 360.0).truncatingRemainder(dividingBy: 360.0)

        return bearing
    }

    // MARK: - Fuel Calculations

    /// Calculate estimated flight time
    static func calculateFlightTime(
        distance: Double, // Nautical miles
        groundSpeed: Int  // Knots
    ) -> TimeInterval {
        guard groundSpeed > 0 else { return 0 }
        let hours = distance / Double(groundSpeed)
        return hours * 3600.0 // Convert to seconds
    }

    /// Calculate fuel required
    static func calculateFuelRequired(
        flightTime: TimeInterval,
        fuelBurnRate: Double, // Gallons per hour
        reserveMinutes: Int = 45
    ) -> Double {
        let flightHours = flightTime / 3600.0
        let reserveHours = Double(reserveMinutes) / 60.0

        return (flightHours + reserveHours) * fuelBurnRate
    }

    // MARK: - Runway Performance

    /// Estimate takeoff distance (simplified)
    static func estimateTakeoffDistance(
        densityAltitude: Int,
        windComponent: Double, // Headwind is positive, tailwind is negative
        weight: Int,           // Aircraft weight in pounds
        maxWeight: Int         // Maximum takeoff weight
    ) -> Int {
        // Base takeoff distance (this should be specific to aircraft)
        var baseDistance = 1000

        // Density altitude factor (10% per 1000 ft)
        let daFactor = 1.0 + (Double(densityAltitude) / 1000.0 * 0.10)

        // Wind factor (10% per 10 knots headwind, -10% per 10 knots tailwind)
        let windFactor = 1.0 - (windComponent / 10.0 * 0.10)

        // Weight factor
        let weightRatio = Double(weight) / Double(maxWeight)
        let weightFactor = 0.5 + (weightRatio * 0.5)

        let takeoffDistance = Double(baseDistance) * daFactor * windFactor * weightFactor

        return Int(takeoffDistance)
    }

    /// Estimate landing distance (simplified)
    static func estimateLandingDistance(
        densityAltitude: Int,
        windComponent: Double,
        weight: Int,
        maxWeight: Int
    ) -> Int {
        // Base landing distance
        var baseDistance = 800

        // Density altitude factor (5% per 1000 ft)
        let daFactor = 1.0 + (Double(densityAltitude) / 1000.0 * 0.05)

        // Wind factor (10% per 10 knots headwind, +20% per 10 knots tailwind)
        let windFactor: Double
        if windComponent > 0 {
            windFactor = 1.0 - (windComponent / 10.0 * 0.10)
        } else {
            windFactor = 1.0 + (abs(windComponent) / 10.0 * 0.20)
        }

        // Weight factor
        let weightRatio = Double(weight) / Double(maxWeight)
        let weightFactor = 0.6 + (weightRatio * 0.4)

        let landingDistance = Double(baseDistance) * daFactor * windFactor * weightFactor

        return Int(landingDistance)
    }

    // MARK: - Flight Rules Determination

    /// Determine flight rules based on ceiling and visibility
    static func determineFlightRules(ceiling: Int?, visibility: Double) -> FlightRules {
        let ceilingFeet = ceiling ?? 10000

        if ceilingFeet > 3000 && visibility > 5 {
            return .vfr
        } else if (ceilingFeet >= 1000 && ceilingFeet <= 3000) || (visibility >= 3 && visibility <= 5) {
            return .mvfr
        } else if (ceilingFeet >= 500 && ceilingFeet < 1000) || (visibility >= 1 && visibility < 3) {
            return .ifr
        } else {
            return .lifr
        }
    }

    // MARK: - Crosswind Limits

    /// Check if crosswind exceeds aircraft limits
    static func isWithinCrosswindLimits(
        crosswind: Double,
        demonstratedCrosswind: Double,
        maxCrosswind: Double? = nil
    ) -> (withinLimits: Bool, warning: String?) {
        let max = maxCrosswind ?? demonstratedCrosswind

        if crosswind <= demonstratedCrosswind {
            return (true, nil)
        } else if crosswind <= max {
            return (true, "⚠️ Au-dessus du vent de travers démontré (\(Int(demonstratedCrosswind)) kt)")
        } else {
            return (false, "⛔ Dépasse la limite de vent de travers (\(Int(max)) kt)")
        }
    }

    // MARK: - Time to Altitude

    /// Estimate time to reach cruise altitude
    static func estimateTimeToAltitude(
        currentAltitude: Int,
        targetAltitude: Int,
        climbRate: Int // Feet per minute
    ) -> TimeInterval {
        guard climbRate > 0 else { return 0 }

        let altitudeDifference = targetAltitude - currentAltitude
        guard altitudeDifference > 0 else { return 0 }

        let minutes = Double(altitudeDifference) / Double(climbRate)
        return minutes * 60.0 // Convert to seconds
    }

    // MARK: - Weight and Balance

    /// Calculate center of gravity
    static func calculateCenterOfGravity(
        emptyWeight: Int,
        emptyArm: Double,
        loads: [(weight: Int, arm: Double)]
    ) -> (totalWeight: Int, cgArm: Double, cgPercent: Double) {
        var totalWeight = emptyWeight
        var totalMoment = Double(emptyWeight) * emptyArm

        for load in loads {
            totalWeight += load.weight
            totalMoment += Double(load.weight) * load.arm
        }

        let cgArm = totalMoment / Double(totalWeight)

        // CG percentage would require aircraft-specific datum
        // This is a placeholder
        let cgPercent = 25.0 // Would need actual calculation based on aircraft

        return (totalWeight, cgArm, cgPercent)
    }

    // MARK: - Altimetry

    /// Calculate altitude corrections
    static func calculateAltitudeCorrections(
        indicatedAltitude: Int,
        altimeter: Double,
        temperature: Double,
        standardTemperature: Double
    ) -> (trueAltitude: Int, correction: Int) {
        // Temperature correction for altitude
        let tempError = temperature - standardTemperature

        // Approximately 4 feet per 1000 feet per 1°C deviation
        let correction = Int((Double(indicatedAltitude) / 1000.0) * 4.0 * tempError)

        let trueAltitude = indicatedAltitude + correction

        return (trueAltitude, correction)
    }

    // MARK: - Sun Position (for twilight calculations)

    /// Calculate sunrise and sunset times would require complex astronomical calculations
    /// This would typically use WeatherKit data or external APIs
    /// Placeholder for civil twilight determination

    static func isCivilTwilight(sunriseTime: Date, sunsetTime: Date, currentTime: Date) -> Bool {
        // Civil twilight is 30 minutes before sunrise and 30 minutes after sunset
        let twilightDuration: TimeInterval = 30 * 60

        let morningTwilight = sunriseTime.addingTimeInterval(-twilightDuration)
        let eveningTwilight = sunsetTime.addingTimeInterval(twilightDuration)

        return currentTime < morningTwilight || currentTime > eveningTwilight
    }
}
