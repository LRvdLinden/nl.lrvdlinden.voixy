import SwiftUI

@main
struct VoxiePhoneApp: App {
    @StateObject private var model = VoxieV2Model()

    var body: some Scene {
        WindowGroup {
            VoxiePhoneHomeView()
                .environmentObject(model)
        }
    }
}
