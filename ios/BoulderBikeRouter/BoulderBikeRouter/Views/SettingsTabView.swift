import SwiftUI

struct SettingsTabView: View {
    @Bindable var viewModel: MapViewModel
    @State private var isAuthSheetPresented = false

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
                    
                    // Section 1: Account
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ACCOUNT")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.onSurfaceVariant)
                            .tracking(1)
                            .padding(.horizontal, 4)
                        
                        VStack(spacing: 0) {
                            if viewModel.isUserLoggedIn, let email = viewModel.currentUserEmail {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Signed In As")
                                            .font(.system(size: 12))
                                            .foregroundColor(.onSurfaceVariant)
                                        Text(email)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.onSurface)
                                    }
                                    Spacer()
                                    Button(action: {
                                        viewModel.signOut()
                                    }) {
                                        Text("Sign Out")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.errorRose)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(Color.errorRose.opacity(0.1))
                                            .cornerRadius(6)
                                    }
                                }
                                .padding(16)
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Sync past routes and saved places automatically by signing in or creating a free account.")
                                        .font(.system(size: 12))
                                        .foregroundColor(.onSurfaceVariant)
                                        .lineSpacing(4)
                                    
                                    Button(action: {
                                        isAuthSheetPresented = true
                                    }) {
                                        HStack {
                                            Image(systemName: "person.badge.key.fill")
                                            Text("Sign In or Create Account")
                                                .font(.system(size: 14, weight: .bold))
                                        }
                                        .foregroundColor(.forestDeep)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.primaryMint)
                                        .cornerRadius(8)
                                    }
                                }
                                .padding(16)
                            }
                        }
                        .background(Color.surfaceDim)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.onSurfaceVariant.opacity(0.05), lineWidth: 1)
                        )
                    }
                    
                    if viewModel.isUserLoggedIn {
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
                                        Text("Cloud Sync")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.onSurface)
                                        Text("Sync past routes & saved places via iCloud")
                                            .font(.system(size: 12))
                                            .foregroundColor(.onSurfaceVariant)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { viewModel.isCloudSyncEnabled },
                                        set: { viewModel.isCloudSyncEnabled = $0 }
                                    ))
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
                    
                    // Section 3: Routing Weights and Offsets
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ROUTING WEIGHTS AND OFFSETS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.onSurfaceVariant)
                            .tracking(1)
                            .padding(.horizontal, 4)
                        
                        WeightSlidersView(
                            weights: $viewModel.weights,
                            metadata: viewModel.weightsMetadata,
                            isLocked: viewModel.isWeightsLocked,
                            onReset: { viewModel.resetWeights() }
                        )
                        .padding(16)
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
        .sheet(isPresented: $isAuthSheetPresented) {
            AuthView(viewModel: viewModel)
        }
    }
}
