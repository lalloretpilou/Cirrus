//
//  colorExt.swift
//  Cirrus
//
//  Created by Pierre-Louis L'ALLORET on 08/09/2025.
//

import SwiftUI

extension Color {
    // MARK: - Premium Brand Colors
    static let premiumOrange = Color(hex: "CF4616")
    static let premiumGradientStart = Color(hex: "CF4616")
    static let premiumGradientEnd = Color(hex: "FF6B35")
    static let premiumAccent = Color(hex: "CF4616")
    
    // MARK: - Premium Gradients
    static let premiumGradient = LinearGradient(
        colors: [.premiumGradientStart, .premiumGradientEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let premiumRadialGradient = RadialGradient(
        colors: [.premiumOrange.opacity(0.8), .clear],
        center: .center,
        startRadius: 2,
        endRadius: 12
    )
    
    // MARK: - App Theme Colors
    static let cirrusPrimary = Color.primary
    static let cirrusSecondary = Color.secondary
    static let cirrusBackground = Color(.systemBackground)
    static let cirrusGroupedBackground = Color(.systemGroupedBackground)
    
    // MARK: - Weather Condition Colors
    static let sunny = Color.yellow
    static let cloudy = Color.gray
    static let rainy = Color.blue
    static let stormy = Color.purple
    static let snowy = Color.white
    
    // MARK: - Comfort Score Colors
    static let comfortExcellent = Color.green
    static let comfortGood = Color.yellow
    static let comfortFair = Color.premiumOrange
    static let comfortPoor = Color.red
    
    // MARK: - Status Colors
    static let statusSuccess = Color.green
    static let statusWarning = Color.orange
    static let statusError = Color.red
    static let statusInfo = Color.blue
    
    // MARK: - Premium Feature Colors
    static let featureUnlocked = Color.premiumOrange
    static let featureLocked = Color.gray
    static let featureComingSoon = Color.blue
    
    // MARK: - Material Colors
    static let cardBackground = Color(.systemBackground).opacity(0.8)
    static let glassMaterial = Color.white.opacity(0.1)
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
