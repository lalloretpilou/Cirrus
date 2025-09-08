import SwiftUI
import CoreLocation

struct StartupView: View {
    @StateObject private var premiumManager = PremiumManager.shared
    @StateObject private var weatherViewModel = WeatherViewModel()
    @State private var isInitializing = true
    @State private var initializationSteps: [InitStep] = []
    @State private var currentStepIndex = 0
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            if isInitializing {
                InitializationView(steps: initializationSteps, currentStep: currentStepIndex)
            } else {
                ContentView()
                    .environmentObject(premiumManager)
                    .environmentObject(weatherViewModel)
            }
        }
        .task {
            await performStartupInitialization()
        }
    }
    
    // MARK: - Startup Initialization
    
    private func performStartupInitialization() async {
        print("🚀 Starting app initialization...")
        
        // Définir les étapes d'initialisation
        initializationSteps = [
            InitStep(title: "Initialisation", description: "Démarrage de Cirrus", isCompleted: false),
            InitStep(title: "Services Premium", description: "Vérification des abonnements", isCompleted: false),
            InitStep(title: "Localisation", description: "Configuration de la géolocalisation", isCompleted: false),
            InitStep(title: "Données météo", description: "Chargement des prévisions", isCompleted: false),
            InitStep(title: "Interface", description: "Finalisation", isCompleted: false)
        ]
        
        // Étape 1: Initialisation de base
        updateStep(0, "Initialisation de Cirrus...")
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s pour effet visuel
        completeStep(0)
        
        // Étape 2: Services Premium
        updateStep(1, "Vérification Premium...")
        await premiumManager.initialize()
        completeStep(1)
        
        // Étape 3: Géolocalisation - CORRIGÉ
        updateStep(2, "Configuration géolocalisation...")
        setupLocationServices()
        completeStep(2)
        
        // Étape 4: Données météo
        updateStep(3, "Chargement météo...")
        await loadInitialWeatherData()
        completeStep(3)
        
        // Étape 5: Finalisation
        updateStep(4, "Finalisation...")
        try? await Task.sleep(nanoseconds: 500_000_000)
        completeStep(4)
        
        // Attendre un peu puis passer à l'interface principale
        try? await Task.sleep(nanoseconds: 800_000_000)
        
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.5)) {
                isInitializing = false
            }
        }
        
        print("✅ App initialization completed!")
    }
    
    // CORRIGÉ - Ne plus appeler authorizationStatus directement
    private func setupLocationServices() {
        guard CLLocationManager.locationServicesEnabled() else {
            print("❌ Location services not available")
            return
        }
        
        print("📍 Location services available - setup complete")
        
        // CORRIGÉ - La demande sera faite au bon moment via l'interface utilisateur
        // Cela évite les warnings et respecte le flow UX
        
        // Le WeatherViewModel gérera les permissions quand l'utilisateur interagira
        // CORRIGÉ - Enlever l'await puisque checkInitialLocationStatus est synchrone
        weatherViewModel.checkInitialLocationStatus()
    }
    
    private func loadInitialWeatherData() async {
        await weatherViewModel.loadWeatherForCurrentLocation()
        print("✅ Initial weather data loaded")
    }
    
    // MARK: - Step Management
    
    @MainActor
    private func updateStep(_ index: Int, _ description: String) {
        guard index < initializationSteps.count else { return }
        
        currentStepIndex = index
        initializationSteps[index].description = description
    }
    
    @MainActor
    private func completeStep(_ index: Int) {
        guard index < initializationSteps.count else { return }
        
        initializationSteps[index].isCompleted = true
    }
}

// MARK: - Initialization Models

struct InitStep {
    let title: String
    var description: String
    var isCompleted: Bool
}

// MARK: - Initialization View - CORRIGÉ

struct InitializationView: View {
    let steps: [InitStep]
    let currentStep: Int
    
    var body: some View {
        VStack(spacing: 40) {
            // App logo and title
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: "airplane.departure")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(spacing: 8) {
                    Text("Cirrus")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text("Météo de voyage intelligente")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            // Progress steps
            VStack(spacing: 20) {
                // Overall progress bar - CORRIGÉ
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Initialisation")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Text("\(currentStep + 1)/\(steps.count)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // CORRIGÉ - S'assurer que la valeur est dans les limites
                    let safeCurrentStep = max(0, min(currentStep, steps.count - 1))
                    let progressValue = Double(safeCurrentStep + 1)
                    let totalValue = Double(max(steps.count, 1)) // Éviter division par zéro
                    
                    ProgressView(value: progressValue, total: totalValue)
                        .progressViewStyle(LinearProgressViewStyle())
                        .scaleEffect(y: 2)
                }
                
                // Current step details - CORRIGÉ
                if currentStep >= 0 && currentStep < steps.count {
                    VStack(spacing: 12) {
                        HStack {
                            if steps[currentStep].isCompleted {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(steps[currentStep].title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text(steps[currentStep].description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                        )
                    }
                }
                
                // All steps preview
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(spacing: 8) {
                            Image(systemName: step.isCompleted ? "checkmark.circle.fill" :
                                  index == currentStep ? "circle.inset.filled" : "circle")
                                .foregroundColor(step.isCompleted ? .green :
                                               index == currentStep ? .blue : .secondary)
                                .font(.caption)
                            
                            Text(step.title)
                                .font(.caption2)
                                .foregroundColor(index <= currentStep ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(index <= currentStep ? Color.blue.opacity(0.1) : Color.clear)
                        )
                    }
                }
            }
            
            Spacer()
        }
        .padding(40)
    }
}

// MARK: - Preview

#Preview {
    StartupView()
}
