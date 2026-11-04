import SwiftUI
import WidgetKit

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task {
            completion(await loadEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            let entry = await loadEntry()
            // WidgetKit throttles refreshes; ask for the next slot rather than a tight loop.
            let minutes = max(1, entry.settings.refreshMinutes)
            let next = Date().addingTimeInterval(Double(minutes * 60))
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    /// The host app mirrors the local service credentials into the widget
    /// container, so the widget can fetch fresh numbers even when the host
    /// app is not running. Falls back to the last mirror when the service is
    /// unavailable or has moved to a new port.
    private func loadEntry() async -> UsageEntry {
        let state = SharedStore.load()
        let settings = state?.settings ?? .default
        guard let service = state?.service else {
            return UsageEntry(
                date: Date(),
                snapshot: state?.snapshot,
                updatedAt: state?.updatedAt,
                errorMessage: "启动 OpenCode 与额度 App 后自动刷新",
                settings: settings
            )
        }
        do {
            let snapshot = try await UsageClient.fetch(service: service)
            return UsageEntry(date: Date(), snapshot: snapshot, updatedAt: Date(), errorMessage: nil, settings: settings)
        } catch {
            let message = (error as? UsageError)?.message ?? error.localizedDescription
            return UsageEntry(
                date: Date(),
                snapshot: state?.snapshot,
                updatedAt: state?.updatedAt,
                errorMessage: message,
                settings: settings
            )
        }
    }
}

struct UsageWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        UsageWidgetView(entry: entry, family: family)
            .containerBackground(for: .widget) {
                WidgetBackground()
            }
    }
}

struct OpenCodeUsageWidget: Widget {
    private let kind = "OpenCodeUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            UsageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("OpenCode 额度")
        .description("显示 OpenCode Go 订阅 5 小时 / 周 / 月的剩余额度和重置时间。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct OpenCodeRingsWidget: Widget {
    private let kind = "OpenCodeRingsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            UsageRingsEntryView(entry: entry)
        }
        .configurationDisplayName("OpenCode 额度 · 圆环")
        .description("三个进度环，中间显示剩余百分比，环下显示重置倒计时。")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
