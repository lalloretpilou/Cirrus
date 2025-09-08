import Foundation
import StoreKit
import Combine

@MainActor
class PremiumManager: ObservableObject {
    static let shared = PremiumManager()
    
    @Published var isPremium: Bool = false
    @Published var subscriptionInfo: SubscriptionInfo
    @Published var availableProducts: [Product] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    private let userDefaults = UserDefaults.standard
    
    // MARK: - Product IDs
    enum ProductID: String, CaseIterable {
        case monthlySubscription = "com.travelsky.premium.monthly"
        case yearlySubscription = "com.travelsky.premium.yearly"
        case lifetimePurchase = "com.travelsky.premium.lifetime"
        
        var displayName: String {
            switch self {
            case .monthlySubscription: return "Premium Mensuel"
            case .yearlySubscription: return "Premium Annuel"
            case .lifetimePurchase: return "Premium à Vie"
            }
        }
        
        var description: String {
            switch self {
            case .monthlySubscription: return "Accès complet aux fonctionnalités premium"
            case .yearlySubscription: return "Économisez 37% avec l'abonnement annuel"
            case .lifetimePurchase: return "Achat unique, accès permanent"
            }
        }
    }
    
    // MARK: - Premium Features
    enum PremiumFeature: String, CaseIterable {
        case unlimitedDestinations = "unlimited_destinations"
        case extendedForecast = "extended_forecast"
        case advancedComparison = "advanced_comparison"
        case aiAssistant = "ai_assistant"
        case weatherRadar = "weather_radar"
        case smartNotifications = "smart_notifications"
        case offlineMode = "offline_mode"
        case exportData = "export_data"
        case prioritySupport = "priority_support"
        case customWidgets = "custom_widgets"
        
        var displayName: String {
            switch self {
            case .unlimitedDestinations: return "Destinations illimitées"
            case .extendedForecast: return "Prévisions 30 jours"
            case .advancedComparison: return "Comparateur avancé"
            case .aiAssistant: return "Assistant IA"
            case .weatherRadar: return "Radar temps réel"
            case .smartNotifications: return "Notifications intelligentes"
            case .offlineMode: return "Mode hors-ligne"
            case .exportData: return "Export des données"
            case .prioritySupport: return "Support prioritaire"
            case .customWidgets: return "Widgets personnalisés"
            }
        }
        
        var icon: String {
            switch self {
            case .unlimitedDestinations: return "location.fill"
            case .extendedForecast: return "calendar"
            case .advancedComparison: return "rectangle.split.3x1"
            case .aiAssistant: return "brain.head.profile"
            case .weatherRadar: return "radar"
            case .smartNotifications: return "bell.badge"
            case .offlineMode: return "icloud.slash"
            case .exportData: return "square.and.arrow.up"
            case .prioritySupport: return "person.badge.shield.checkmark"
            case .customWidgets: return "rectangle.stack"
            }
        }
    }
    
    private init() {
        self.subscriptionInfo = SubscriptionInfo(
            isActive: false,
            productId: nil,
            expirationDate: nil,
            autoRenews: false,
            purchaseDate: nil,
            trialEndDate: nil
        )
        
        loadSubscriptionInfo()
        startListeningForTransactions()
    }
    
    // MARK: - Public Methods
    
    func initialize() async {
        await loadProducts()
        await checkSubscriptionStatus()
    }
    
    func canUseFeature(_ feature: PremiumFeature) -> Bool {
        if isPremium { return true }
        
        // Fonctionnalités gratuites limitées
        switch feature {
        case .unlimitedDestinations:
            return getFavoriteDestinationsCount() < 3
        case .extendedForecast:
            return false // Limité à 7 jours en gratuit
        case .advancedComparison:
            return getComparisonCount() < 3
        default:
            return false
        }
    }
    
    func purchaseProduct(_ product: Product) async throws {
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verificationResult):
                let transaction = try checkVerified(verificationResult)
                await updateSubscriptionStatus(from: transaction)
                await transaction.finish()
                
            case .userCancelled:
                break
                
            case .pending:
                errorMessage = "Achat en attente d'approbation"
                
            @unknown default:
                errorMessage = "Erreur inconnue lors de l'achat"
            }
        } catch {
            errorMessage = "Erreur lors de l'achat: \(error.localizedDescription)"
            throw error
        }
        
        isLoading = false
    }
    
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await AppStore.sync()
            await checkSubscriptionStatus()
        } catch {
            errorMessage = "Erreur lors de la restauration: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - Private Methods
    
    private func loadProducts() async {
        do {
            let productIds = ProductID.allCases.map { $0.rawValue }
            let products = try await Product.products(for: productIds)
            
            await MainActor.run {
                self.availableProducts = products.sorted { product1, product2 in
                    // Trier par prix croissant
                    product1.price < product2.price
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Impossible de charger les produits: \(error.localizedDescription)"
            }
        }
    }
    
    private func checkSubscriptionStatus() async {
        var hasActiveSubscription = false
        var currentSubscription: SubscriptionInfo?
        
        // CORRIGÉ - L'énumération des entitlements peut effectivement échouer
        // Par exemple, si l'utilisateur n'est pas connecté à l'App Store
        do {
            for await result in Transaction.currentEntitlements {
                // Cette partie peut également échouer si la transaction n'est pas vérifiable
                do {
                    let transaction = try checkVerified(result)
                    
                    if let productId = ProductID(rawValue: transaction.productID) {
                        switch productId {
                        case .lifetimePurchase:
                            hasActiveSubscription = true
                            currentSubscription = SubscriptionInfo(
                                isActive: true,
                                productId: transaction.productID,
                                expirationDate: nil, // Pas d'expiration pour l'achat à vie
                                autoRenews: false,
                                purchaseDate: transaction.purchaseDate,
                                trialEndDate: nil
                            )
                            
                        case .monthlySubscription, .yearlySubscription:
                            if let expirationDate = transaction.expirationDate,
                               expirationDate > Date() {
                                hasActiveSubscription = true
                                currentSubscription = SubscriptionInfo(
                                    isActive: true,
                                    productId: transaction.productID,
                                    expirationDate: expirationDate,
                                    autoRenews: transaction.isUpgraded == false,
                                    purchaseDate: transaction.purchaseDate,
                                    trialEndDate: nil
                                )
                            }
                        }
                    }
                } catch {
                    print("Transaction verification failed: \(error)")
                }
            }
        } catch {
            // CORRIGÉ - Ce catch est maintenant accessible car l'énumération peut échouer
            // Scénarios possibles :
            // - Utilisateur non connecté à l'App Store
            // - Problème de réseau
            // - Problème de permissions App Store
            print("⚠️ Could not enumerate transactions: \(error.localizedDescription)")
            // Continuer sans erreur - c'est normal en développement ou si l'utilisateur n'est pas connecté
        }
        
        await MainActor.run {
            self.isPremium = hasActiveSubscription
            if let subscription = currentSubscription {
                self.subscriptionInfo = subscription
                self.saveSubscriptionInfo()
            }
        }
    }
    
    private func startListeningForTransactions() {
        Task.detached {
            // Cette partie est dans une Task détachée et peut échouer
            do {
                for await result in Transaction.updates {
                    do {
                        let transaction = try await self.checkVerified(result)
                        await self.updateSubscriptionStatus(from: transaction)
                        await transaction.finish()
                    } catch {
                        print("Transaction update failed: \(error)")
                    }
                }
            } catch {
                print("Failed to listen for transaction updates: \(error)")
            }
        }
    }
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
    
    private func updateSubscriptionStatus(from transaction: Transaction) async {
        guard let productId = ProductID(rawValue: transaction.productID) else { return }
        
        let newSubscription: SubscriptionInfo
        
        switch productId {
        case .lifetimePurchase:
            newSubscription = SubscriptionInfo(
                isActive: true,
                productId: transaction.productID,
                expirationDate: nil,
                autoRenews: false,
                purchaseDate: transaction.purchaseDate,
                trialEndDate: nil
            )
            
        case .monthlySubscription, .yearlySubscription:
            newSubscription = SubscriptionInfo(
                isActive: transaction.expirationDate ?? Date.distantFuture > Date(),
                productId: transaction.productID,
                expirationDate: transaction.expirationDate,
                autoRenews: transaction.isUpgraded == false,
                purchaseDate: transaction.purchaseDate,
                trialEndDate: nil
            )
        }
        
        await MainActor.run {
            self.isPremium = newSubscription.isActive
            self.subscriptionInfo = newSubscription
            self.saveSubscriptionInfo()
        }
    }
    
    // MARK: - UserDefaults Management
    
    private func saveSubscriptionInfo() {
        if let data = try? JSONEncoder().encode(subscriptionInfo) {
            userDefaults.set(data, forKey: "SubscriptionInfo")
        }
    }
    
    private func loadSubscriptionInfo() {
        if let data = userDefaults.data(forKey: "SubscriptionInfo"),
           let subscription = try? JSONDecoder().decode(SubscriptionInfo.self, from: data) {
            subscriptionInfo = subscription
            isPremium = subscription.isActive
        }
    }
    
    // MARK: - Usage Tracking (for Free Tier Limits)
    
    private func getFavoriteDestinationsCount() -> Int {
        // Implementation depends on your data store
        return userDefaults.integer(forKey: "FavoriteDestinationsCount")
    }
    
    private func getComparisonCount() -> Int {
        let today = DateFormatter().string(from: Date())
        return userDefaults.integer(forKey: "ComparisonCount_\(today)")
    }
    
    func incrementFavoriteDestinations() {
        let count = getFavoriteDestinationsCount() + 1
        userDefaults.set(count, forKey: "FavoriteDestinationsCount")
    }
    
    func incrementComparisonCount() {
        let today = DateFormatter().string(from: Date())
        let count = getComparisonCount() + 1
        userDefaults.set(count, forKey: "ComparisonCount_\(today)")
    }
    
    // MARK: - Premium Feature Descriptions
    
    func getPremiumFeatures() -> [PremiumFeature] {
        return PremiumFeature.allCases
    }
    
    func getFeatureDescription(_ feature: PremiumFeature) -> String {
        switch feature {
        case .unlimitedDestinations:
            return "Ajoutez autant de destinations favorites que vous le souhaitez"
        case .extendedForecast:
            return "Prévisions météo jusqu'à 30 jours pour planifier vos voyages"
        case .advancedComparison:
            return "Comparez jusqu'à 10 destinations avec filtres avancés"
        case .aiAssistant:
            return "Assistant IA personnalisé pour recommandations voyage"
        case .weatherRadar:
            return "Radar météo en temps réel avec alertes précipitations"
        case .smartNotifications:
            return "Notifications intelligentes et personnalisées"
        case .offlineMode:
            return "Accès aux données météo sans connexion internet"
        case .exportData:
            return "Exportez vos données et plannings en PDF"
        case .prioritySupport:
            return "Support client prioritaire sous 24h"
        case .customWidgets:
            return "Widgets personnalisables pour écran d'accueil"
        }
    }
}

// MARK: - Store Errors

enum StoreError: Error, LocalizedError {
    case failedVerification
    case system(Error)
    
    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return "Échec de la vérification de l'achat"
        case .system(let error):
            return error.localizedDescription
        }
    }
}
