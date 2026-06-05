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
        .edgesIgnoringSafeArea(.all)
    }

    // MARK: - Subviews

    private var topBannerView: some View {
        HStack(spacing: 16) {
            // Maneuver symbol icon
            ZStack {
                Circle()
                    .fill(Color.emeraldGreen.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: maneuver?.iconName ?? "location.fill")
                    .font(.title2)
                    .foregroundColor(.emeraldGreen)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(maneuver?.instruction ?? "Preparing navigation...")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                if !distanceToNext.isEmpty {
                    Text(distanceToNext)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.emeraldGreen)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.1))
                .opacity(0.95)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
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
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.amberGold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Color.amberGold.opacity(0.15))
            }

            HStack {
                // Trip ETA & Distance
                VStack(alignment: .leading, spacing: 2) {
                    Text(eta)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text(remainingDistance)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Mute/Unmute
                Button(action: onMuteToggle) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                            .foregroundColor(.white)
                            .font(.title3)
                    }
                }
                
                // Exit navigation button
                Button(action: onExit) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("End")
                    }
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(Color.crimsonRed)
                    .cornerRadius(10)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(
            Color(white: 0.1)
                .opacity(0.95)
                .background(.ultraThinMaterial)
        )
        .cornerRadius(16, corners: [.topLeft, .topRight])
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: -5)
    }
}
