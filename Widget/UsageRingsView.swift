import SwiftUI
import WidgetKit

struct UsageRingsEntryView: View {
    let entry: UsageEntry

    var body: some View {
        UsageRingsView(entry: entry)
            .containerBackground(for: .widget) {
                WidgetBackground()
            }
    }
}

struct UsageRingsView: View {
    let entry: UsageEntry

    private var settings: DisplaySettings { entry.settings }

    var body: some View {
        Group {
            if entry.snapshot == nil {
                emptyState
            } else {
                grid
            }
        }
        .padding(12)
        .foregroundStyle(WidgetPalette.primary)
    }

    private var grid: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                RingCell(title: "5小时", window: entry.snapshot?.rolling, settings: settings)
                metaCell
            }
            HStack(spacing: 6) {
                RingCell(title: "周", window: entry.snapshot?.weekly, settings: settings)
                RingCell(title: "月", window: entry.snapshot?.monthly, settings: settings)
            }
        }
    }

    private var metaCell: some View {
        VStack(alignment: .center, spacing: 3) {
            Text("OpenCode")
                .font(.system(size: 10, weight: .bold, design: .rounded))
            HStack(spacing: 3) {
                Circle()
                    .fill(health.color)
                    .frame(width: 4.5, height: 4.5)
                Text(health.label)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(health.color)
            }
            Text(updatedText)
                .font(.system(size: 8, design: .rounded))
                .foregroundStyle(WidgetPalette.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var health: (color: Color, label: String) {
        guard entry.snapshot != nil else {
            return entry.errorMessage == nil
                ? (settings.normalColor.color, "同步中")
                : (settings.criticalColor.color, "未连接")
        }
        if entry.errorMessage != nil { return (settings.warningColor.color, "离线") }
        let windows = [entry.snapshot?.rolling, entry.snapshot?.weekly, entry.snapshot?.monthly]
        if windows.contains(where: { $0?.limited == true }) {
            return (settings.warningColor.color, "已限流")
        }
        return (settings.normalColor.color, "正常")
    }

    private var updatedText: String {
        guard let updatedAt = entry.updatedAt else { return "尚未更新" }
        return "更新 \(Self.timeFormatter.string(from: updatedAt))"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("尚未同步额度")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
            Text(entry.errorMessage ?? "启动 OpenCode 与额度 App 后自动刷新")
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct RingCell: View {
    let title: String
    let window: UsageWindow?
    let settings: DisplaySettings

    private var value: Double {
        guard let window else { return 0 }
        return settings.showRemaining
            ? window.remainingPercent
            : min(100, window.usedPercent)
    }

    private var ratio: CGFloat {
        CGFloat(max(0, min(1, value / 100)))
    }

    private var tint: Color {
        guard let window else { return MeterColor.gray.color }
        if window.limited || window.remainingPercent <= settings.criticalThreshold {
            return settings.criticalColor.color
        }
        if window.remainingPercent <= settings.warningThreshold {
            return settings.warningColor.color
        }
        return settings.normalColor.color
    }

    private var percentText: String {
        guard window != nil else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    private var resetText: String {
        guard let window else { return "—" }
        if window.limited { return "已限流" }
        return UsageWidgetView.compactReset(window.resetsAt)
    }

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                .foregroundStyle(WidgetPalette.secondary)
            ZStack {
                Circle()
                    .stroke(WidgetPalette.track, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: ratio)
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(percentText)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(window == nil ? WidgetPalette.tertiary : tint)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
            }
            .frame(width: 40, height: 40)
            .padding(.vertical, 1)
            Text(resetText)
                .font(.system(size: 8, design: .rounded))
                .foregroundStyle(WidgetPalette.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
