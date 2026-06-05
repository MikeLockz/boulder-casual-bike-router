import SwiftUI

struct WelcomeModalView: View {
    let onUseLocation: () -> Void
    let onExploreDemo: () -> Void

    var body: some View {
        ZStack {
            // Semi-transparent backdrop blur
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Pin icon
                ZStack {
                    Circle()
                        .fill(Color.emeraldGreen.opacity(0.15))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "map.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.emeraldGreen)
                }
                .padding(.top, 8)

                VStack(spacing: 8) {
                    Text("Explore Biking Boulder")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Plan the safest, lowest-stress bike routes using off-street paths and quiet residential corridors.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 16)
                }

                Text("Would you like to route starting from your current location?")
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                VStack(spacing: 12) {
                    Button(action: onUseLocation) {
                        HStack {
                            Image(systemName: "location.fill")
                            Text("Use My Current Location")
                        }
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.emeraldGreen)
                        .cornerRadius(10)
                    }

                    Button(action: onExploreDemo) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                            Text("Explore Demo Route")
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(white: 0.15))
                    .shadow(radius: 20)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 28)
        }
    }
}
