import WidgetKit
import SwiftUI

// MARK: - Shared model (mirrors WidgetPreset in ContentView)

private struct WidgetPreset: Codable {
    let name: String
    let line1: String
    let line2: String
}

private let appGroupID = "group.com.zimalogistics.splitr"
private let widgetKey  = "splitr.widgetData"

// MARK: - Colors (mirrors Splitr design tokens)

private let bgBase  = Color(red: 0.05, green: 0.07, blue: 0.13)
private let accent  = Color(red: 0.25, green: 0.65, blue: 1.00)
private let textDim = Color(white: 0.55)

// MARK: - Timeline

private struct SplitEntry: TimelineEntry {
    let date: Date
    let preset: WidgetPreset?
}

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SplitEntry {
        SplitEntry(date: Date(), preset: WidgetPreset(
            name: "Marathon pace",
            line1: "8:30 /mi  ·  5:17 /km",
            line2: "26.2 mi  ·  42.2 km  ·  3:42:20"
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (SplitEntry) -> Void) {
        completion(SplitEntry(date: Date(), preset: loadFirst()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SplitEntry>) -> Void) {
        let entry = SplitEntry(date: Date(), preset: loadFirst())
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func loadFirst() -> WidgetPreset? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: widgetKey),
              let presets = try? JSONDecoder().decode([WidgetPreset].self, from: data),
              let first = presets.first
        else { return nil }
        return first
    }
}

// MARK: - Views

private struct WidgetView: View {
    let entry: SplitEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let preset = entry.preset {
            filledView(preset: preset)
        } else {
            emptyView
        }
    }

    private func filledView(preset: WidgetPreset) -> some View {
        let hasName = !preset.name.isEmpty
        let line1Size: CGFloat = hasName
            ? (family == .systemSmall ? 16 : 19)
            : (family == .systemSmall ? 20 : 24)
        let line2Size: CGFloat = hasName
            ? (family == .systemSmall ? 12 : 14)
            : (family == .systemSmall ? 14 : 16)

        return VStack(alignment: .leading, spacing: 5) {
            if hasName {
                Text(preset.name)
                    .font(.system(size: family == .systemSmall ? 12 : 13,
                                  weight: .medium, design: .rounded))
                    .foregroundStyle(textDim)
                    .lineLimit(1)
            }

            // User inputs — large accent text
            Text(preset.line1)
                .font(.system(size: line1Size, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            // Derived values
            if !preset.line2.isEmpty {
                Text(preset.line2)
                    .font(.system(size: line2Size, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(family == .systemSmall ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "stopwatch.fill")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(accent.opacity(0.5))
            Text("Save a preset\nin Splitr")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(textDim)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Widget

@main
struct SplitrWidget: Widget {
    let kind = "SplitrWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            WidgetView(entry: entry)
                .containerBackground(bgBase, for: .widget)
        }
        .configurationDisplayName("Splitr")
        .description("Your most recent saved preset.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
