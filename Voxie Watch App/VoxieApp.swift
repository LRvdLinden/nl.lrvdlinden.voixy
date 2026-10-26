import SwiftUI
import WatchKit

@main
struct VoxieApp: App {
    @WKApplicationDelegateAdaptor private var pushDelegate: VoxiePushDelegate
    @StateObject private var model = VoxieV2Model()

    var body: some Scene {
        WindowGroup {
            VoxieHomeView()
                .environmentObject(model)
                .onAppear {
                    pushDelegate.onToken = { token in
                        Task { await model.uploadPushToken(token) }
                    }
                    pushDelegate.registerNotifications()
                }
        }
    }
}
