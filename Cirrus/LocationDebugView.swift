import SwiftUI
import CoreLocation

struct LocationDebugView: View {
    @EnvironmentObject var viewModel: WeatherViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Statut de la géolocalisation")
                .font(.headline)
                .fontWeight(.semibold)
            
            // Statut actuel
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                
                Text(statusDescription)
                    .font(.subheadline)
                    .foregroundColor(statusColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(statusColor.opacity(0.1))
            )
            
            // Actions de test
            VStack(spacing: 8) {
                Button("🔑 Forcer la demande de permission") {
                    Task {
                        await viewModel.requestLocationPermissionForced()
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button("📍 Vérifier les services de localisation") {
                    checkLocationServices()
                }
                .buttonStyle(.bordered)
                
                if viewModel.locationPermissionStatus == .denied {
                    Button("⚙️ Ouvrir les Réglages") {
                        openSettings()
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            // Informations détaillées
            VStack(alignment: .leading, spacing: 4) {
                Text("Informations détaillées:")
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text("Services activés: \(CLLocationManager.locationServicesEnabled() ? "✅" : "❌")")
                    .font(.caption2)
                
                Text("Statut: \(viewModel.locationPermissionStatus.rawValue) (\(statusName))")
                    .font(.caption2)
                
                if let location = viewModel.userLocation {
                    Text("Position: \(location.coordinate.latitude, specifier: "%.4f"), \(location.coordinate.longitude, specifier: "%.4f")")
                        .font(.caption2)
                } else {
                    Text("Position: Aucune")
                        .font(.caption2)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
    
    private var statusIcon: String {
        switch viewModel.locationPermissionStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return "location.fill"
        case .denied, .restricted:
            return "location.slash"
        case .notDetermined:
            return "location.circle"
        @unknown default:
            return "location.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch viewModel.locationPermissionStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }
    
    private var statusDescription: String {
        switch viewModel.locationPermissionStatus {
        case .authorizedWhenInUse:
            return "Autorisé pendant l'utilisation"
        case .authorizedAlways:
            return "Toujours autorisé"
        case .denied:
            return "Accès refusé"
        case .restricted:
            return "Accès restreint"
        case .notDetermined:
            return "Permission non demandée"
        @unknown default:
            return "Statut inconnu"
        }
    }
    
    private var statusName: String {
        switch viewModel.locationPermissionStatus {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "authorizedAlways"
        case .authorizedWhenInUse: return "authorizedWhenInUse"
        @unknown default: return "unknown"
        }
    }
    
    private func checkLocationServices() {
        let enabled = CLLocationManager.locationServicesEnabled()
        print("📍 Location services enabled: \(enabled)")
        
        if !enabled {
            // Afficher une alerte pour activer les services de localisation
            print("❌ Location services are disabled system-wide")
        }
    }
    
    private func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}
