import SwiftUI

@main
struct VoxiePhoneApp: App {
    @StateObject private var model = VoxieV2Model()

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
