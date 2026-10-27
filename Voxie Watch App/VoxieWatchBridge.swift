import Foundation
import WatchConnectivity

/// Encrypted companion-device channel. Only the iPhone publishes a Watch session.
final class VoxieWatchBridge: NSObject, WCSessionDelegate {
    static let shared = VoxieWatchBridge()

    var onSessionChanged: ((String?) -> Void)?
    var onVolumeChanged: ((Double) -> Void)?
    private var pendingContext: [String: Any]?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        #if os(watchOS)
        if !session.receivedApplicationContext.isEmpty {
            self.session(session, didReceiveApplicationContext: session.receivedApplicationContext)
        }
        #endif
    }

    #if os(iOS)
    func publish(token: String?) {
        if let token {
            pendingContext = ["configured": true, "watchToken": token,
                              "playbackVolume": UserDefaults.standard.object(forKey: "voxie.playbackVolume") as? Double ?? 1]
        } else {
            pendingContext = ["configured": false]
        }
        flush()
    }

    func publishVolume(_ volume: Double) {
        var context = pendingContext ?? WCSession.default.applicationContext
        context["playbackVolume"] = volume
        pendingContext = context
        flush()
    }

    private func flush() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let pendingContext else { return }
        try? WCSession.default.updateApplicationContext(pendingContext)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        #if os(iOS)
        if activationState == .activated { flush() }
        #endif
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let token = applicationContext["configured"] as? Bool == true
            ? applicationContext["watchToken"] as? String : nil
        DispatchQueue.main.async { [weak self] in
            if let volume = applicationContext["playbackVolume"] as? Double {
                self?.onVolumeChanged?(volume)
            }
            self?.onSessionChanged?(token)
        }
    }
}
