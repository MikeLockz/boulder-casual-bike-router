import SwiftUI

struct HistoryTabView: View {
    let pastRoutes: [PastRoute]
    @Environment(MapViewModel.self) private var viewModel
    @State private var selectedDetailRoute: PastRoute?
    
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
                    onDismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var mapPreview: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color.primaryMint.opacity(0.28), Color.forestDeep, Color.surfaceContainer],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Path { path in
                path.move(to: CGPoint(x: 34, y: 112))
                path.addCurve(to: CGPoint(x: 150, y: 58), control1: CGPoint(x: 76, y: 78), control2: CGPoint(x: 98, y: 154))
                path.addCurve(to: CGPoint(x: 302, y: 92), control1: CGPoint(x: 210, y: 0), control2: CGPoint(x: 236, y: 134))
            }
            .stroke(Color.mintGlow, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            .shadow(color: .mintGlow.opacity(0.6), radius: 10)

            Text("Preview")
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundColor(.forestDeep)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.primaryMint)
                .clipShape(Capsule())
                .padding(14)
        }
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.onSurfaceVariant.opacity(0.08), lineWidth: 1)
        )
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
            statCard(icon: "map", label: "Distance", value: String(format: "%.2f mi", route.distanceMiles))
            statCard(icon: "timer", label: "Duration", value: formatDuration(route.durationSeconds))
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
        guard let metersPerSecond = route.displayedAverageSpeedMetersPerSecond else { return "—" }
        return String(format: "%.1f mph", metersPerSecond * 2.23694)
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
