import SwiftUI

struct RoutesTabView: View {
    @Bindable var viewModel: MapViewModel
    let onShowPlan: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Routes & Presets")
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
                    
                    // Section 1: Presets & Destinations
                    VStack(alignment: .leading, spacing: 12) {
                        Text("LOOP CONFIGURATIONS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.onSurfaceVariant)
                            .tracking(1)
                            .padding(.horizontal, 4)
                        
                        ForEach(viewModel.presets) { preset in
                            Button(action: {
                                withAnimation(.spring()) {
                                    viewModel.selectPreset(preset)
                                    if preset.routeType == "b180" || preset.routeType == "b360" {
                                        onShowPlan()
                                    }
                                }
                            }) {
                                HStack(spacing: 16) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(viewModel.selectedPresetName == preset.name ? Color.primaryMint.opacity(0.15) : Color.surfaceElevated)
                                            .frame(width: 44, height: 44)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(viewModel.selectedPresetName == preset.name ? Color.primaryMint.opacity(0.5) : Color.onSurfaceVariant.opacity(0.1), lineWidth: 1)
                                            )
                                        
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .foregroundColor(viewModel.selectedPresetName == preset.name ? .primaryMint : .onSurfaceVariant)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(preset.name)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(viewModel.selectedPresetName == preset.name ? .primaryMint : .onSurface)
                                        Text(preset.desc)
                                            .font(.system(size: 12))
                                            .foregroundColor(.onSurfaceVariant)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                    
                                    if viewModel.selectedPresetName == preset.name {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.primaryMint)
                                            .font(.title3)
                                    }
                                }
                                .padding(12)
                                .background(Color.surfaceDim)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.onSurfaceVariant.opacity(0.05), lineWidth: 1)
                                )
                            }
                        }
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
