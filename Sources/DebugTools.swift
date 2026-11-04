import AppKit
import SwiftUI
import WidgetKit

@MainActor
enum DebugTools {
    static func printLimits() async -> Int32 {
        do {
            let (snapshot, _) = try await UsageClient.fetchLive()
            func line(_ name: String, _ window: UsageWindow?) -> String {
                guard let window else { return "\(name): -" }
                return "\(name): 剩余 \(Int(window.remainingPercent.rounded()))% | 重置 \(Format.reset(window.resetsAt))"
            }
            Swift.print(line("5h", snapshot.rolling))
            Swift.print(line("1w", snapshot.weekly))
            Swift.print(line("1m", snapshot.monthly))
            return 0
        } catch {
            FileHandle.standardError.write(Data((((error as? UsageError)?.message ?? error.localizedDescription) + "\n").utf8))
            return 1
        }
    }

    static func syncOnce() async -> Int32 {
        do {
            let (snapshot, service) = try await UsageClient.fetchLive()
            var state = SharedStore.load() ?? SharedState()
            state.service = service
            state.snapshot = snapshot
            state.updatedAt = Date()
            let saved = SharedStore.save(state)
            WidgetCenter.shared.reloadAllTimelines()
            Swift.print("state: \(SharedStore.stateURL.path)")
            Swift.print("saved: \(saved)")
            return saved ? 0 : 1
        } catch {
            FileHandle.standardError.write(Data((((error as? UsageError)?.message ?? error.localizedDescription) + "\n").utf8))
            return 1
        }
    }

    static func printState() -> Int32 {
        Swift.print("state file: \(SharedStore.stateURL.path)")
        if let raw = try? String(contentsOf: SharedStore.stateURL, encoding: .utf8) {
            Swift.print(raw)
        } else {
            Swift.print("(missing)")
        }
        return 0
    }

    static func renderPreviews(to directory: String) -> Int32 {
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let entry = UsageEntry.placeholder
        var failed = false

        func render(_ view: some View, size: CGSize, name: String) {
            let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else {
                failed = true
                return
            }
            try? png.write(to: folder.appendingPathComponent(name))
        }

        let small = UsageWidgetView(entry: entry, family: .systemSmall)
            .background(WidgetBackground())
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        render(small, size: CGSize(width: 158, height: 158), name: "small.png")

        let medium = UsageWidgetView(entry: entry, family: .systemMedium)
            .background(WidgetBackground())
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        render(medium, size: CGSize(width: 338, height: 158), name: "medium.png")

        let offlineEntry = UsageEntry(
            date: Date(),
            snapshot: nil,
            updatedAt: nil,
            errorMessage: "无法连接 OpenCode 本地服务",
            settings: .default
        )
        let offline = UsageWidgetView(entry: offlineEntry, family: .systemSmall)
            .background(WidgetBackground())
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        render(offline, size: CGSize(width: 158, height: 158), name: "offline.png")

        let low = UsageEntry(
            date: Date(),
            snapshot: UsageSnapshot(
                rolling: UsageWindow(usedPercent: 88, limited: false, resetsAt: Date().addingTimeInterval(3600)),
                weekly: UsageWindow(usedPercent: 80, limited: false, resetsAt: Date().addingTimeInterval(3 * 86400)),
                monthly: UsageWindow(usedPercent: 94, limited: false, resetsAt: Date().addingTimeInterval(20 * 86400)),
                usageURL: nil,
                workspaceName: "Default"
            ),
            updatedAt: Date(),
            errorMessage: nil,
            settings: .default
        )
        let lowView = UsageWidgetView(entry: low, family: .systemMedium)
            .background(WidgetBackground())
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        render(lowView, size: CGSize(width: 338, height: 158), name: "low.png")

        let rings = UsageRingsView(entry: entry)
            .background(WidgetBackground())
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        render(rings, size: CGSize(width: 158, height: 158), name: "rings.png")

        let ringsLow = UsageRingsView(entry: low)
            .background(WidgetBackground())
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        render(ringsLow, size: CGSize(width: 158, height: 158), name: "rings-low.png")

        Swift.print("previews: \(folder.path)")
        return failed ? 1 : 0
    }
}

enum Format {
    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    static func reset(_ date: Date) -> String {
        resetFormatter.string(from: date)
    }
}
