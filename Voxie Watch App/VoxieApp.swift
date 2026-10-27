import SwiftUI

@main
struct VoxieApp: App {
    @StateObject private var model = VoxieV2Model()

    var body: some Scene {
        WindowGroup {
            VoxieHomeView()
                .environmentObject(model)
        }
    }
}
