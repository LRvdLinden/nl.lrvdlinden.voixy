import AppIntents
import SwiftUI
import WidgetKit

// Supported in Apple Watch Control Center, Smart Stack and Ultra Action Button
// on watchOS 26+. This control opens Voxie; it does not start microphone capture.
@main
struct VoxieControlBundle: WidgetBundle {
    var body: some Widget {
        VoxieOpenControl()
        VoxieComplication()
    }
}

struct VoxieOpenControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "nl.lrvdlinden.Voxie.open") {
            ControlWidgetButton(action: OpenVoxieIntent()) {
                Label("Voxie", systemImage: "waveform")
            }
        }
        .displayName("Voxie")
        .description("Open je Walkietalkie en praat met een vriend.")
    }
}

struct OpenVoxieIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Voxie"
    static var description = IntentDescription("Open Voxie op je Apple Watch.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult { .result() }
}
