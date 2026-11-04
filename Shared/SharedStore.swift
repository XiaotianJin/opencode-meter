import Foundation
import Darwin

/// Data hand-off between the menu bar app and the sandboxed widget extension.
///
/// App Groups would be the canonical channel, but they need a team identifier
/// and a provisioning profile. The state lives in the user's Application
/// Support instead; the widget's sandbox gets a home-relative read-only
/// exception for that one folder.
struct SharedState: Codable {
    var service: OpenCodeService?
    var snapshot: UsageSnapshot?
    var updatedAt: Date?
    var settings: DisplaySettings?
}

// MARK: - Display settings

enum MeterColor: String, Codable, CaseIterable {
    case green, mint, teal, blue, purple, pink, red, orange, yellow, gray

    var title: String {
        switch self {
        case .green: return "绿"
        case .mint: return "薄荷"
        case .teal: return "青"
        case .blue: return "蓝"
        case .purple: return "紫"
        case .pink: return "粉"
        case .red: return "红"
        case .orange: return "橙"
        case .yellow: return "黄"
        case .gray: return "灰"
        }
    }
}

struct DisplaySettings: Codable, Equatable {
    var showRemaining: Bool = true
    var warningThreshold: Double = 25
    var criticalThreshold: Double = 10
    var normalColor: MeterColor = .green
    var warningColor: MeterColor = .yellow
    var criticalColor: MeterColor = .red
    var refreshMinutes: Int = 3

    static let `default` = DisplaySettings()

    init() {}

    /// Tolerate older or partial state files so a schema change never blanks the widget.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = DisplaySettings()
        showRemaining = try container.decodeIfPresent(Bool.self, forKey: .showRemaining) ?? fallback.showRemaining
        warningThreshold = try container.decodeIfPresent(Double.self, forKey: .warningThreshold) ?? fallback.warningThreshold
        criticalThreshold = try container.decodeIfPresent(Double.self, forKey: .criticalThreshold) ?? fallback.criticalThreshold
        refreshMinutes = try container.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? fallback.refreshMinutes

        func color(_ key: CodingKeys, _ fallback: MeterColor) -> MeterColor {
            guard let raw = try? container.decodeIfPresent(String.self, forKey: key),
                  let value = MeterColor(rawValue: raw)
            else { return fallback }
            return value
        }
        normalColor = color(.normalColor, fallback.normalColor)
        warningColor = color(.warningColor, fallback.warningColor)
        criticalColor = color(.criticalColor, fallback.criticalColor)
    }

    mutating func normalize() {
        warningThreshold = min(100, max(1, warningThreshold.rounded()))
        criticalThreshold = min(100, max(0, criticalThreshold.rounded()))
        if criticalThreshold >= warningThreshold {
            criticalThreshold = max(0, warningThreshold - 5)
        }
        refreshMinutes = min(60, max(1, refreshMinutes))
    }
}

enum SharedStore {
    static let widgetBundleID = "local.metax.opencode-meter.widget"
    private static let folder = "OpenCodeMeter"

    /// Inside the widget sandbox the process home is the container, so resolve
    /// the real account home through the password database instead.
    static var realHomeURL: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var supportFolderURL: URL {
        realHomeURL
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true)
    }

    static var stateURL: URL {
        supportFolderURL.appendingPathComponent("state.json")
    }

    static func load() -> SharedState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(SharedState.self, from: data)
    }

    @discardableResult
    static func save(_ state: SharedState) -> Bool {
        let url = stateURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .deferredToDate
            let data = try encoder.encode(state)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
