import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var viewModel = MapViewModel()
    @State private var selectedTab: Int = 0
    @State private var isDrawerOpen: Bool = false
    @State private var isNavigationActive: Bool = false
    @State private var historyRouteToPresent: PastRoute?
    @State private var isSessionAuthPresented = false
    @State private var showSessionExpiredAlert = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack(alignment: .leading) {
            // Tab View contents
            ZStack {
                switch selectedTab {
                case 0:
                    MainMapView(
                        viewModel: viewModel,
                        isDrawerOpen: $isDrawerOpen,
                        isNavigationActive: $isNavigationActive
                    )
                case 1:
                    RoutesTabView(viewModel: viewModel) {
                        selectTab(0)
                    }
                case 2:
                    HistoryTabView(routeToPresent: $historyRouteToPresent)
                case 3:
                    SettingsTabView(viewModel: viewModel)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isNavigationActive {
                customTabBar
            }
        }
        .environment(viewModel)
        .sheet(isPresented: $isSessionAuthPresented) {
            AuthView(viewModel: viewModel, initialMode: .signIn)
        }
        .alert("Session Expired", isPresented: $showSessionExpiredAlert) {
            Button("Sign In") {
                isSessionAuthPresented = true
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Sign in again to sync your saved routes and pending changes. Your routes remain saved on this iPhone.")
        }
        .onChange(of: viewModel.isSessionExpired) { _, isExpired in
            if isExpired {
                showSessionExpiredAlert = true
            }
        }
        .onAppear {
            viewModel.modelContext = modelContext
            showSessionExpiredAlert = viewModel.isSessionExpired
            Task {
                await viewModel.loadConfiguration()
            }
        }
        .onChange(of: viewModel.isSelectingHomeLocation) { _, isSelecting in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectTab(isSelecting ? 0 : 3)
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab != 0 {
                viewModel.clearHistorySelection()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HistoryRouteMapBack"))) { notification in
            if let route = notification.object as? PastRoute {
                historyRouteToPresent = route
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectTab(2)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HistoryRouteSelected"))) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectTab(0)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("HomeLocationSaved"))) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectTab(3)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AuthenticationExpired"))) { _ in
            viewModel.handleAuthenticationExpired()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TelemetryRouteEnded"))) { notification in
            guard let routeId = notification.object as? String else { return }
            Task {
                let completedRoute = viewModel.loadCompletedRouteFromLocalStore(routeId: routeId)
                historyRouteToPresent = completedRoute
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectTab(2)
                }

                // Reconcile cloud history after the local summary is already visible.
                await viewModel.loadHistory()
                if completedRoute == nil,
                   let recoveredRoute = viewModel.pastRoutes.first(where: { $0.id == routeId }) {
                    historyRouteToPresent = recoveredRoute
                }
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
        .background(
            Color.surfaceContainer
                .cornerRadius(12, corners: [.topLeft, .topRight])
                .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }
    
    private func tabBarItem(title: String, icon: String, index: Int) -> some View {
        let isActive = selectedTab == index
        
        return Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectTab(index)
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

    private func selectTab(_ index: Int) {
        if index != 0 {
            viewModel.clearHistorySelection()
        }
        selectedTab = index
    }
    
}
