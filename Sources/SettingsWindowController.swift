import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private var settings: DisplaySettings
    private let onChange: (DisplaySettings) -> Void

    private let displayPopup = NSPopUpButton()
    private let warningPopup = NSPopUpButton()
    private let criticalPopup = NSPopUpButton()
    private let normalColorPopup = NSPopUpButton()
    private let warningColorPopup = NSPopUpButton()
    private let criticalColorPopup = NSPopUpButton()
    private let refreshPopup = NSPopUpButton()

    private static let warningValues = [50, 40, 30, 25, 20, 15, 10]
    private static let criticalValues = [25, 20, 15, 10, 5]
    private static let refreshValues = [1, 2, 3, 5, 10, 15, 30, 60]

    init(settings: DisplaySettings, onChange: @escaping (DisplaySettings) -> Void) {
        self.settings = settings
        self.onChange = onChange

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 342),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenCode 额度设置"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        buildUI()
        reloadSelections()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(with settings: DisplaySettings) {
        self.settings = settings
        reloadSelections()
        centerOnMainScreen()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func centerOnMainScreen() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.screens.first
            ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            )
        )
    }

    // MARK: UI

    private func buildUI() {
        guard let window else { return }

        configurePopups()

        let grid = NSGridView(views: [
            [label("显示"), displayPopup],
            [label("黄色阈值"), warningPopup],
            [label("红色阈值"), criticalPopup],
            [label("正常颜色"), normalColorPopup],
            [label("警告颜色"), warningColorPopup],
            [label("危险颜色"), criticalColorPopup],
            [label("刷新间隔"), refreshPopup]
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.translatesAutoresizingMaskIntoConstraints = false

        let dataButton = NSButton(title: "打开数据目录", target: self, action: #selector(openDataFolder))
        dataButton.bezelStyle = .rounded
        let closeButton = NSButton(title: "完成", target: self, action: #selector(closeWindow))
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "\r"

        let buttons = NSStackView(views: [dataButton, closeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 342))
        container.addSubview(grid)
        container.addSubview(buttons)
        window.contentView = container
        window.setContentSize(NSSize(width: 380, height: 342))

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            buttons.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 18),
            buttons.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16)
        ])
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: 12)
        field.textColor = .secondaryLabelColor
        return field
    }

    private func configurePopups() {
        displayPopup.addItems(withTitles: ["剩余额度", "已使用"])

        for value in Self.warningValues {
            warningPopup.addItem(withTitle: "剩余 ≤ \(value)%")
            warningPopup.lastItem?.tag = value
        }
        for value in Self.criticalValues {
            criticalPopup.addItem(withTitle: "剩余 ≤ \(value)%")
            criticalPopup.lastItem?.tag = value
        }
        for value in Self.refreshValues {
            refreshPopup.addItem(withTitle: "\(value) 分钟")
            refreshPopup.lastItem?.tag = value
        }

        for popup in [normalColorPopup, warningColorPopup, criticalColorPopup] {
            for color in MeterColor.allCases {
                popup.addItem(withTitle: color.title)
                popup.lastItem?.representedObject = color.rawValue
            }
        }

        for popup in [displayPopup, warningPopup, criticalPopup, normalColorPopup,
                      warningColorPopup, criticalColorPopup, refreshPopup] {
            popup.target = self
            popup.action = #selector(controlsChanged)
            popup.translatesAutoresizingMaskIntoConstraints = false
            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        }
    }

    private func reloadSelections() {
        displayPopup.selectItem(at: settings.showRemaining ? 0 : 1)

        select(popup: warningPopup, tag: Int(settings.warningThreshold))
        select(popup: criticalPopup, tag: Int(settings.criticalThreshold))
        select(popup: refreshPopup, tag: settings.refreshMinutes)

        selectColor(normalColorPopup, settings.normalColor)
        selectColor(warningColorPopup, settings.warningColor)
        selectColor(criticalColorPopup, settings.criticalColor)
    }

    private func select(popup: NSPopUpButton, tag: Int) {
        if let item = popup.itemArray.first(where: { $0.tag == tag }) {
            popup.select(item)
        }
    }

    private func selectColor(_ popup: NSPopUpButton, _ color: MeterColor) {
        if let item = popup.itemArray.first(where: {
            ($0.representedObject as? String) == color.rawValue
        }) {
            popup.select(item)
        }
    }

    @objc private func controlsChanged() {
        var next = settings
        next.showRemaining = displayPopup.indexOfSelectedItem == 0
        next.warningThreshold = Double(warningPopup.selectedTag())
        next.criticalThreshold = Double(criticalPopup.selectedTag())
        next.refreshMinutes = refreshPopup.selectedTag()

        if let raw = normalColorPopup.selectedItem?.representedObject as? String,
           let color = MeterColor(rawValue: raw) {
            next.normalColor = color
        }
        if let raw = warningColorPopup.selectedItem?.representedObject as? String,
           let color = MeterColor(rawValue: raw) {
            next.warningColor = color
        }
        if let raw = criticalColorPopup.selectedItem?.representedObject as? String,
           let color = MeterColor(rawValue: raw) {
            next.criticalColor = color
        }

        next.normalize()
        settings = next
        reloadSelections()
        onChange(next)
    }

    @objc private func openDataFolder() {
        let url = SharedStore.supportFolderURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc private func closeWindow() {
        window?.close()
    }
}
