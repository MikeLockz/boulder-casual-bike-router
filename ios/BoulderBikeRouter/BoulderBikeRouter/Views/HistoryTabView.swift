import SwiftUI

struct HistoryTabView: View {
    let pastRoutes: [PastRoute]
    @Environment(MapViewModel.self) private var viewModel
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Adventure History")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.mintGlow)
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)
            .padding(.bottom, 16)
            .background(Color.surfaceDim)
            
            // Content
            VStack {
                if pastRoutes.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.onSurfaceVariant.opacity(0.4))
                        
                        Text("No Past Adventures Yet")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.onSurface)
                        
                        Text("Completed routes from active navigation mode will appear here.")
                            .font(.system(size: 14))
                            .foregroundColor(.onSurfaceVariant)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(pastRoutes) { route in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(route.name)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.onSurface)
                                    Spacer()
                                    Text(dateFormatter.string(from: route.date))
                                        .font(.system(size: 11))
                                        .foregroundColor(.onSurfaceVariant)
                                }
                                
                                HStack(spacing: 24) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("DISTANCE")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.onSurfaceVariant)
                                            .tracking(1)
                                        Text(String(format: "%.2f mi", route.distanceMiles))
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.primaryMint)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("DURATION")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.onSurfaceVariant)
                                            .tracking(1)
                                        Text(formatDuration(route.durationSeconds))
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.primaryMint)
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(Color.primaryMint)
                                            .frame(width: 6, height: 6)
                                        Text(route.startPointName)
                                            .font(.system(size: 12))
                                            .foregroundColor(.onSurfaceVariant)
                                            .lineLimit(1)
                                    }
                                    
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(Color.errorRose)
                                            .frame(width: 6, height: 6)
                                        Text(route.endPointName)
                                            .font(.system(size: 12))
                                            .foregroundColor(.onSurfaceVariant)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(16)
                            .background(Color.surfaceDim)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.onSurfaceVariant.opacity(0.05), lineWidth: 1)
                            )
                            .onTapGesture {
                                Task {
                                    await viewModel.selectHistoryRoute(route)
                                    NotificationCenter.default.post(name: NSNotification.Name("HistoryRouteSelected"), object: nil)
                                }
                            }
                            .listRowBackground(Color.forestDeep)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .background(Color.forestDeep)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.forestDeep)
        }
        .background(Color.forestDeep)
        .ignoresSafeArea(edges: .top)
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }
}
