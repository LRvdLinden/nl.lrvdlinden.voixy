import Foundation
import WatchConnectivity

/// Encrypted companion-device channel. Only the iPhone mints a Watch session.
///
/// Delivery paths, in order of preference:
/// 1. Watch → iPhone `sendMessage("requestSession")`. watchOS may wake the
///    iPhone app in the background; the iPhone mints a fresh Watch session with
///    its own Keychain credential and replies immediately.
/// 2. iPhone → Watch application context (latest state, delivered whenever the
///    Watch app next runs). Re-published when the Watch app gets installed.
final class VoxieWatchBridge: NSObject, WCSessionDelegate {
    static let shared = VoxieWatchBridge()

    var onSessionChanged: ((String?) -> Void)?
    var onVolumeChanged: ((Double) -> Void)?
    /// Human readable pairing state for the Watch setup screen.
    var onPairingStatus: ((String) -> Void)?
    /// Asked on the main queue before an automatic session request, so a
    /// Watch that is already signed in does not mint a new session every launch.
    var needsSession: (() -> Bool)?
    private var pendingContext: [String: Any]?
    private var activated = false

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil { session.delegate = self }
        if session.activationState == .activated {
            // Already active (e.g. second call): process what we already have.
            #if os(watchOS)
            processStoredContext(session)
            #else
            flush()
            #endif
            return
        }
        guard !activated else { return }
        activated = true
        session.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        guard activationState == .activated else { return }
        #if os(iOS)
        flush()
        #else
        // receivedApplicationContext is only reliable after activation completed.
        processStoredContext(session)
        requestSessionIfNeeded()
        #endif
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    /// Only a context that explicitly carries `configured` may change the login.
    /// A volume-only update must never sign the Watch out.
    private func apply(_ context: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            if let volume = context["playbackVolume"] as? Double {
                self?.onVolumeChanged?(volume)
            }
            if let configured = context["configured"] as? Bool {
                let token = configured ? context["watchToken"] as? String : nil
                self?.onSessionChanged?(token)
            }
        }
    }

    #if os(watchOS)
    private func processStoredContext(_ session: WCSession) {
        let context = session.receivedApplicationContext
        if !context.isEmpty { apply(context) }
    }

    /// Ask the iPhone for a fresh Watch session. Safe to call repeatedly.
    func requestSessionFromPhone() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            activate(); return
        }
        guard session.isCompanionAppInstalled else {
            status("Installeer Voxie op je iPhone")
            return
        }
        guard session.isReachable else {
            status("Open Voxie op je iPhone om te koppelen")
            return
        }
        status("Koppelen met iPhone…")
        session.sendMessage(["request": "watchSession"], replyHandler: { [weak self] reply in
            if let token = reply["watchToken"] as? String {
                DispatchQueue.main.async { self?.onSessionChanged?(token) }
                if let volume = reply["playbackVolume"] as? Double {
                    DispatchQueue.main.async { self?.onVolumeChanged?(volume) }
                }
            } else {
                self?.status(reply["error"] as? String ?? "Rond eerst de installatie op je iPhone af")
            }
        }, errorHandler: { [weak self] _ in
            self?.status("Open Voxie op je iPhone om te koppelen")
        })
    }

    /// Automatic variant: only when the Watch has no working session.
    func requestSessionIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.needsSession?() ?? true else { return }
            self.requestSessionFromPhone()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { requestSessionIfNeeded() }
    }

    func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        requestSessionIfNeeded()
    }

    private func status(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.onPairingStatus?(text) }
    }
    #endif

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
        // Merge into the last full context so the Watch keeps its session.
        var context = pendingContext ?? [:]
        context["playbackVolume"] = volume
        pendingContext = context
        flush()
    }

    private func flush() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let pendingContext else { return }
        // Throws when no Watch is paired or the Watch app is not installed yet;
        // sessionWatchStateDidChange retries once it is.
        try? WCSession.default.updateApplicationContext(pendingContext)
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        if session.isPaired && session.isWatchAppInstalled { flush() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        guard message["request"] as? String == "watchSession" else {
            replyHandler(["error": "Onbekend verzoek"]); return
        }
        Self.mintWatchSession { [weak self] token, error in
            if let token {
                let volume = UserDefaults.standard.object(forKey: "voxie.playbackVolume") as? Double ?? 1
                replyHandler(["watchToken": token, "playbackVolume": volume])
                DispatchQueue.main.async { self?.publish(token: token) }
            } else {
                replyHandler(["error": error ?? "Rond eerst de installatie op je iPhone af"])
            }
        }
    }

    /// Uses the iPhone's own Keychain session; works while the app is woken in
    /// the background by the Watch and does not need the SwiftUI model.
    static func mintWatchSession(_ completion: @escaping (String?, String?) -> Void) {
        guard let phoneToken = VoxieCredentialStore.load(), !phoneToken.isEmpty,
              let url = URL(string: SupabaseConfiguration.functionURL + "/v3/watch-session") else {
            completion(nil, "Log eerst in op je iPhone"); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(phoneToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200, let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = object["token"] as? String else {
                completion(nil, code == 409 ? "Kies eerst een gebruikersnaam op je iPhone"
                               : code == 401 ? "Log opnieuw in op je iPhone"
                               : "Voxie-server niet bereikbaar (\(code))")
                return
            }
            completion(token, nil)
        }.resume()
    }
    #endif
}
