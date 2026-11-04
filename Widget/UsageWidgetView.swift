import SwiftUI
import WidgetKit

// MARK: - Entry

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let updatedAt: Date?
    let errorMessage: String?
    let settings: DisplaySettings

    static var placeholder: UsageEntry {
        let now = Date()
        return UsageEntry(
            date: now,
            snapshot: UsageSnapshot(
                rolling: UsageWindow(usedPercent: 0, limited: false, resetsAt: now.addingTimeInterval(2.4 * 3600)),
                weekly: UsageWindow(usedPercent: 24, limited: false, resetsAt: now.addingTimeInterval(4.9 * 86400)),
                monthly: UsageWindow(usedPercent: 63, limited: false, resetsAt: now.addingTimeInterval(26 * 86400)),
                usageURL: URL(string: "https://opencode.ai/console"),
                workspaceName: "Default"
            ),
            updatedAt: now,
            errorMessage: nil,
            settings: .default
        )
    }
}

// MARK: - Palette

enum WidgetPalette {
    static let green = Color(red: 0.32, green: 0.85, blue: 0.56)
    static let amber = Color(red: 0.98, green: 0.73, blue: 0.30)
    static let red = Color(red: 0.94, green: 0.40, blue: 0.40)
    static let gray = Color(red: 0.62, green: 0.65, blue: 0.72)

    static let primary = Color.white.opacity(0.94)
    static let secondary = Color.white.opacity(0.58)
    static let tertiary = Color.white.opacity(0.40)
    static let track = Color.white.opacity(0.13)
    static let card = Color.white.opacity(0.06)
}

struct WidgetBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.15, green: 0.17, blue: 0.23),
                Color(red: 0.07, green: 0.08, blue: 0.11)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Health

private enum WidgetHealth {
    case ok, limited, stale, offline, loading

    var color: Color {
        switch self {
        case .ok: return WidgetPalette.green
        case .limited, .stale: return WidgetPalette.amber
        case .offline: return WidgetPalette.red
        case .loading: return WidgetPalette.gray
        }
    }

    var label: String {
        switch self {
        case .ok: return "正常"
        case .limited: return "已限流"
        case .stale: return "离线"
        case .offline: return "未连接"
        case .loading: return "同步中"
        }
    }
}

// MARK: - Widget view

struct UsageWidgetView: View {
    let entry: UsageEntry
    let family: WidgetFamily

    private var settings: DisplaySettings { entry.settings }

    private var health: WidgetHealth {
        guard let snapshot = entry.snapshot else {
            return entry.errorMessage == nil ? .loading : .offline
        }
        if entry.errorMessage != nil { return .stale }
        let windows = [snapshot.rolling, snapshot.weekly, snapshot.monthly]
        if windows.contains(where: { $0?.limited == true }) { return .limited }
        return .ok
    }

    var body: some View {
        Group {
            if family == .systemSmall {
                smallLayout
            } else {
                mediumLayout
            }
        }
        .padding(14)
        .foregroundStyle(WidgetPalette.primary)
    }

    // MARK: small

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            smallHeader
            if entry.snapshot == nil {
                Spacer(minLength: 0)
                emptyState
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 8) {
                    compactRow("5h", entry.snapshot?.rolling)
                    compactRow("周", entry.snapshot?.weekly)
                    compactRow("月", entry.snapshot?.monthly)
                }
                Spacer(minLength: 0)
                if let updatedAt = entry.updatedAt {
                    HStack(spacing: 3) {
                        Text(entry.errorMessage != nil ? "离线 ·" : "更新于")
                        Text(updatedAt, style: .time)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 8, design: .rounded))
                    .foregroundStyle(WidgetPalette.tertiary)
                }
            }
        }
    }

    private var smallHeader: some View {
        HStack(spacing: 5) {
            Text("OpenCode")
                .font(.system(size: 11, weight: .bold, design: .rounded))
            Spacer(minLength: 2)
            Circle()
                .fill(health.color)
                .frame(width: 5, height: 5)
            Text(health.label)
                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                .foregroundStyle(health.color)
        }
    }

    private func compactRow(_ label: String, _ window: UsageWindow?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(WidgetPalette.secondary)
                .frame(width: 18, alignment: .leading)
            Text(percentText(window))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(window == nil ? WidgetPalette.tertiary : tint(window))
            Spacer(minLength: 2)
            resetLabel(window, compact: true)
        }
    }

    // MARK: medium

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 9) {
            mediumHeader
            if entry.snapshot == nil {
                Spacer(minLength: 0)
                emptyState
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 8) {
                    wideRow("5 小时", entry.snapshot?.rolling)
                    wideRow("周限额", entry.snapshot?.weekly)
                    wideRow("月限额", entry.snapshot?.monthly)
                }
                Spacer(minLength: 0)
                if let updatedAt = entry.updatedAt {
                    footer(updatedAt)
                }
            }
        }
    }

    private var mediumHeader: some View {
        HStack(spacing: 6) {
            Text("OpenCode")
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Text("Go 订阅额度")
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(WidgetPalette.tertiary)
            Spacer(minLength: 4)
            Circle()
                .fill(health.color)
                .frame(width: 5.5, height: 5.5)
            Text(health.label)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(health.color)
        }
    }

    private func wideRow(_ title: String, _ window: UsageWindow?) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(WidgetPalette.secondary)
                .frame(width: 46, alignment: .leading)
            Text(percentText(window))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(window == nil ? WidgetPalette.tertiary : tint(window))
                .frame(width: 46, alignment: .leading)
            bar(window)
            resetLabel(window, compact: false)
                .frame(width: 66, alignment: .trailing)
        }
    }

    private func bar(_ window: UsageWindow?) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetPalette.track)
                if let window {
                    let ratio = max(0, min(1, displayedValue(window) / 100))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint(window).opacity(0.7), tint(window)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(ratio <= 0 ? 0 : 3, geometry.size.width * ratio))
                }
            }
        }
        .frame(height: 5.5)
    }

    // MARK: shared

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("尚未同步额度")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            Text(entry.errorMessage ?? "启动 OpenCode 与额度 App 后自动刷新")
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footer(_ updatedAt: Date) -> some View {
        HStack(spacing: 4) {
            if entry.errorMessage != nil {
                Text("离线 · 数据为")
            } else {
                Text("更新于")
            }
            Text(updatedAt, style: .time)
            Spacer(minLength: 0)
            Text("每 \(settings.refreshMinutes) 分钟刷新")
        }
        .font(.system(size: 8.5, design: .rounded))
        .foregroundStyle(WidgetPalette.tertiary)
    }

    private func displayedValue(_ window: UsageWindow?) -> Double {
        guard let window else { return 0 }
        return settings.showRemaining ? window.remainingPercent : min(100, window.usedPercent)
    }

    private func percentText(_ window: UsageWindow?) -> String {
        guard let window else { return "—" }
        return "\(Int(displayedValue(window).rounded()))%"
    }

    private func tint(_ window: UsageWindow?) -> Color {
        guard let window else { return MeterColor.gray.color }
        if window.limited || window.remainingPercent <= settings.criticalThreshold {
            return settings.criticalColor.color
        }
        if window.remainingPercent <= settings.warningThreshold {
            return settings.warningColor.color
        }
        return settings.normalColor.color
    }

    private func resetLabel(_ window: UsageWindow?, compact: Bool) -> some View {
        Group {
            if let window {
                if window.limited {
                    Text("已限流")
                } else {
                    Text(Self.compactReset(window.resetsAt))
                }
            } else {
                Text("—")
            }
        }
        .font(.system(size: compact ? 9 : 10, weight: .medium, design: .rounded))
        .foregroundStyle(WidgetPalette.tertiary)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    /// Compact ASCII countdown ("4d21h") keeps the narrow widgets readable;
    /// the widget reloads every 15 minutes and the host app nudges it sooner.
    static func compactReset(_ date: Date, now: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "即将重置" }
        let minutes = Int(seconds / 60)
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let mins = minutes % 60
        if days > 0 { return "\(days)d\(hours)h" }
        if hours > 0 { return "\(hours)h\(mins)m" }
        return "\(max(1, mins))m"
    }
}

extension MeterColor {
    var color: Color {
        switch self {
        case .green: return Color(red: 0.32, green: 0.85, blue: 0.56)
        case .mint: return Color(red: 0.40, green: 0.90, blue: 0.75)
        case .teal: return Color(red: 0.30, green: 0.80, blue: 0.82)
        case .blue: return Color(red: 0.36, green: 0.65, blue: 0.98)
        case .purple: return Color(red: 0.68, green: 0.55, blue: 0.98)
        case .pink: return Color(red: 0.98, green: 0.55, blue: 0.76)
        case .red: return Color(red: 0.94, green: 0.40, blue: 0.40)
        case .orange: return Color(red: 0.98, green: 0.62, blue: 0.30)
        case .yellow: return Color(red: 0.98, green: 0.73, blue: 0.30)
        case .gray: return Color(red: 0.62, green: 0.65, blue: 0.72)
        }
    }
}
