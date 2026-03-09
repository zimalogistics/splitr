import WidgetKit
import SwiftUI

// MARK: - Shared model (mirrors ContentView)

private struct WidgetField: Codable {
    let label: String
    let value: String
    let secondary: String?
}

private struct WidgetPreset: Codable {
    let name: String
    let fields: [WidgetField]
}

private let appGroupID = "group.com.zimalogistics.splitr"
private let widgetKey  = "splitr.widgetData"

// MARK: - Colors

private let bgBase  = Color(red: 0.05, green: 0.07, blue: 0.13)
private let accent  = Color(red: 0.25, green: 0.65, blue: 1.00)
private let textDim = Color(white: 0.45)

// MARK: - Timeline

private struct SplitEntry: TimelineEntry {
    let date: Date
    let preset: WidgetPreset?
}

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SplitEntry {
        SplitEntry(date: Date(), preset: WidgetPreset(
            name: "Marathon goal",
            fields: [
                WidgetField(label: "PACE", value: "8:30 /mi", secondary: "5:17 /km"),
                WidgetField(label: "DIST", value: "26.2 mi",  secondary: "42.2 km"),
                WidgetField(label: "TIME", value: "3:42:20",  secondary: nil),
            ]
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
        let isSmall     = family == .systemSmall
        let valueSize: CGFloat  = isSmall ? 17 : 20
        let secSize: CGFloat    = isSmall ? 13 : 16
        let labelSize: CGFloat  = 9
        let rowSpacing: CGFloat = isSmall ? 5 : 7
        let pad: CGFloat        = 10

        return VStack(alignment: .leading, spacing: rowSpacing) {
            if !preset.name.isEmpty {
                Text(preset.name)
                    .font(.system(size: isSmall ? 12 : 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .padding(.bottom, 1)
            }

            ForEach(preset.fields, id: \.label) { field in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    // Label
                    Text(field.label)
                        .font(.system(size: labelSize, weight: .bold, design: .rounded))
                        .foregroundStyle(textDim)
                        .frame(width: 34, alignment: .leading)

                    // Primary value
                    Text(field.value)
                        .font(.system(size: valueSize, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    // Secondary value — medium widget only
                    if !isSmall, let sec = field.secondary {
                        Text("·")
                            .font(.system(size: secSize, weight: .medium))
                            .foregroundStyle(textDim)
                        Text(sec)
                            .font(.system(size: secSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(pad)
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
