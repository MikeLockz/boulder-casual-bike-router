import SwiftUI

struct SettingsTabView: View {
    @Bindable var viewModel: MapViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.mintGlow)
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)
            .padding(.bottom, 16)
            .background(Color.surfaceDim)
            
            ScrollView {
                VStack(spacing: 24) {
                    
                    // Section 1: Navigation Preferences
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ROUTE CONFIGURATIONS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.onSurfaceVariant)
                            .tracking(1)
                            .padding(.horizontal, 4)
                        
                        VStack(spacing: 0) {
                            Toggle(isOn: $viewModel.avoidTolls) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Avoid Tolls")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.onSurface)
                                    Text("Reroute around toll roads when possible")
                                        .font(.system(size: 12))
                                        .foregroundColor(.onSurfaceVariant)
                                }
                            }
                            .padding(16)
                            .tint(.primaryMint)
                            
                            Divider()
                                .background(Color.onSurfaceVariant.opacity(0.1))
                                .padding(.horizontal, 16)
                            
                            Toggle(isOn: $viewModel.avoidHighways) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Avoid Highways")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.onSurface)
                                    Text("Prefer secondary or scenic roads")
                                        .font(.system(size: 12))
                                        .foregroundColor(.onSurfaceVariant)
                                }
                            }
                            .padding(16)
                            .tint(.primaryMint)
                        }
                        .background(Color.surfaceDim)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.onSurfaceVariant.opacity(0.05), lineWidth: 1)
                        )
                    }
                    
                    // Section 2: Account Security
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ACCOUNT & SECURITY")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.onSurfaceVariant)
                            .tracking(1)
                            .padding(.horizontal, 4)
                        
                        VStack(spacing: 0) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Face ID Authentication")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.onSurface)
                                    Text("Require Face ID to unlock saved locations")
                                        .font(.system(size: 12))
                                        .foregroundColor(.onSurfaceVariant)
                                }
                                Spacer()
                                Toggle("", isOn: .constant(true))
                                    .labelsHidden()
                                    .tint(.primaryMint)
                            }
                            .padding(16)
                            
                            Divider()
                                .background(Color.onSurfaceVariant.opacity(0.1))
                                .padding(.horizontal, 16)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Cloud Sync")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.onSurface)
                                    Text("Sync past routes & saved places via iCloud")
                                        .font(.system(size: 12))
                                        .foregroundColor(.onSurfaceVariant)
                                }
                                Spacer()
                                Toggle("", isOn: .constant(true))
                                    .labelsHidden()
                                    .tint(.primaryMint)
                            }
                            .padding(16)
                        }
                        .background(Color.surfaceDim)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.onSurfaceVariant.opacity(0.05), lineWidth: 1)
                        )
                    }
                }
                .padding(24)
            }
            .background(Color.forestDeep)
        }
        .background(Color.forestDeep)
        .ignoresSafeArea(edges: .top)
    }
}
