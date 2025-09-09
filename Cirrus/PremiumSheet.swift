//
//  PremiumSheet.swift
//  Cirrus
//
//  Created by Pierre-Louis L'ALLORET on 25/08/2025.
//

import SwiftUI
import StoreKit

struct PremiumSheet: View {
    @StateObject private var premiumManager = PremiumManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProduct: Product?
    @State private var showingFeatureDetail = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    PremiumHeader()
                    
                    // Features grid
                    
                    // Pricing section
                    if !premiumManager.availableProducts.isEmpty {
                        PricingSection(selectedProduct: $selectedProduct)
                    }
                    
                    // Benefits comparison
                    BenefitsComparison()
                    
                    // Testimonials
                    TestimonialsSection()
                    
                    Spacer(minLength: 100)
                }
                .padding()
            }
            .navigationTitle("Cirrus Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if premiumManager.subscriptionInfo.isActive {
                        Image(systemName: "crown.fill")
                            .foregroundColor(.yellow)
                    }
                }
            }
            .overlay(
                // Purchase button overlay
                VStack {
                    Spacer()
                    PurchaseButtonOverlay(selectedProduct: $selectedProduct)
                }
                .ignoresSafeArea(.keyboard)
            )
        }
        .task {
            await premiumManager.initialize()
        }
    }
}

// MARK: - Premium Header

struct PremiumHeader: View {
    var body: some View {
        VStack(spacing: 16) {
            // Premium crown icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.yellow.opacity(0.3), .orange.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "crown.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("Débloquez le potentiel complet")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("Planifiez vos voyages comme un expert avec nos fonctionnalités premium")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Premium Feature Card

struct PremiumFeatureCard: View {
    let feature: PremiumFeatureDisplay   // <- au lieu de PremiumManager.PremiumFeature
    @State private var isPressed = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: feature.icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                
                Spacer()
                
                Image(systemName: "crown.fill")
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)    // <- adapte selon ton modèle
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                Text(feature.description)  // <- idem
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                .scaleEffect(isPressed ? 0.95 : 1.0)
        )
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = false
                }
            }
        }
    }
}

// MARK: - Pricing Section

struct PricingSection: View {
    @Binding var selectedProduct: Product?
    @StateObject private var premiumManager = PremiumManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choisissez votre formule")
                .font(.title3)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                ForEach(premiumManager.availableProducts, id: \.id) { product in
                    PricingCard(
                        product: product,
                        isSelected: selectedProduct?.id == product.id
                    ) {
                        selectedProduct = product
                    }
                }
            }
        }
    }
}

// MARK: - Pricing Card

struct PricingCard: View {
    let product: Product
    let isSelected: Bool
    let action: () -> Void
    
    private var isYearlyPlan: Bool {
        product.id.contains("yearly")
    }
    
    private var isLifetimePlan: Bool {
        product.id.contains("lifetime")
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(productTitle)
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        if isYearlyPlan {
                            Text("POPULAIRE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                        
                        if isLifetimePlan {
                            Text("MEILLEURE VALEUR")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(productDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if isYearlyPlan {
                        Text("Économisez 37%")
                            .font(.caption)
                            .foregroundColor(.green)
                            .fontWeight(.medium)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if !isLifetimePlan {
                        Text(priceSubtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .green : .secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var productTitle: String {
        if isYearlyPlan {
            return "Premium Annuel"
        } else if isLifetimePlan {
            return "Premium à Vie"
        } else {
            return "Premium Mensuel"
        }
    }
    
    private var productDescription: String {
        if isYearlyPlan {
            return "Facturation annuelle"
        } else if isLifetimePlan {
            return "Paiement unique"
        } else {
            return "Facturation mensuelle"
        }
    }
    
    private var priceSubtitle: String {
        if isYearlyPlan {
            return "par an"
        } else {
            return "par mois"
        }
    }
}

// MARK: - Benefits Comparison

struct BenefitsComparison: View {
    private let features = [
        ("Destinations favorites", "3", "Illimitées"),
        ("Prévisions météo", "7 jours", "30 jours"),
        ("Comparateur", "3 villes", "10 villes"),
        ("Assistant IA", "❌", "✅"),
        ("Radar temps réel", "❌", "✅"),
        ("Mode hors-ligne", "❌", "✅"),
        ("Notifications", "Basiques", "Intelligentes"),
        ("Support", "Standard", "Prioritaire")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Gratuit vs Premium")
                .font(.title3)
                .fontWeight(.semibold)
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Fonctionnalité")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text("Gratuit")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(width: 80)
                    
                    Text("Premium")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .frame(width: 80)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray5))
                
                // Features
                ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                    HStack {
                        Text(feature.0)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text(feature.1)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 80)
                        
                        Text(feature.2)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                            .frame(width: 80)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(index % 2 == 0 ? Color(.systemGray6) : Color.clear)
                }
            }
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
    }
}

// MARK: - Testimonials Section

struct TestimonialsSection: View {
    private let testimonials = [
        Testimonial(
            name: "Marie L.",
            location: "Paris",
            rating: 5,
            text: "Indispensable pour mes voyages d'affaires. Les prévisions étendues m'aident à optimiser mes déplacements."
        ),
        Testimonial(
            name: "Thomas R.",
            location: "Lyon",
            rating: 5,
            text: "L'assistant IA est bluffant ! Il m'a conseillé les meilleures dates pour visiter le Japon."
        ),
        Testimonial(
            name: "Sophie M.",
            location: "Marseille",
            rating: 5,
            text: "Le comparateur multi-destinations m'a fait gagner un temps précieux pour organiser mon tour d'Europe."
        )
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ce que disent nos utilisateurs")
                .font(.title3)
                .fontWeight(.semibold)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(testimonials, id: \.name) { testimonial in
                        TestimonialCard(testimonial: testimonial)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.horizontal, -16)
        }
    }
}

// MARK: - Testimonial Models and Card

struct Testimonial {
    let name: String
    let location: String
    let rating: Int
    let text: String
}

struct TestimonialCard: View {
    let testimonial: Testimonial
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 2) {
                ForEach(0..<testimonial.rating, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                }
            }
            
            Text("\"\(testimonial.text)\"")
                .font(.subheadline)
                .italic()
                .lineLimit(4)
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 2) {
                Text(testimonial.name)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text(testimonial.location)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(width: 200, height: 120)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Purchase Button Overlay

struct PurchaseButtonOverlay: View {
    @Binding var selectedProduct: Product?
    @StateObject private var premiumManager = PremiumManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 12) {
            if premiumManager.subscriptionInfo.isActive {
                // Already premium
                PremiumStatusView()
            } else {
                // Purchase buttons
                PurchaseButtons()
            }
        }
        .padding()
        .background(.regularMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.systemGray4)),
            alignment: .top
        )
    }
    
    @ViewBuilder
    private func PremiumStatusView() -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "crown.fill")
                    .foregroundColor(.yellow)
                
                Text("Premium Actif")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            if let expirationDate = premiumManager.subscriptionInfo.expirationDate {
                Text("Valide jusqu'au \(formatDate(expirationDate))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("Accès permanent")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Button("Gérer l'abonnement") {
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    UIApplication.shared.open(url)
                }
            }
            .font(.subheadline)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.1))
        )
    }
    
    @ViewBuilder
    private func PurchaseButtons() -> some View {
        VStack(spacing: 8) {
            if let product = selectedProduct {
                Button(action: {
                    Task {
                        do {
                            try await premiumManager.purchaseProduct(product)
                            dismiss()
                        } catch {
                            // Error handled by PremiumManager
                        }
                    }
                }) {
                    HStack {
                        if premiumManager.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "crown.fill")
                        }
                        
                        Text(premiumManager.isLoading ? "Traitement..." : "Commencer avec Premium")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .disabled(premiumManager.isLoading)
                
                Text("Essai gratuit de 7 jours, puis \(product.displayPrice)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Sélectionnez une formule ci-dessus")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 16) {
                Button("Restaurer") {
                    Task {
                        await premiumManager.restorePurchases()
                    }
                }
                .font(.subheadline)
                .disabled(premiumManager.isLoading)
                
                Button("Conditions") {
                    if let url = URL(string: "https://example.com/terms") {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.subheadline)
                
                Button("Confidentialité") {
                    if let url = URL(string: "https://example.com/privacy") {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.subheadline)
            }
            .foregroundColor(.secondary)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: date)
    }
}

#Preview {
    PremiumSheet()
}
