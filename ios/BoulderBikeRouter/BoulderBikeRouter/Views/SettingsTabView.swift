import SwiftUI
import CoreLocation

struct SettingsTabView: View {
    @Bindable var viewModel: MapViewModel
    @State private var isAuthSheetPresented = false
    @State private var screen: SettingsScreen = .root
    @State private var editorProfile: RouteTuningProfile?
    @State private var draftName = "Custom Routing Profile"
    @State private var draftWeights: [String: Double] = [:]
    @State private var draftOffsets: [String: Double] = [:]
    @State private var deleteCandidate: RouteTuningProfile?
    @State private var showEditorDeleteConfirm = false

    private enum SettingsScreen {
        case root
        case weightsList
        case weightsEditor
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 24) {
                    switch screen {
                    case .root:
                        rootContent
                    case .weightsList:
                        weightsListContent
                    case .weightsEditor:
                        weightsEditorContent
                    }
                }
                .padding(24)
            }
            .background(Color.forestDeep)
        }
        .background(Color.forestDeep)
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $isAuthSheetPresented) {
            AuthView(viewModel: viewModel)
        }
        .alert("Delete Weight Setting?", isPresented: Binding(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let profile = deleteCandidate {
                    Task { await delete(profile) }
                }
                deleteCandidate = nil
            }
            Button("Cancel", role: .cancel) {
                deleteCandidate = nil
            }
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Delete Weight Setting?", isPresented: $showEditorDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let profile = editorProfile {
                    Task {
                        await delete(profile)
                        screen = .weightsList
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var header: some View {
        HStack {
            if screen != .root {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primaryMint)
                        .frame(width: 34, height: 34)
                }
            }

            Text(headerTitle)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.mintGlow)

            Spacer()

            if screen == .weightsList {
                Button(action: openNewEditor) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.forestDeep)
                        .frame(width: 34, height: 34)
                        .background(Color.primaryMint)
                        .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 60)
        .padding(.bottom, 16)
        .background(Color.surfaceDim)
    }

    private var headerTitle: String {
        switch screen {
        case .root: return "Settings"
        case .weightsList: return "Manage Weights"
        case .weightsEditor: return editorProfile == nil ? "New Weight Setting" : "Edit Weight Setting"
        }
    }

    private var rootContent: some View {
        VStack(spacing: 24) {
            accountSection
            if viewModel.isUserLoggedIn {
                accountSecuritySection
                homeSection
            }
            weightsNavSection
            layersPlaceholder
        }
    }

    private var accountSection: some View {
        settingsGroup(title: "ACCOUNT") {
            if viewModel.isUserLoggedIn, let email = viewModel.currentUserEmail {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Signed In As")
                            .font(.system(size: 12))
                            .foregroundColor(.onSurfaceVariant)
                        Text(email)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.onSurface)
                    }
                    Spacer()
                    Button("Sign Out") {
                        viewModel.signOut()
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.errorRose)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.errorRose.opacity(0.1))
                    .cornerRadius(6)
                }
                .padding(16)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sync past routes and saved places automatically by signing in or creating a free account.")
                        .font(.system(size: 12))
                        .foregroundColor(.onSurfaceVariant)
                        .lineSpacing(4)

                    Button(action: { isAuthSheetPresented = true }) {
                        Label("Sign In or Create Account", systemImage: "person.badge.key.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.forestDeep)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.primaryMint)
                            .cornerRadius(8)
                    }
                }
                .padding(16)
            }
        }
    }

    private var accountSecuritySection: some View {
        settingsGroup(title: "ACCOUNT & SECURITY") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cloud Sync")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.onSurface)
                    Text("Sync past routes & saved places via iCloud")
                        .font(.system(size: 12))
                        .foregroundColor(.onSurfaceVariant)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { viewModel.isCloudSyncEnabled },
                    set: { viewModel.isCloudSyncEnabled = $0 }
                ))
                .labelsHidden()
                .tint(.primaryMint)
            }
            .padding(16)
        }
    }

    private var homeSection: some View {
        settingsGroup(title: "HOME") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.primaryMint.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "house.fill")
                            .foregroundColor(.primaryMint)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Home Location")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.onSurface)
                        Text(homeLocationStatusText)
                            .font(.system(size: 12))
                            .foregroundColor(.onSurfaceVariant)
                    }

                    Spacer()
                }

                if let error = viewModel.homeLocationError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.errorRose)
                }

                HStack(spacing: 8) {
                    Button(action: { viewModel.beginHomeLocationSelection() }) {
                        Label("Set Home Location", systemImage: "mappin.and.ellipse")
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.primaryMint)
                    .disabled(viewModel.isSavingHomeLocation)

                    Button(action: { Task { await viewModel.deleteHomeLocation() } }) {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.errorRose)
                    .disabled(viewModel.homeLocation == nil || viewModel.isSavingHomeLocation)
                }
            }
            .padding(16)
        }
    }

    private var weightsNavSection: some View {
        settingsGroup(title: "WEIGHTS") {
            Button(action: { screen = .weightsList }) {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.primaryMint)
                        .frame(width: 24)
                    Text("Manage Weights")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.onSurface)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.onSurfaceVariant)
                }
                .padding(16)
            }
        }
    }

    private var layersPlaceholder: some View {
        EmptyView()
    }

    private var weightsListContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.routeTuningProfiles.isEmpty {
                Text("No custom weight settings yet.")
                    .font(.system(size: 13))
                    .foregroundColor(.onSurfaceVariant)
                    .frame(maxWidth: .infinity)
                    .padding(18)
                    .background(Color.surfaceDim)
                    .cornerRadius(12)
            } else {
                ForEach(viewModel.routeTuningProfiles) { profile in
                    HStack(spacing: 8) {
                        Button(action: { openEditor(profile) }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(profile.isDefault ? "★ " : "")\(profile.name)")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.onSurface)
                                    Text(profile.synced == true ? "Synced" : "Local changes")
                                        .font(.system(size: 12))
                                        .foregroundColor(.onSurfaceVariant)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.onSurfaceVariant)
                            }
                            .padding(16)
                            .background(Color.surfaceDim)
                            .cornerRadius(12)
                        }

                        Button(action: { deleteCandidate = profile }) {
                            Image(systemName: "trash")
                                .foregroundColor(.errorRose)
                                .frame(width: 42, height: 52)
                                .background(Color.surfaceDim)
                                .cornerRadius(12)
                        }
                    }
                }
            }
        }
    }

    private var weightsEditorContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("NAME")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.onSurfaceVariant)
                .tracking(1)
                .padding(.horizontal, 4)

            TextField("Weight setting name", text: $draftName)
                .textFieldStyle(.roundedBorder)

            WeightSlidersView(
                weights: $draftWeights,
                metadata: viewModel.weightsMetadata,
                isLocked: false,
                onReset: { draftWeights = viewModel.defaultRouteWeights() }
            )
            .padding(16)
            .background(Color.surfaceDim)
            .cornerRadius(12)

            HStack(spacing: 8) {
                Button("Cancel") {
                    screen = .weightsList
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("Save") {
                    Task { await saveEditor() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.primaryMint)
                .frame(maxWidth: .infinity)

                if editorProfile != nil {
                    Button(action: { showEditorDeleteConfirm = true }) {
                        Image(systemName: "trash")
                            .frame(width: 42)
                    }
                    .buttonStyle(.bordered)
                    .tint(.errorRose)
                }
            }
        }
    }

    private func settingsGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.onSurfaceVariant)
                .tracking(1)
                .padding(.horizontal, 4)

            content()
                .background(Color.surfaceDim)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.onSurfaceVariant.opacity(0.05), lineWidth: 1)
                )
        }
    }

    private func back() {
        switch screen {
        case .root:
            break
        case .weightsList:
            screen = .root
        case .weightsEditor:
            screen = .weightsList
        }
    }

    private func openNewEditor() {
        editorProfile = nil
        draftName = "Custom Routing Profile"
        draftWeights = viewModel.defaultRouteWeights()
        draftOffsets = [:]
        screen = .weightsEditor
    }

    private func openEditor(_ profile: RouteTuningProfile) {
        editorProfile = profile
        draftName = profile.name
        draftWeights = profile.weights
        draftOffsets = profile.offsets
        screen = .weightsEditor
    }

    @MainActor
    private func saveEditor() async {
        if let profile = editorProfile {
            await viewModel.saveRouteTuningProfile(
                id: profile.localId ?? profile.id,
                name: draftName,
                weights: draftWeights,
                offsets: draftOffsets
            )
        } else {
            await viewModel.createRouteTuningProfile(
                name: draftName,
                weights: draftWeights,
                offsets: draftOffsets
            )
        }
        screen = .weightsList
    }

    @MainActor
    private func delete(_ profile: RouteTuningProfile) async {
        await viewModel.deleteRouteTuningProfile(id: profile.localId ?? profile.id)
    }

    private var homeLocationStatusText: String {
        guard let home = viewModel.homeLocation else {
            return "Home has not been set yet."
        }
        return String(format: "%.6f, %.6f", home.lat, home.lng)
    }
}
