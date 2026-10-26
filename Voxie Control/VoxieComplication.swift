import SwiftUI
import WidgetKit

struct VoxieComplicationEntry: TimelineEntry {
    let date: Date
}

struct VoxieComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> VoxieComplicationEntry {
        VoxieComplicationEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (VoxieComplicationEntry) -> Void) {
        completion(VoxieComplicationEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VoxieComplicationEntry>) -> Void) {
        completion(Timeline(entries: [VoxieComplicationEntry(date: .now)], policy: .never))
    }
}

struct VoxieComplicationView: View {
    @Environment(\.widgetFamily) private var family
    private let yellow = Color(red: 1, green: 0.85, blue: 0)

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                HStack(spacing: 7) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 25))
                        .foregroundStyle(yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VOXIE").font(.system(size: 12, weight: .black))
                        Text("Tik om te praten").font(.system(size: 10))
                    }
                    Spacer(minLength: 0)
                }
            case .accessoryInline:
                Label("Voxie", systemImage: "waveform")
            case .accessoryCorner:
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(yellow)
                    .widgetLabel("Voxie")
            default:
                VStack(spacing: 1) {
                    Image(systemName: "waveform")
                        .font(.system(size: 21, weight: .heavy))
                        .foregroundStyle(yellow)
                    Text("VOXIE")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                }
            }
        }
        .containerBackground(.clear, for: .widget)
        .accessibilityLabel("Open Voxie Walkietalkie")
    }
}

struct VoxieComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nl.lrvdlinden.Voxie.complication", provider: VoxieComplicationProvider()) { _ in
            VoxieComplicationView()
        }
        .configurationDisplayName("Voxie Walkietalkie")
        .description("Open Voxie vanaf je Apple Watch-wijzerplaat.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
