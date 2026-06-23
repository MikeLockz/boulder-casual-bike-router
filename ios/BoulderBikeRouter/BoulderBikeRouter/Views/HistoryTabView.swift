import SwiftUI
import MapKit

struct HistoryTabView: View {
    @Binding var routeToPresent: PastRoute?
    @Environment(MapViewModel.self) private var viewModel
    @State private var selectedDetailRoute: PastRoute?
    
    private var pastRoutes: [PastRoute] {
        viewModel.pastRoutes
    }
    
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
                                        Text(endpointText(route.startNearName, pointName: route.startPointName, latitude: route.startLat, longitude: route.startLon))
                                            .font(.system(size: 12))
                                            .foregroundColor(.onSurfaceVariant)
                                            .lineLimit(1)
                                    }
                                    
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(Color.errorRose)
                                            .frame(width: 6, height: 6)
                                        Text(endpointText(route.endNearName, pointName: route.endPointName, latitude: route.endLat, longitude: route.endLon))
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
                                selectedDetailRoute = route
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.deleteHistoryRoute(route)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
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
        .sheet(item: $selectedDetailRoute) { route in
            RouteHistoryDetailView(route: route) {
                selectedDetailRoute = nil
            }
            .environment(viewModel)
        }
        .onAppear {
            presentPendingRouteIfNeeded()
        }
        .onChange(of: routeToPresent) { _, _ in
            presentPendingRouteIfNeeded()
        }
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        if seconds > 0 && seconds < 60 {
            return "<1 min"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }

    private func coordinateText(latitude: Double, longitude: Double) -> String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }

    private func endpointText(_ nearName: String?, pointName: String, latitude: Double, longitude: Double) -> String {
        if let nearName, !nearName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nearName
        }
        let trimmedPointName = pointName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPointName.isEmpty && trimmedPointName != "Start Point" && trimmedPointName != "Destination" {
            return trimmedPointName
        }
        return coordinateText(latitude: latitude, longitude: longitude)
    }

    private func presentPendingRouteIfNeeded() {
        guard let route = routeToPresent else { return }
        selectedDetailRoute = route
        routeToPresent = nil
    }
}

struct RouteHistoryDetailView: View {
    let route: PastRoute
    let onDismiss: () -> Void

    @Environment(MapViewModel.self) private var viewModel
    @State private var title: String
    @State private var notes: String
    @State private var isEditing = false
    @State private var isDeleteConfirmationPresented = false

    init(route: PastRoute, onDismiss: @escaping () -> Void) {
        self.route = route
        self.onDismiss = onDismiss
        _title = State(initialValue: route.name)
        _notes = State(initialValue: route.notes ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primaryMint)
                        .frame(width: 40, height: 40)
                        .background(Color.surfaceContainer)
                        .clipShape(Circle())
                }

                Text("Route Details")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.mintGlow)

                Spacer()

                Button {
                    Task {
                        if isEditing {
                            await viewModel.updateHistoryRoute(route, displayName: title, notes: notes)
                        }
                        isEditing.toggle()
                    }
                } label: {
                    Image(systemName: isEditing ? "checkmark" : "pencil")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(isEditing ? .primaryMint : .onSurfaceVariant)
                        .frame(width: 40, height: 40)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)
            .background(Color.surfaceDim)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    mapPreview
                    header
                    statsGrid
                    if isEditing || !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        notesEditor
                    }
                    actions
                }
                .padding(20)
            }
            .background(Color.forestDeep)
        }
        .background(Color.forestDeep)
        .confirmationDialog("Remove this route from history?", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
            Button("Remove from History", role: .destructive) {
                Task {
                    await viewModel.deleteHistoryRoute(route)
                    await MainActor.run {
                        onDismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var mapPreview: some View {
        Map(position: .constant(.region(previewRegion)), interactionModes: []) {
            ForEach(0..<previewRouteCoordinates.count, id: \.self) { pathIdx in
                MapPolyline(coordinates: previewRouteCoordinates[pathIdx])
                    .stroke(Color.mintGlow, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }

            if let startCoordinate {
                Annotation("Start", coordinate: startCoordinate, anchor: .bottom) {
                    previewMarker(color: .primaryMint)
                }
            }

            if let endCoordinate {
                Annotation("End", coordinate: endCoordinate, anchor: .bottom) {
                    previewMarker(color: .errorRose)
                }
            }
        }
        .frame(height: 170)
        .disabled(true)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.onSurfaceVariant.opacity(0.08), lineWidth: 1)
        )
        .task(id: route.id) {
            if viewModel.selectedHistoryRouteDetails?.id != route.id {
                await viewModel.preloadHistoryRouteDetails(route)
            }
        }
    }

    private var recordedCoordinates: [CLLocationCoordinate2D] {
        guard viewModel.selectedHistoryRouteDetails?.id == route.id else { return [] }
        return viewModel.selectedHistoryRouteDetails?.actualRouteCoordinatePath ?? []
    }

    private var startCoordinate: CLLocationCoordinate2D? {
        recordedCoordinates.first
    }

    private var endCoordinate: CLLocationCoordinate2D? {
        guard recordedCoordinates.count >= 2 else { return nil }
        return recordedCoordinates.last
    }

    private var previewRouteCoordinates: [[CLLocationCoordinate2D]] {
        recordedCoordinates.count >= 2 ? [recordedCoordinates] : []
    }

    private var previewRegion: MKCoordinateRegion {
        let fallbackCoordinate = CLLocationCoordinate2D(latitude: route.startLat, longitude: route.startLon)
        let coords = recordedCoordinates
        return RouteMapCamera.region(
            for: coords.isEmpty ? [fallbackCoordinate] : coords,
            screenSize: CGSize(width: UIScreen.main.bounds.width - 32, height: 170),
            insets: .previewCard
        ) ?? MKCoordinateRegion(
            center: coords.first ?? fallbackCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
        )
    }

    private func previewMarker(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .shadow(radius: 2)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Route title", text: $title)
                .disabled(!isEditing)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(isEditing ? .primaryMint : .onSurface)
                .textFieldStyle(.plain)

            Label(dateFormatter.string(from: route.date), systemImage: "calendar")
                .font(.system(size: 14))
                .foregroundColor(.onSurfaceVariant)
        }
    }

    private var statsGrid: some View {
        HStack(spacing: 10) {
            statCard(icon: "map", label: "Distance", value: String(format: "%.2f mi", detailDistanceMiles))
            statCard(icon: "timer", label: "Duration", value: formatDuration(detailDurationSeconds))
            statCard(icon: "speedometer", label: "Speed", value: averageSpeed)
        }
    }

    private var notesEditor: some View {
        TextEditor(text: $notes)
            .disabled(!isEditing)
            .frame(minHeight: 90)
            .scrollContentBackground(.hidden)
            .padding(10)
            .foregroundColor(isEditing ? .onSurface : .onSurfaceVariant)
            .background(Color.surfaceContainer.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isEditing ? Color.primaryMint.opacity(0.35) : Color.onSurfaceVariant.opacity(0.08), lineWidth: 1)
            )
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await viewModel.selectHistoryRoute(route)
                    NotificationCenter.default.post(name: NSNotification.Name("HistoryRouteSelected"), object: nil)
                    onDismiss()
                }
            } label: {
                Label("View on Map", systemImage: "map")
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(.primaryMint)

            Button(role: .destructive) {
                isDeleteConfirmationPresented = true
            } label: {
                Label("Remove from History", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.bordered)
            .tint(.errorRose)
        }
    }

    private var averageSpeed: String {
        let metersPerSecond = detailAverageSpeedMetersPerSecond
        return String(format: "%.1f mph", metersPerSecond * 2.23694)
    }

    private var currentDetails: DetailedRouteResponse? {
        guard viewModel.selectedHistoryRouteDetails?.id == route.id else { return nil }
        return viewModel.selectedHistoryRouteDetails
    }

    private var detailDistanceMeters: Double {
        currentDetails?.actualDistanceMeters ?? route.displayedDistanceMeters
    }

    private var detailDistanceMiles: Double {
        detailDistanceMeters / 1609.34
    }

    private var detailDurationSeconds: Int {
        Int((currentDetails?.actualDurationSeconds ?? route.displayedDurationSeconds).rounded())
    }

    private var detailAverageSpeedMetersPerSecond: Double {
        if let speed = currentDetails?.averageSpeed {
            return speed
        }
        return route.displayedAverageSpeedMetersPerSecond ?? 0
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }

    private func statCard(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.primaryMint)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.onSurfaceVariant)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 98)
        .background(Color.surfaceContainer.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.onSurfaceVariant.opacity(0.08), lineWidth: 1)
        )
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds > 0 && seconds < 60 {
            return "<1 min"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) min"
        }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

}
