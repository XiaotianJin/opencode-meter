import AppKit

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private let controller: AppController

    init(controller: AppController) {
        self.controller = controller
    }

    /// Double-clicking the app (or `open -a`) reopens the settings window even
    /// when the menu bar item is hidden by the notch or a crowded menu bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.showSettings()
        return true
    }
}

@main
struct OpenCodeMeterApp {
    @MainActor
    static func main() async {
        let arguments = CommandLine.arguments

        if arguments.contains("--print") {
            exit(await DebugTools.printLimits())
        }
        if arguments.contains("--sync") {
            exit(await DebugTools.syncOnce())
        }
        if arguments.contains("--state") {
            exit(DebugTools.printState())
        }
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            exit(DebugTools.renderPreviews(to: arguments[index + 1]))
        }
        if arguments.contains("--windows") {
            let application = NSApplication.shared
            application.setActivationPolicy(.accessory)
            let controller = AppController()
            controller.start()
            controller.showSettings()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            for window in NSApp.windows {
                print("window title=\(window.title) frame=\(window.frame) visible=\(window.isVisible) level=\(window.level.rawValue)")
            }
            exit(0)
        }

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        let controller = AppController()
        let delegate = ApplicationDelegate(controller: controller)
        application.delegate = delegate

        controller.start()

        application.run()
    }
}
