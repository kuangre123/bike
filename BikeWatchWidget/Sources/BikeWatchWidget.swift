import WidgetKit
import SwiftUI

private let appGroup = "group.com.bochen.bike"

struct TodayEntry: TimelineEntry {
    let date: Date
    let minutes: Int
    let count: Int
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, minutes: 25, count: 2)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .after(Date().addingTimeInterval(1800))))
    }

    private func load() -> TodayEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        return TodayEntry(
            date: .now,
            minutes: defaults?.integer(forKey: "todayMinutes") ?? 0,
            count: defaults?.integer(forKey: "todayCount") ?? 0
        )
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("今日 \(entry.minutes) 分", systemImage: "bicycle")
        case .accessoryCircular:
            VStack(spacing: 1) {
                Image(systemName: "bicycle").font(.headline)
                Text("\(entry.minutes)").font(.caption2.weight(.bold))
            }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "bicycle").font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("今日运动").font(.caption2).foregroundStyle(.secondary)
                    Text("\(entry.minutes) 分 · \(entry.count) 次").font(.caption.weight(.bold))
                }
            }
        default:
            Image(systemName: "bicycle")
        }
    }
}

struct TodayComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayComplication", provider: TodayProvider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("今日运动")
        .description("快速查看今天的运动时长")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

@main
struct BikeWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayComplication()
    }
}
