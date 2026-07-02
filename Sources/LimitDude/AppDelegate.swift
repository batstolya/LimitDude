import AppKit
import LimitDudeCore
import LimitDudeMac

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let launcherOriginDefaultsKey = "LimitDudeLauncherOrigin"
    private let monitor = LimitRecoveryMonitor()
    private let taskMonitor = CodexTaskMonitor()
    private let provider = CodexRateLimitProvider()
    private let taskProvider = CodexTaskSnapshotProvider()
    private let setupProvider = SetupStatusProvider()
    private let overlay = PixelDudeOverlay()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var launcherWindow: NSWindow?
    private var statusMenuItem: NSMenuItem?
    private var detailsMenuItem: NSMenuItem?
    private var taskWatchMenuItem: NSMenuItem?
    private var pollTimer: Timer?
    private var taskTimer: Timer?
    private var demoTimers: [Timer] = []
    private var taskWatchEnabled = true
    private var isCheckingLimits = false
    private var latestLimitReading: LimitReading?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ReadmeAssetRenderer.renderIfRequested() {
            NSApplication.shared.terminate(nil)
            return
        }

        log("applicationDidFinishLaunching")
        configureStatusItem()
        configureLauncherWindow()
        schedulePolling()
        checkTasksNow()
        checkNow()
        runTaskDoneDemoIfNeeded()
        runDemoModeIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        log("applicationWillTerminate")
        pollTimer?.invalidate()
        taskTimer?.invalidate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func configureStatusItem() {
        statusItem.button?.title = "LD"
        statusItem.button?.image = makeDudeIcon(size: 24)
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.toolTip = "Codex Dude is watching Codex limits"

        let menu = NSMenu()

        let appTitle = NSMenuItem(title: "Codex Dude", action: nil, keyEquivalent: "")
        appTitle.isEnabled = false
        menu.addItem(appTitle)

        let status = NSMenuItem(title: "Status: Starting", action: nil, keyEquivalent: "")
        status.isEnabled = false
        statusMenuItem = status
        menu.addItem(status)

        let details = NSMenuItem(title: "Waiting for first check", action: nil, keyEquivalent: "")
        details.isEnabled = false
        detailsMenuItem = details
        menu.addItem(details)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Setup Status", action: #selector(showSetupStatus), keyEquivalent: "s"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Check Codex Now", action: #selector(checkNow), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Show Dude", action: #selector(showDude), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Show Current Limits", action: #selector(showWarningDude), keyEquivalent: "w"))
        menu.addItem(NSMenuItem(title: "Hide Dude", action: #selector(hideDude), keyEquivalent: "h"))
        menu.addItem(.separator())
        let taskWatch = NSMenuItem(title: "Task Watch: On", action: #selector(toggleTaskWatch), keyEquivalent: "t")
        taskWatch.state = .on
        taskWatchMenuItem = taskWatch
        menu.addItem(taskWatch)
        menu.addItem(NSMenuItem(title: "Check Tasks Now", action: #selector(checkTasksNow), keyEquivalent: "k"))
        menu.addItem(NSMenuItem(title: "Simulate Task Done", action: #selector(simulateTaskDone), keyEquivalent: "g"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Simulate 80% Warning", action: #selector(simulateWarning), keyEquivalent: "8"))
        menu.addItem(NSMenuItem(title: "Simulate Limited", action: #selector(simulateLimited), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "Simulate Reset", action: #selector(simulateReset), keyEquivalent: "a"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func configureLauncherWindow() {
        guard launcherWindow == nil, let screen = NSScreen.main else { return }

        let size = NSSize(width: 76, height: 34)
        let origin = savedLauncherOrigin(size: size, screen: screen) ?? NSPoint(
            x: screen.visibleFrame.maxX - size.width - 18,
            y: screen.visibleFrame.maxY - size.height - 8
        )
        let frame = NSRect(origin: origin, size: size)

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false
        window.hidesOnDeactivate = false

        let button = DraggableLauncherButton(frame: NSRect(origin: .zero, size: size))
        button.title = "LD"
        button.image = makeDudeIcon(size: 24)
        button.imagePosition = .imageLeft
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 14, weight: .bold)
        button.target = self
        button.action = #selector(showDude)
        button.toolTip = "Show Codex Dude"
        button.onPositionChanged = { [weak self] origin in
            self?.saveLauncherOrigin(origin)
        }

        window.contentView = button
        window.orderFrontRegardless()
        launcherWindow = window
    }

    private func savedLauncherOrigin(size: NSSize, screen: NSScreen) -> NSPoint? {
        guard let dictionary = UserDefaults.standard.dictionary(forKey: launcherOriginDefaultsKey),
              let x = dictionary["x"] as? Double,
              let y = dictionary["y"] as? Double else {
            return nil
        }

        let frame = screen.visibleFrame
        return NSPoint(
            x: min(max(CGFloat(x), frame.minX), frame.maxX - size.width),
            y: min(max(CGFloat(y), frame.minY), frame.maxY - size.height)
        )
    }

    private func saveLauncherOrigin(_ origin: NSPoint) {
        UserDefaults.standard.set(
            [
                "x": Double(origin.x),
                "y": Double(origin.y)
            ],
            forKey: launcherOriginDefaultsKey
        )
    }

    private func schedulePolling() {
        let timer = Timer(timeInterval: 60, target: self, selector: #selector(checkNow), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        let taskTimer = Timer(timeInterval: 2, target: self, selector: #selector(checkTasksNow), userInfo: nil, repeats: true)
        RunLoop.main.add(taskTimer, forMode: .common)
        self.taskTimer = taskTimer
    }

    @objc private func checkNow() {
        guard !isCheckingLimits else {
            log("checkNowSkipped")
            return
        }

        log("checkNow")
        isCheckingLimits = true
        updateStatus(.checking())
        DispatchQueue.global(qos: .utility).async { [provider] in
            let reading = provider.read()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isCheckingLimits = false
                self.latestLimitReading = reading
                self.handle(reading)
            }
        }
    }

    @objc private func showSetupStatus() {
        log("showSetupStatus")
        detailsMenuItem?.title = "Checking setup..."

        DispatchQueue.global(qos: .utility).async { [setupProvider] in
            let report = setupProvider.read()
            DispatchQueue.main.async { [weak self] in
                self?.detailsMenuItem?.title = report.hasMissingRequiredSetup ? "Setup needs attention" : "Setup looks ready"
                self?.presentSetupReport(report)
            }
        }
    }

    @objc private func toggleTaskWatch() {
        taskWatchEnabled.toggle()
        log("toggleTaskWatch \(taskWatchEnabled)")
        taskWatchMenuItem?.title = taskWatchEnabled ? "Task Watch: On" : "Task Watch: Off"
        taskWatchMenuItem?.state = taskWatchEnabled ? .on : .off
        if taskWatchEnabled {
            checkTasksNow()
        }
    }

    @objc private func checkTasksNow() {
        guard taskWatchEnabled else { return }
        log("checkTasksNow")
        let completions = taskMonitor.ingest(taskProvider.recentTasks())
        if let completion = completions.first {
            log("taskDone \(completion.id) \(completion.title)")
            showTaskDone(completion)
        }
    }

    @objc private func simulateTaskDone() {
        log("simulateTaskDone")
        showTaskDone(CodexTaskCompletion(id: "simulated", title: "Demo Codex task", duration: 42))
    }

    @objc private func simulateLimited() {
        log("simulateLimited")
        let reading = LimitReading.limited(reason: "Simulation only: Codex limit reached", resetText: nil)
        updateStatus(reading)
        overlay.show(mode: .warning(reading))
    }

    @objc private func simulateWarning() {
        log("simulateWarning")
        let reading = LimitReading.warning(reason: "Simulation only: Codex limits are near 80%", usagePercent: nil, resetText: nil)
        updateStatus(reading)
        overlay.show(mode: .warning(reading))
    }

    @objc private func simulateReset() {
        log("simulateReset")
        let reading = LimitReading.available(reason: "Simulated Codex reset")
        updateStatus(reading)
        overlay.show(mode: .recovery(reading))
    }

    @objc private func showDude() {
        log("showDude")
        let reading = provider.read()
        latestLimitReading = reading
        updateStatus(reading)
        showManualDude(for: reading)
    }

    @objc private func showWarningDude() {
        log("showWarningDude")
        let reading = provider.read()
        latestLimitReading = reading
        updateStatus(reading)
        showManualDude(for: reading)
    }

    @objc private func hideDude() {
        log("hideDude")
        overlay.hide()
    }

    @objc private func quit() {
        log("quit")
        NSApplication.shared.terminate(nil)
    }

    private func handle(_ reading: LimitReading) {
        updateStatus(reading)
        switch monitor.ingest(reading) {
        case .none:
            break
        case .warning(let warningReading):
            overlay.show(mode: .warning(warningReading))
        case .recovery(let recoveryReading):
            overlay.show(mode: .recovery(recoveryReading))
        }
    }

    private func showManualDude(for reading: LimitReading) {
        switch reading.state {
        case .available:
            overlay.show(mode: .recovery(reading))
        case .warning, .limited:
            overlay.show(mode: .warning(reading))
        case .checking, .unknown:
            overlay.show(mode: .warning(.warning(reason: reading.reason, usagePercent: nil, resetText: reading.resetText)))
        }
    }

    private func presentSetupReport(_ report: SetupReport) {
        let alert = NSAlert()
        alert.messageText = report.hasMissingRequiredSetup ? "LimitDude setup needs attention" : "LimitDude setup looks ready"
        alert.informativeText = report.plainText
        alert.alertStyle = report.hasMissingRequiredSetup ? .warning : .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showTaskDone(_ completion: CodexTaskCompletion) {
        let resetLine = latestLimitReading?.resetText.map { "\nReset: \($0)" } ?? ""
        let reading = LimitReading.available(reason: "Task done. Можно кодить дальше.\nDuration: \(formatDuration(completion.duration))\(resetLine)")
        updateStatus(reading)
        log("showTaskDoneOverlay \(completion.id)")
        overlay.show(mode: .recovery(reading), showDetails: false, forceAttention: true)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60

        if minutes == 0 {
            return "\(remainingSeconds)s"
        }

        if remainingSeconds == 0 {
            return "\(minutes)m"
        }

        return "\(minutes)m \(remainingSeconds)s"
    }

    private func updateStatus(_ reading: LimitReading) {
        let title: String
        switch reading.state {
        case .checking:
            title = "Checking"
        case .warning:
            title = "Warning"
        case .limited:
            title = "Limited"
        case .available:
            title = "Available"
        case .unknown:
            title = "Unknown"
        }

        statusItem.button?.title = "LD"
        statusItem.button?.image = makeDudeIcon(size: 24)
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.toolTip = "Codex Dude: \(title). \(reading.reason)"
        statusMenuItem?.title = "Status: \(title)"
        detailsMenuItem?.title = reading.reason
    }

    private func makeDudeIcon(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()

        let pixel = floor(size / 12)
        let origin = NSPoint(
            x: floor((size - pixel * 12) / 2),
            y: floor((size - pixel * 12) / 2)
        )
        let body = NSColor(calibratedRed: 0.92, green: 0.49, blue: 0.34, alpha: 1)
        let bodyDark = NSColor(calibratedRed: 0.78, green: 0.36, blue: 0.24, alpha: 1)
        let dark = NSColor(calibratedRed: 0.07, green: 0.06, blue: 0.05, alpha: 1)

        func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: NSColor) {
            color.setFill()
            NSRect(
                x: origin.x + CGFloat(x) * pixel,
                y: origin.y + CGFloat(y) * pixel,
                width: CGFloat(w) * pixel,
                height: CGFloat(h) * pixel
            ).fill()
        }

        rect(2, 4, 8, 5, body)
        rect(1, 5, 1, 2, body)
        rect(10, 5, 1, 2, body)
        rect(3, 2, 1, 2, body)
        rect(6, 2, 1, 2, body)
        rect(9, 2, 1, 2, body)
        rect(2, 4, 8, 1, bodyDark)
        rect(4, 7, 1, 1, dark)
        rect(8, 7, 1, 1, dark)
        rect(5, 10, 1, 1, dark)
        rect(6, 11, 1, 1, dark)
        rect(5, 12, 1, 1, dark)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func runDemoModeIfNeeded() {
        guard CommandLine.arguments.contains("--demo-warning") else { return }

        let showTimer = Timer(timeInterval: 0.5, target: self, selector: #selector(runDemoWarning), userInfo: nil, repeats: false)
        RunLoop.main.add(showTimer, forMode: .common)
        demoTimers.append(showTimer)

        if CommandLine.arguments.contains("--demo-click") {
            let clickTimer = Timer(timeInterval: 3.0, target: self, selector: #selector(runDemoClick), userInfo: nil, repeats: false)
            RunLoop.main.add(clickTimer, forMode: .common)
            demoTimers.append(clickTimer)
        }

        if CommandLine.arguments.contains("--demo-autoclose") {
            let quitTimer = Timer(timeInterval: 24.0, target: self, selector: #selector(runDemoQuit), userInfo: nil, repeats: false)
            RunLoop.main.add(quitTimer, forMode: .common)
            demoTimers.append(quitTimer)
        }
    }

    @objc private func runDemoWarning() {
        overlay.show(mode: .warning(.warning(reason: "Demo only: Codex limits are near 80%", usagePercent: nil, resetText: nil)))
    }

    private func runTaskDoneDemoIfNeeded() {
        guard CommandLine.arguments.contains("--demo-task-done") else { return }

        let taskTimer = Timer(timeInterval: 1.0, target: self, selector: #selector(runDemoTaskDone), userInfo: nil, repeats: false)
        RunLoop.main.add(taskTimer, forMode: .common)
        demoTimers.append(taskTimer)
    }

    @objc private func runDemoTaskDone() {
        log("runDemoTaskDone")
        showTaskDone(CodexTaskCompletion(id: "demo-task", title: "Demo Codex task", duration: 42))
    }

    @objc private func runDemoClick() {
        overlay.demoClick()
    }

    @objc private func runDemoQuit() {
        demoTimers.forEach { $0.invalidate() }
        demoTimers.removeAll()
        log("runDemoQuit")
        Darwin.exit(0)
    }

    private func log(_ message: String) {
        let line = "\(Date()) \(message)\n"
        guard let data = line.data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/limit-dude.log")) else {
            try? line.write(toFile: "/tmp/limit-dude.log", atomically: true, encoding: .utf8)
            return
        }

        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    }
}

private final class DraggableLauncherButton: NSButton {
    private var mouseDownLocationInWindow: NSPoint?
    private var windowFrameAtMouseDown: NSRect?
    private var didDrag = false
    private let dragThreshold: CGFloat = 3
    var onPositionChanged: ((NSPoint) -> Void)?

    override func mouseDown(with event: NSEvent) {
        mouseDownLocationInWindow = event.locationInWindow
        windowFrameAtMouseDown = window?.frame
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let mouseDownLocationInWindow,
              let windowFrameAtMouseDown else {
            super.mouseDragged(with: event)
            return
        }

        let currentScreenLocation = NSEvent.mouseLocation
        let origin = NSPoint(
            x: currentScreenLocation.x - mouseDownLocationInWindow.x,
            y: currentScreenLocation.y - mouseDownLocationInWindow.y
        )
        let deltaX = origin.x - windowFrameAtMouseDown.origin.x
        let deltaY = origin.y - windowFrameAtMouseDown.origin.y
        if abs(deltaX) > dragThreshold || abs(deltaY) > dragThreshold {
            didDrag = true
        }

        let clampedOrigin = clampedOrigin(origin, for: window)
        window.setFrameOrigin(clampedOrigin)
        onPositionChanged?(clampedOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownLocationInWindow = nil
            windowFrameAtMouseDown = nil
            didDrag = false
        }

        if didDrag {
            if let origin = window?.frame.origin {
                onPositionChanged?(origin)
            }
        } else if isEnabled {
            performClick(nil)
        }
    }

    private func clampedOrigin(_ origin: NSPoint, for window: NSWindow) -> NSPoint {
        guard let screen = window.screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
            return origin
        }

        let frame = screen.visibleFrame
        let size = window.frame.size
        return NSPoint(
            x: min(max(origin.x, frame.minX), frame.maxX - size.width),
            y: min(max(origin.y, frame.minY), frame.maxY - size.height)
        )
    }
}
