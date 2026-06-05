import SwiftUI

struct WeightSlidersView: View {
    @Binding var weights: [String: Double]
    let metadata: [WeightConfig]
    var isLocked: Bool
    var onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isLocked {
                HStack {
                    Image(systemName: "lock.fill")
                    Text("Sliders locked to official route paths")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.15))
                .foregroundColor(.yellow)
                .cornerRadius(8)
                .padding(.bottom, 4)
            } else {
                Text("Adjust sliders to influence path selection. Lower values attract routes; higher values penalize roads.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
            }

            ScrollView {
                VStack(spacing: 14) {
                    ForEach(metadata) { w in
                        sliderRow(for: w)
                            .disabled(isLocked)
                            .opacity(isLocked ? 0.6 : 1.0)
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 320)

            if !isLocked {
                Button(action: onReset) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset Defaults")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.emeraldGreen)
                    .cornerRadius(8)
                }
                .padding(.top, 4)
            }
        }
    }

    private func sliderRow(for w: WeightConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: w.iosIcon)
                        .foregroundColor(infraColor(for: w.key))
                        .frame(width: 20)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        Text(w.description)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text(String(format: "%.1fx", weights[w.key] ?? w.default))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(infraColor(for: w.key))
            }

            Slider(
                value: Binding(
                    get: { weights[w.key] ?? w.default },
                    set: { weights[w.key] = $0 }
                ),
                in: w.min...w.max,
                step: w.step
            )
            .tint(infraColor(for: w.key))
        }
        .padding(.vertical, 4)
    }

    private func infraColor(for key: String) -> Color {
        switch key {
        case "separated_path": return .emeraldGreen
        case "residential": return .emeraldGreen.opacity(0.8)
        case "sharrow_minor": return .amberGold
        case "sidewalk": return .cyanTeal
        case "busy_with_lane": return .deepOrange
        case "busy_with_sharrow": return .crimsonRed
        default: return .purpleAccent
        }
    }
}

// Custom Colors extension for consistent premium styling
extension Color {
    static let emeraldGreen = Color(red: 0.0, green: 0.9, blue: 0.46)
    static let crimsonRed = Color(red: 1.0, green: 0.09, blue: 0.27)
    static let amberGold = Color(red: 1.0, green: 0.7, blue: 0.0)
    static let cyanTeal = Color(red: 0.0, green: 0.9, blue: 1.0)
    static let deepOrange = Color(red: 1.0, green: 0.34, blue: 0.13)
    static let purpleAccent = Color(red: 0.7, green: 0.53, blue: 1.0)
}
