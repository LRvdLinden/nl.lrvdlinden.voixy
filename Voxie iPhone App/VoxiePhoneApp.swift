import SwiftUI

/// The iPhone and iPad companion manages the user's account, friends and Watch
/// preferences. Audio capture, playback and walkie-talkie controls live only in
/// the watchOS app.
@main
struct VoxiePhoneApp: App {
    @StateObject private var model = VoxieV2Model()

    init() {
        // Activate before any view exists: the Watch can wake this app in the
        // background with a session request, and then no view's onAppear runs.
        VoxieWatchBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            VoxiePhoneHomeView()
                .environmentObject(model)
                .onOpenURL { url in model.openSharedProfile(url) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { model.openSharedProfile(url) }
                }
        }
    }
}
