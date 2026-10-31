import SwiftUI

@main
struct VoxieApp: App {
    @WKApplicationDelegateAdaptor(VoxiePushDelegate.self) private var pushDelegate
    @StateObject private var model = VoxieV2Model()
    @Environment(\.scenePhase) private var scenePhase
    @State private var didSetUp = false

    var body: some Scene {
        WindowGroup {
            VoxieHomeView()
                .environmentObject(model)
                // Lifecycle lives on the scene root, not on a conditional Group:
                // modifiers on a Group are applied to each branch, so every
                // screen change used to stop the network/audio loops.
                .task { setUpOnce() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.start()
                VoxieWatchBridge.shared.requestSessionIfNeeded()
            case .background:
                model.stop()
            default:
                break
            }
        }
    }

    @MainActor
    private func setUpOnce() {
        guard !didSetUp else { return }
        didSetUp = true
        // A Keychain session that did not come from this iPhone pairing flow
        // (older builds) is discarded; the iPhone hands over a fresh one.
        if !UserDefaults.standard.bool(forKey: "voxie.watchPairedViaPhone") {
            model.signOut()
        }
        let bridge = VoxieWatchBridge.shared
        let voxie = model
        bridge.onSessionChanged = { token in voxie.acceptWatchSession(token) }
        bridge.onVolumeChanged = { volume in voxie.setPlaybackVolume(volume) }
        bridge.onPairingStatus = { text in voxie.setPairingStatus(text) }
        bridge.needsSession = { !voxie.ready }
        VoxiePushDelegate.onToken = { token in voxie.setPushToken(token) }
        VoxiePushDelegate.onTalk = { sender, opened in
            voxie.handleTalkNotification(sender: sender, opened: opened)
        }
        bridge.activate()
        voxie.start()
    }
}
