import SwiftUI

struct SettingsTabView: View {
    @Bindable var viewModel: MapViewModel
    @State private var isAuthSheetPresented = false
    @State private var newProfileName = "Custom Routing Profile"
    @State private var offsetsJSON = "{}"

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

                        routeTuningProfileControls
                        
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
        .onAppear {
            offsetsJSON = encodeOffsets(viewModel.routeOffsets)
        }
        .onChange(of: viewModel.routeOffsets) { _, newOffsets in
            offsetsJSON = encodeOffsets(newOffsets)
        }
    }

    private var routeTuningProfileControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Routing Profile", selection: Binding(
                get: { viewModel.activeRouteTuningProfileId ?? "" },
                set: { selectedId in
                    if selectedId.isEmpty {
                        viewModel.applyRouteTuningProfile(nil)
                    } else if let profile = viewModel.routeTuningProfiles.first(where: { ($0.localId ?? $0.id) == selectedId || $0.id == selectedId }) {
                        viewModel.applyRouteTuningProfile(profile)
                    }
                }
            )) {
                Text("System Defaults").tag("")
                ForEach(viewModel.routeTuningProfiles) { profile in
                    Text("\(profile.isDefault ? "★ " : "")\(profile.name)")
                        .tag(profile.localId ?? profile.id)
                }
            }
            .pickerStyle(.menu)
            .tint(.primaryMint)

            HStack(spacing: 8) {
                TextField("Profile name", text: $newProfileName)
                    .textFieldStyle(.roundedBorder)
                Button("New") {
                    Task { await viewModel.createRouteTuningProfile(name: newProfileName) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.primaryMint)
            }

            Text("Offsets JSON")
                .font(.caption)
                .foregroundColor(.onSurfaceVariant)

            TextEditor(text: $offsetsJSON)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 72)
                .padding(6)
                .background(Color.black.opacity(0.18))
                .cornerRadius(8)

            HStack(spacing: 8) {
                Button("Save") {
                    if let offsets = decodeOffsets(offsetsJSON) {
                        viewModel.routeOffsets = offsets
                        Task { await viewModel.saveActiveRouteTuningProfile() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.primaryMint)

                Button("Default") {
                    Task { await viewModel.setActiveRouteTuningProfileDefault() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.activeRouteTuningProfileId == nil)

                Button("Delete") {
                    Task { await viewModel.deleteActiveRouteTuningProfile() }
                }
                .buttonStyle(.bordered)
                .tint(.errorRose)
                .disabled(viewModel.activeRouteTuningProfileId == nil)
            }
        }
        .padding(16)
        .background(Color.surfaceDim)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.onSurfaceVariant.opacity(0.05), lineWidth: 1)
        )
    }

    private func encodeOffsets(_ offsets: [String: Double]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: offsets, options: [.prettyPrinted]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private func decodeOffsets(_ string: String) -> [String: Double]? {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var offsets: [String: Double] = [:]
        for (key, value) in object {
            if let number = value as? NSNumber {
                offsets[key] = number.doubleValue
            }
        }
        return offsets
    }
}
