import SwiftUI

struct DrawerMenuView: View {
    @Binding var isDrawerOpen: Bool
    @Binding var selectedTab: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Profile Header Section
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    // Profile Avatar with Gradient Background
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [.forestDeep, .primaryContainer],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "person.fill")
                            .font(.title2)
                            .foregroundColor(.primaryMint)
                    }
                    .overlay(Circle().stroke(Color.primaryMint.opacity(0.3), lineWidth: 2))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Alex Wayfarer")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.onSurface)
                        
                        Text("PRO MEMBER")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.primaryMint)
                            .tracking(2)
                    }
                }
                
                // Progress Bar (75%)
                HStack(spacing: 12) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.surfaceElevated)
                                .frame(height: 6)
                            
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [.primaryMint, .mintGlow],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                                .frame(width: geo.size.width * 0.75, height: 6)
                        }
                    }
                    .frame(height: 6)
                    
                    Text("75%")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.onSurfaceVariant)
                }
            }
            .padding(.top, 60)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .background(Color.surfaceDim)
            
            Divider()
                .background(Color.onSurfaceVariant.opacity(0.1))
            
            // Menu Items
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    drawerButton(title: "Plan", icon: "safari.fill", index: 0)
                    drawerButton(title: "Routes", icon: "map.fill", index: 1)
                    drawerButton(title: "History", icon: "clock.fill", index: 2)
                    
                    // Non-tab navigation action placeholder
                    Button(action: {
                        isDrawerOpen = false
                    }) {
                        HStack(spacing: 16) {
                            Image(systemName: "bookmark.fill")
                                .foregroundColor(.onSurfaceVariant)
                                .frame(width: 24)
                            Text("Saved Places")
                                .font(.body)
                                .foregroundColor(.onSurfaceVariant)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    }
                    
                    Divider()
                        .background(Color.onSurfaceVariant.opacity(0.1))
                        .padding(.vertical, 8)
                    
                    drawerButton(title: "Settings", icon: "gearshape.fill", index: 3)
                    
                    Button(action: {
                        isDrawerOpen = false
                    }) {
                        HStack(spacing: 16) {
                            Image(systemName: "questionmark.circle.fill")
                                .foregroundColor(.onSurfaceVariant)
                                .frame(width: 24)
                            Text("Help & Support")
                                .font(.body)
                                .foregroundColor(.onSurfaceVariant)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 8)
            }
            .background(Color.surfaceDim)
            
            Spacer()
            
            // Footer Section
            Divider()
                .background(Color.onSurfaceVariant.opacity(0.1))
            
            HStack {
                Text("v2.4.0")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.onSurfaceVariant.opacity(0.6))
                
                Spacer()
                
                Button(action: {
                    isDrawerOpen = false
                }) {
                    HStack(spacing: 6) {
                        Text("Logout")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "power")
                            .font(.caption)
                    }
                    .foregroundColor(.errorRose)
                }
            }
            .padding(24)
            .background(Color.surfaceDim)
        }
        .frame(width: 280)
        .background(Color.surfaceDim)
        .ignoresSafeArea()
    }
    
    // Helper to render active/inactive drawer item
    private func drawerButton(title: String, icon: String, index: Int) -> some View {
        let isActive = selectedTab == index
        
        return Button(action: {
            selectedTab = index
            isDrawerOpen = false
        }) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .foregroundColor(isActive ? .primaryMint : .onSurfaceVariant)
                    .frame(width: 24)
                
                Text(title)
                    .font(.system(size: 16, weight: isActive ? .bold : .medium))
                    .foregroundColor(isActive ? .primaryMint : .onSurface)
                
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(isActive ? Color.primaryContainer.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
    }
}
