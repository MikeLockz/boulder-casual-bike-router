import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var viewModel = MapViewModel()
    @State private var selectedTab: Int = 0
    @State private var isDrawerOpen: Bool = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack(alignment: .leading) {
            // Tab View contents
            VStack(spacing: 0) {
                ZStack {
                    switch selectedTab {
                    case 0:
                        MainMapView(viewModel: viewModel, isDrawerOpen: $isDrawerOpen)
                    case 1:
                        RoutesTabView(viewModel: viewModel)
                    case 2:
                        HistoryTabView(pastRoutes: viewModel.pastRoutes)
                    case 3:
                        SettingsTabView(viewModel: viewModel)
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Custom Bottom Tab Bar
                customTabBar
            }
            .ignoresSafeArea(edges: .bottom)
            
            // Drawer Shim (Background Dim)
            if isDrawerOpen {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isDrawerOpen = false
                        }
                    }
                    .transition(.opacity)
            }
            
            // Drawer Side Menu
            if isDrawerOpen {
                DrawerMenuView(isDrawerOpen: $isDrawerOpen, selectedTab: $selectedTab)
                    .transition(.move(edge: .leading))
                    .zIndex(1)
            }
        }
        .environment(viewModel)
        .onAppear {
            viewModel.modelContext = modelContext
            Task {
                await viewModel.loadConfiguration()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HistoryRouteSelected"))) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = 0
            }
        }
        .onChange(of: viewModel.isSelectingHomeLocation) { _, isSelecting in
            if isSelecting {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedTab = 0
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HomeLocationSaved"))) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = 3
            }
        }
    }
    
    // Custom styled Bottom Navigation Bar matching PRD specs
    private var customTabBar: some View {
        HStack(spacing: 0) {
            tabBarItem(title: "Plan", icon: "safari.fill", index: 0)
            tabBarItem(title: "Routes", icon: "map.fill", index: 1)
            tabBarItem(title: "History", icon: "clock.fill", index: 2)
            tabBarItem(title: "Settings", icon: "gearshape.fill", index: 3)
        }
        .padding(.vertical, 8)
        .padding(.bottom, safeAreaBottomPadding)
        .background(Color.surfaceContainer)
        .cornerRadius(12, corners: [.topLeft, .topRight])
        .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: -4)
    }
    
    private func tabBarItem(title: String, icon: String, index: Int) -> some View {
        let isActive = selectedTab == index
        
        return Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = index
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(isActive ? .primaryMint : .onSurfaceVariant)
            .padding(.vertical, 4)
            .background(isActive ? Color.primaryContainer.opacity(0.1) : Color.clear)
            .cornerRadius(8)
            .padding(.horizontal, 8)
        }
    }
    
    // Helper to calculate safe area bottom inset
    private var safeAreaBottomPadding: CGFloat {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let safeAreaInsets = windowScene.windows.first?.safeAreaInsets {
            return safeAreaInsets.bottom > 0 ? safeAreaInsets.bottom - 8 : 12
        }
        return 12
    }
}
