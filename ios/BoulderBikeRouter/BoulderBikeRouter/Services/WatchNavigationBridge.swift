import Foundation
import WatchConnectivity

@MainActor
final class WatchNavigationBridge: NSObject {
    static let shared = WatchNavigationBridge()

    private let encoder = JSONEncoder()
    private var session: WCSession?
    private var lastSnapshot: WatchNavigationSnapshot?
    private var lastSentAt: Date?

    private override init() {
        super.init()
        encoder.dateEncodingStrategy = .iso8601

        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
    }

    func send(_ snapshot: WatchNavigationSnapshot, force: Bool = false) {
        guard let session else { return }
        guard session.activationState == .activated else { return }
        guard session.isPaired, session.isWatchAppInstalled else { return }
        guard shouldSend(snapshot, force: force) else { return }
        guard let data = try? encoder.encode(snapshot) else { return }

        let payload: [String: Any] = ["snapshot": data]
        try? session.updateApplicationContext(payload)

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }

        lastSnapshot = snapshot
        lastSentAt = Date()
    }

    private func shouldSend(_ snapshot: WatchNavigationSnapshot, force: Bool) -> Bool {
        guard !force else { return true }
        guard let lastSnapshot else { return true }

        if snapshot.status != lastSnapshot.status { return true }
        if snapshot.routeId != lastSnapshot.routeId { return true }
        if snapshot.instruction != lastSnapshot.instruction { return true }
        if snapshot.maneuverIconName != lastSnapshot.maneuverIconName { return true }
        if snapshot.remainingDistanceText != lastSnapshot.remainingDistanceText { return true }
        if snapshot.etaText != lastSnapshot.etaText { return true }

        let currentDistance = snapshot.distanceToManeuverMeters ?? .infinity
        let lastDistance = lastSnapshot.distanceToManeuverMeters ?? .infinity
        if abs(currentDistance - lastDistance) >= 15.0 { return true }

        if let lastSentAt, Date().timeIntervalSince(lastSentAt) < 5.0 {
            return false
        }

        return true
    }
}

extension WatchNavigationBridge: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
