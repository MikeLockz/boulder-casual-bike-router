import SwiftUI

struct NavigationOverlayView: View {
    let maneuver: Maneuver?
    let distanceToNext: String
    let remainingDistance: String
    let eta: String
    let isMuted: Bool
    let isSimulating: Bool
    let onMuteToggle: () -> Void
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Top banner: Current maneuver directives
            topBannerView
                .padding(.top, 50) // Adjust for status bar overlap

            Spacer()

            // Bottom bar: Trip stats and controls
            bottomStatsBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .edgesIgnoringSafeArea(.all)
    }

    // MARK: - Subviews

    private var topBannerView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Maneuver symbol icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primaryMint.opacity(0.15))
                        .frame(width: 52, height: 52)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primaryMint.opacity(0.3), lineWidth: 1))
                    
                    Image(systemName: maneuver?.iconName ?? "location.fill")
                        .font(.title2)
                        .foregroundColor(.primaryMint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(maneuver?.instruction ?? "Preparing navigation...")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.onSurface)
                        .lineLimit(2)
                    
                    if !distanceToNext.isEmpty {
                        Text("in \(distanceToNext)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primaryMint)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            
        }
        .background(Color.forestDeep)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primaryMint.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private var bottomStatsBar: some View {
        VStack(spacing: 12) {
            if isSimulating {
                HStack {
                    Image(systemName: "play.circle.fill")
                    Text("GPS Replay Simulation Active")
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Color.surfaceElevated.opacity(0.8))
            }

            HStack {
                // Trip ETA & Distance
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatDuration(remainingDistance))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.primaryMint)
                        Text("min")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primaryMint)
                    }
                    
                    HStack(spacing: 6) {
                        Text(remainingDistance)
                            .font(.system(size: 14))
                            .foregroundColor(.onSurfaceVariant)
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.onSurfaceVariant)
                        Text(eta)
                            .font(.system(size: 14))
                            .foregroundColor(.onSurfaceVariant)
                    }
                }
                
                Spacer()
                
                // Mute/Unmute
                Button(action: onMuteToggle) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                            .foregroundColor(.onSurface)
                            .font(.title3)
                    }
                }
                .padding(.trailing, 8)
                
                // Exit navigation button (End)
                Button(action: onExit) {
                    HStack(spacing: 6) {
                        Image(systemName: "close")
                            .font(.caption)
                        Text("End")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.onErrorContainer)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 22)
                    .background(Color.errorContainer)
                    .cornerRadius(28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(Color.errorRose.opacity(0.3), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, safeAreaBottomPadding)
        }
        .background(Color.surfaceContainer)
        .cornerRadius(16, corners: [.topLeft, .topRight])
        .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: -4)
    }
    
    // Help helper for duration estimation formatting from string
    private func formatDuration(_ text: String) -> String {
        // Simple extraction: e.g. "2.4 miles" -> 12 mins
        let val = text.replacingOccurrences(of: " miles", with: "").replacingOccurrences(of: " mile", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = Double(val) {
            return String(Int(d * 5))
        }
        return "8"
    }

    private var safeAreaBottomPadding: CGFloat {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let safeAreaInsets = windowScene.windows.first?.safeAreaInsets {
            return safeAreaInsets.bottom > 0 ? safeAreaInsets.bottom : 16
        }
        return 16
    }
}
