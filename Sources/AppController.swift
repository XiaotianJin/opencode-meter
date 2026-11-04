import AppKit
import WidgetKit

@MainActor
final class AppController: NSObject {
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var state = SharedState()
    private var settings = DisplaySettings.default
    private var isRefreshing = false
    private var lastError: String?
    private var settingsWindow: SettingsWindowController?

    func start() {
        state = SharedStore.load() ?? SharedState()
        settings = (state.settings ?? .default)
        settings.normalize()
        state.settings = settings
        SharedStore.save(state)

        buildStatusItem()
        rebuildMenu()
        updateStatusItem()
        scheduleTimer()

        refresh()

        DispatchQueue.main.async { [weak self] in
            self?.showSettingsOnLaunchIfNeeded()
        }
    }

    private func showSettingsOnLaunchIfNeeded() {
        let key = "didShowSettingsWindow"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        showSettings()
    }

    // MARK: status item

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        if let image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "OpenCode 额度") {
            image.isTemplate = true
            item.button?.image = image
            item.button?.imagePosition = .imageLeading
        }
        statusItem = item
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }

        if let rolling = state.snapshot?.rolling {
            button.title = "\(Int(rolling.remainingPercent.rounded()))%"
            button.toolTip = String(format: "OpenCode 额度\n5 小时剩余 %.0f%%", rolling.remainingPercent)
        } else {
            button.title = "—"
            button.toolTip = "OpenCode 额度"
        }
        if let error = lastError {
            button.toolTip = (button.toolTip ?? "") + "\n\(error)"
        }
    }

    // MARK: menu

    private func rebuildMenu() {
        guard let statusItem else { return }

        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(actionItem("设置…", #selector(openSettings), ","))
        menu.addItem(.separator())
        menu.addItem(actionItem("立即刷新", #selector(refreshNow), "r"))
        menu.addItem(actionItem("打开用量详情", #selector(openUsage)))

        menu.addItem(.separator())

        menu.addItem(submenu("显示", [
            choiceItem("剩余额度", on: settings.showRemaining, action: #selector(setRemaining)),
            choiceItem("已使用", on: !settings.showRemaining, action: #selector(setUsed))
        ]))

        menu.addItem(submenu("变色阈值", [
            submenu("黄色阈值（剩余 ≤）", thresholdItems(
                values: [50, 40, 30, 25, 20, 15, 10],
                current: settings.warningThreshold,
                action: #selector(setWarning)
            )),
            submenu("红色阈值（剩余 ≤）", thresholdItems(
                values: [25, 20, 15, 10, 5],
                current: settings.criticalThreshold,
                action: #selector(setCritical)
            ))
        ]))

        menu.addItem(submenu("颜色", [
            colorRoleItem("正常", current: settings.normalColor, action: #selector(setNormalColor)),
            colorRoleItem("警告", current: settings.warningColor, action: #selector(setWarningColor)),
            colorRoleItem("危险", current: settings.criticalColor, action: #selector(setCriticalColor))
        ]))

        menu.addItem(submenu("刷新间隔", refreshItems()))

        menu.addItem(.separator())
        menu.addItem(actionItem("如何添加小组件…", #selector(showHelp)))
        menu.addItem(actionItem("打开数据目录", #selector(openDataFolder)))
        menu.addItem(.separator())
        menu.addItem(actionItem("退出", #selector(quit), "q"))

        statusItem.menu = menu
    }

    private func actionItem(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func choiceItem(
        _ title: String,
        on: Bool,
        action: Selector,
        tag: Int = 0,
        represented: Any? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        item.tag = tag
        item.representedObject = represented
        return item
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu()
        for item in items { menu.addItem(item) }
        item.submenu = menu
        return item
    }

    private func thresholdItems(values: [Int], current: Double, action: Selector) -> [NSMenuItem] {
        var list = values
        let rounded = Int(current)
        if !list.contains(rounded) {
            list.append(rounded)
            list.sort(by: >)
        }
        return list.map { choiceItem("\($0)%", on: rounded == $0, action: action, tag: $0) }
    }

    private func colorRoleItem(_ title: String, current: MeterColor, action: Selector) -> NSMenuItem {
        let items = MeterColor.allCases.map { color in
            choiceItem(color.title, on: color == current, action: action, represented: color.rawValue)
        }
        return submenu(title, items)
    }

    private func refreshItems() -> [NSMenuItem] {
        var list = [1, 2, 3, 5, 10, 15, 30, 60]
        if !list.contains(settings.refreshMinutes) {
            list.append(settings.refreshMinutes)
            list.sort()
        }
        return list.map {
            choiceItem("\($0) 分钟", on: settings.refreshMinutes == $0, action: #selector(setRefresh), tag: $0)
        }
    }

    // MARK: settings

    private func update(_ mutate: (inout DisplaySettings) -> Void) {
        var next = settings
        mutate(&next)
        applySettings(next)
    }

    private func applySettings(_ settings: DisplaySettings) {
        var normalized = settings
        normalized.normalize()
        self.settings = normalized
        state.settings = normalized
        SharedStore.save(state)

        // The menu is still tracking when the action fires; rebuild next tick.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.rebuildMenu()
            self.scheduleTimer()
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings) { [weak self] next in
                self?.applySettings(next)
            }
        }
        settingsWindow?.present(with: settings)
    }

    @objc private func setRemaining() { update { $0.showRemaining = true } }
    @objc private func setUsed() { update { $0.showRemaining = false } }

    @objc private func setWarning(_ sender: NSMenuItem) {
        update { $0.warningThreshold = Double(sender.tag) }
    }

    @objc private func setCritical(_ sender: NSMenuItem) {
        update { $0.criticalThreshold = Double(sender.tag) }
    }

    @objc private func setNormalColor(_ sender: NSMenuItem) {
        guard let color = MeterColor(rawValue: sender.representedObject as? String ?? "") else { return }
        update { $0.normalColor = color }
    }

    @objc private func setWarningColor(_ sender: NSMenuItem) {
        guard let color = MeterColor(rawValue: sender.representedObject as? String ?? "") else { return }
        update { $0.warningColor = color }
    }

    @objc private func setCriticalColor(_ sender: NSMenuItem) {
        guard let color = MeterColor(rawValue: sender.representedObject as? String ?? "") else { return }
        update { $0.criticalColor = color }
    }

    @objc private func setRefresh(_ sender: NSMenuItem) {
        update { $0.refreshMinutes = sender.tag }
    }

    // MARK: refresh

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = Double(max(1, settings.refreshMinutes) * 60)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task {
            defer { isRefreshing = false }

            do {
                let (snapshot, service) = try await UsageClient.fetchLive()
                state.service = service
                state.snapshot = snapshot
                state.updatedAt = Date()
                state.settings = settings
                lastError = nil
                SharedStore.save(state)
            } catch {
                lastError = (error as? UsageError)?.message ?? error.localizedDescription
                // Still record credentials so the widget can retry by itself.
                if let service = OpenCodeService.discover() {
                    state.service = service
                    state.settings = settings
                    SharedStore.save(state)
                }
            }

            updateStatusItem()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: actions

    @objc private func openSettings() {
        showSettings()
    }

    @objc private func refreshNow() {
        refresh()
    }

    @objc private func openUsage() {
        let fallback = URL(string: "https://opencode.ai/console")!
        NSWorkspace.shared.open(state.snapshot?.usageURL ?? fallback)
    }

    @objc private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "添加 OpenCode 桌面小组件"
        alert.informativeText = """
        1. 在桌面空白处右键，选择“编辑小组件…”
        2. 搜索 “OpenCode”，选择小号或中号，拖到桌面即可
        3. 小组件按当前设置（\(settings.refreshMinutes) 分钟）自动刷新

        如果菜单栏图标被刘海或其它图标挤掉，双击 /Applications/OpenCodeMeter.app 也能打开设置窗口。
        """
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func openDataFolder() {
        let url = SharedStore.supportFolderURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
