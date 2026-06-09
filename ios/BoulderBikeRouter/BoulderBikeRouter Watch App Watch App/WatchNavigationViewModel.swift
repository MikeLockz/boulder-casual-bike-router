import Foundation
import Combine
import WatchConnectivity
import WatchKit

@MainActor
final class WatchNavigationViewModel: NSObject, ObservableObject {
    @Published private(set) var snapshot: WatchNavigationSnapshot = .inactive
    @Published private(set) var isConnectedToPhone = false

    private let decoder = JSONDecoder()
    private var session: WCSession?
    private var lastHapticRouteId: String?
    private var lastHapticInstruction: String?
    private var playedApproachHaptic = false
    private var playedImmediateHaptic = false

    override init() {
        super.init()
        decoder.dateDecodingStrategy = .iso8601

        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()

        applyPayload(session.receivedApplicationContext)
    }

    var isSnapshotStale: Bool {
        guard snapshot.status == .navigating || snapshot.status == .offRoute else {
            return false
        }
        return Date().timeIntervalSince(snapshot.updatedAt) > 30
    }

    private func applyPayload(_ payload: [String: Any]) {
        guard let data = payload["snapshot"] as? Data else { return }
        guard let decoded = try? decoder.decode(WatchNavigationSnapshot.self, from: data) else { return }

        let previous = snapshot
        snapshot = decoded
        updateConnectionState()
        playHapticIfNeeded(previous: previous, current: decoded)
    }

    private func updateConnectionState() {
        guard let session else {
            isConnectedToPhone = false
            return
        }
        isConnectedToPhone = session.activationState == .activated && session.isCompanionAppInstalled
    }

    private func playHapticIfNeeded(previous: WatchNavigationSnapshot, current: WatchNavigationSnapshot) {
        if current.routeId != lastHapticRouteId || current.instruction != lastHapticInstruction {
            lastHapticRouteId = current.routeId
            lastHapticInstruction = current.instruction
            playedApproachHaptic = false
            playedImmediateHaptic = false
        }

        switch current.status {
        case .offRoute where previous.status != .offRoute:
            WKInterfaceDevice.current().play(.failure)
        case .arrived where previous.status != .arrived:
            WKInterfaceDevice.current().play(.success)
        case .navigating:
            guard let meters = current.distanceToManeuverMeters else { return }
            if meters <= 30, !playedImmediateHaptic {
                playedImmediateHaptic = true
                WKInterfaceDevice.current().play(.directionDown)
            } else if meters <= 100, !playedApproachHaptic {
                playedApproachHaptic = true
                WKInterfaceDevice.current().play(.click)
            }
        default:
            break
        }
    }
}

extension WatchNavigationViewModel: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.updateConnectionState()
            self.applyPayload(session.receivedApplicationContext)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.updateConnectionState()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.applyPayload(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.applyPayload(message)
        }
    }
}
