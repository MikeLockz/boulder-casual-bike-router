import SwiftUI
import CoreLocation

struct ControlPanelView: View {
    @Binding var isCollapsed: Bool
    @Binding var selectedPresetId: String?
    @Binding var selectedPlayground: Playground?
    
    // Dynamic config passed down from MapViewModel
    let presets: [PresetConfig]
    let weightsMetadata: [WeightConfig]
    let playgrounds: [Playground]
    
    @Binding var weights: [String: Double]
    let isWeightsLocked: Bool
    let onResetWeights: () -> Void
    @Binding var showOfficialRoutes: Bool
    
    // Route metrics & triggers
    let routeDistance: Double? // in miles
    let routeCost: Double?
    let maneuvers: [Maneuver]
    let onStartNavigation: () -> Void
    let onSelectPreset: (PresetConfig) -> Void
    
    // Accordion expand states
    @State private var expandPresets = true
    @State private var expandWeights = false
    @State private var expandLayers = false
    @State private var expandHelp = false

    var body: some View {
        VStack(spacing: 0) {
            // Drag grab bar + Header
            grabBarSection

            if !isCollapsed {
                ScrollView {
                    VStack(spacing: 16) {
                        // Section 1: Presets & Wayfinding
                        presetsDisclosure

                        Divider().background(Color.white.opacity(0.1))

                        // Section 2: Routing Weights
                        weightsDisclosure

                        Divider().background(Color.white.opacity(0.1))

                        // Section 3: Map Layers
                        layersDisclosure

                        Divider().background(Color.white.opacity(0.1))

                        // Section 4: Instruction
                        helpDisclosure

                        // Active route summary card
                        if routeDistance != nil {
                            routeSummaryCard
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            Color(white: 0.1)
                .opacity(0.85)
                .background(.ultraThinMaterial)
        )
        .cornerRadius(16, corners: [.topLeft, .topRight])
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: -5)
    }

    // MARK: - Subviews

    private var grabBarSection: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 40, height: 4)
                .padding(.top, 8)
                .onTapGesture {
                    withAnimation(.spring()) {
                        isCollapsed.toggle()
                    }
                }
            
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "bicycle")
                        .foregroundColor(.emeraldGreen)
                        .font(.title2)
                    Text("Biking Boulder")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                Spacer()
                
                Button(action: {
                    withAnimation(.spring()) {
                        isCollapsed.toggle()
                    }
                }) {
                    Image(systemName: isCollapsed ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var presetsDisclosure: some View {
        DisclosureGroup(isExpanded: $expandPresets) {
            VStack(alignment: .leading, spacing: 12) {
                // Preset List
                ForEach(presets) { preset in
                    Button(action: {
                        selectedPresetId = preset.name
                        onSelectPreset(preset)
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(selectedPresetId == preset.name ? .emeraldGreen : .white)
                                Text(preset.desc)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if selectedPresetId == preset.name {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.emeraldGreen)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedPresetId == preset.name ? Color.emeraldGreen.opacity(0.1) : Color.white.opacity(0.05))
                        )
                    }
                }

            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "map")
                    .foregroundColor(.emeraldGreen)
                Text("Presets & Destinations")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
    }

    private var weightsDisclosure: some View {
        DisclosureGroup(isExpanded: $expandWeights) {
            WeightSlidersView(
                weights: $weights,
                metadata: weightsMetadata,
                isLocked: isWeightsLocked,
                onReset: onResetWeights
            )
            .padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.emeraldGreen)
                Text("Routing Weights")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
    }

    private var layersDisclosure: some View {
        DisclosureGroup(isExpanded: $expandLayers) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $showOfficialRoutes) {
                    HStack(spacing: 8) {
                        Image(systemName: "map.fill")
                            .foregroundColor(.emeraldGreen)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Official Bike Routes")
                                .font(.subheadline)
                                .foregroundColor(.white)
                            Text("Overlay official Boulder bike paths")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .tint(.emeraldGreen)
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "layers.fill")
                    .foregroundColor(.emeraldGreen)
                Text("Map Layers")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
    }

    private var helpDisclosure: some View {
        DisclosureGroup(isExpanded: $expandHelp) {
            VStack(alignment: .leading, spacing: 8) {
                Text("• Long-press on the map to drop a Start pin.")
                Text("• Double-tap on the map to set a Destination pin.")
                Text("• Adjust sliders to avoid busy streets.")
                Text("• Press 'Navigate' for turn instructions.")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.emeraldGreen)
                Text("How to Use")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
    }

    private var routeSummaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ROUTE SUMMARY")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.emeraldGreen)
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading) {
                            Text("Distance")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f miles", routeDistance ?? 0))
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading) {
                            Text("Stress Cost")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f", routeCost ?? 0))
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                }
                Spacer()
                
                Button(action: onStartNavigation) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Navigate")
                    }
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(Color.emeraldGreen)
                    .cornerRadius(8)
                }
            }
            
            if !maneuvers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Turn-by-Turn Preview")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(0..<min(3, maneuvers.count), id: \.self) { idx in
                                HStack(spacing: 8) {
                                    Image(systemName: maneuvers[idx].iconName)
                                        .foregroundColor(.emeraldGreen)
                                        .font(.caption)
                                    Text(maneuvers[idx].shortInstruction)
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                            if maneuvers.count > 3 {
                                Text("+ \(maneuvers.count - 3) more maneuvers")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxHeight: 60)
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// RoundedCorner extension to style corners in SwiftUI
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
