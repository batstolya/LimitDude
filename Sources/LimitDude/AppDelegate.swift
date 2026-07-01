import AppKit
import LimitDudeCore
import LimitDudeMac

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = LimitRecoveryMonitor()
    private let taskMonitor = CodexTaskMonitor()
    private let provider = CodexRateLimitProvider()
    private let taskProvider = CodexTaskSnapshotProvider()
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

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        let frame = NSRect(
            x: screen.visibleFrame.maxX - size.width - 18,
            y: screen.visibleFrame.maxY - size.height - 8,
            width: size.width,
            height: size.height
        )

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

        let button = NSButton(frame: NSRect(origin: .zero, size: size))
        button.title = "LD"
        button.image = makeDudeIcon(size: 24)
        button.imagePosition = .imageLeft
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 14, weight: .bold)
        button.target = self
        button.action = #selector(showDude)
        button.toolTip = "Show Codex Dude"

        window.contentView = button
        window.orderFrontRegardless()
        launcherWindow = window
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
                self.handle(reading)
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
        showTaskDone(CodexTaskCompletion(id: "simulated", title: "Demo Codex task"))
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
        updateStatus(reading)
        showManualDude(for: reading)
    }

    @objc private func showWarningDude() {
        log("showWarningDude")
        let reading = provider.read()
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

    private func showTaskDone(_ completion: CodexTaskCompletion) {
        let reading = LimitReading.available(reason: "Task done. Можно кодить дальше.\n\(completion.title)")
        updateStatus(reading)
        log("showTaskDoneOverlay \(completion.id)")
        overlay.show(mode: .recovery(reading), showDetails: false, forceAttention: true)
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
        showTaskDone(CodexTaskCompletion(id: "demo-task", title: "Demo Codex task"))
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
