import AppKit
import LimitDudeCore

enum PixelDudeMode {
    case recovery(LimitReading)
    case warning(LimitReading)

    var isTaskDone: Bool {
        switch self {
        case .recovery(let reading):
            return reading.reason.hasPrefix("Task done.")
        case .warning:
            return false
        }
    }

    var signText: String {
        switch self {
        case .recovery(let reading):
            if reading.reason.hasPrefix("Task done.") {
                return "Codex is available"
            }
            return reading.codexLimitHeadline ?? "Codex done"
        case .warning(let reading):
            if reading.reason.hasPrefix("Simulation only:") {
                return "Demo only"
            }
            if let headline = reading.codexLimitHeadline {
                return headline
            }
            if let usagePercent = reading.usagePercent {
                return "Codex \(usagePercent)%"
            }
            return "Limits soon"
        }
    }

    var detailText: String {
        switch self {
        case .recovery(let reading):
            if reading.reason.hasPrefix("Left:") {
                return reading.reason.replacingOccurrences(of: ". Reset:", with: "\nReset:")
            }
            if reading.reason.contains("Codex") {
                return reading.reason
            }
            if let resetText = reading.resetText {
                return "Codex is back. Next reset: \(resetText)"
            }
            return "Codex is available."
        case .warning(let reading):
            if reading.reason.hasPrefix("Simulation only:") {
                return reading.reason
            }
            if reading.reason.hasPrefix("Left:") {
                return reading.reason.replacingOccurrences(of: ". Reset:", with: "\nReset:")
            }
            if reading.reason.contains("Codex limits") || reading.reason.contains("Codex task") {
                return reading.reason
            }
            let usage = reading.usagePercent.map { "\($0)% used" } ?? "Almost out"
            let reset = reading.resetText.map { "Reset: \($0)" } ?? "Reset time unknown"
            return "\(usage). \(reset)."
        }
    }

    var taskDurationText: String? {
        switch self {
        case .recovery(let reading):
            guard reading.reason.hasPrefix("Task done.") else { return nil }
            return reading.reason
                .split(separator: "\n")
                .first { $0.hasPrefix("Duration: ") }
                .map { "last task \($0.replacingOccurrences(of: "Duration: ", with: ""))" }
        case .warning:
            return nil
        }
    }
}

private extension LimitReading {
    var codexLimitHeadline: String? {
        if reason.hasPrefix("Left: ") {
            let limitPart = reason
                .replacingOccurrences(of: "Left: ", with: "")
                .components(separatedBy: ". Reset:")
                .first?
                .replacingOccurrences(of: ", weekly", with: " / wk")
            guard let limitPart, !limitPart.isEmpty else { return nil }
            return limitPart
        }

        if reason.hasPrefix("Codex left: ") {
            let limitPart = reason
                .replacingOccurrences(of: "Codex left: ", with: "")
                .components(separatedBy: ". Used:")
                .first?
                .replacingOccurrences(of: ", weekly", with: " / wk")
            guard let limitPart, !limitPart.isEmpty else { return nil }
            return "left \(limitPart)"
        }

        guard reason.hasPrefix("Codex limits: ") else { return nil }
        let limitPart = reason
            .replacingOccurrences(of: "Codex limits: ", with: "")
            .components(separatedBy: ". Reset:")
            .first?
            .replacingOccurrences(of: ", weekly", with: " / wk")
        guard let limitPart, !limitPart.isEmpty else { return nil }
        return limitPart
    }
}

private let boredStartTime: TimeInterval = 4.5
private let boredSceneDuration: TimeInterval = 4.0

private enum BoredScene {
    case soccer
    case nap
    case dance
}

@MainActor
final class PixelDudeOverlay {
    private var window: NSWindow?
    private var view: PixelDudeView?
    private var timer: Timer?
    private var dismissTimer: Timer?
    private var startTime: TimeInterval = 0

    func show(mode: PixelDudeMode = .recovery(.available()), showDetails: Bool = false, forceAttention: Bool = false) {
        timer?.invalidate()
        dismissTimer?.invalidate()
        guard let overlayWindow = ensureWindow() else { return }

        view?.mode = mode
        view?.phase = 0
        view?.isShowingDetails = showDetails
        view?.detailRevealTime = Date().timeIntervalSinceReferenceDate
        view?.needsDisplay = true
        startTime = Date().timeIntervalSinceReferenceDate

        if forceAttention {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.requestUserAttention(.informationalRequest)
        }

        overlayWindow.setIsVisible(true)
        overlayWindow.makeKeyAndOrderFront(nil)
        overlayWindow.orderFrontRegardless()
        NSLog("LimitDude overlay show frame=\(overlayWindow.frame) details=\(showDetails) attention=\(forceAttention)")

        let animationTimer = Timer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(animationTimerFired), userInfo: nil, repeats: true)
        RunLoop.main.add(animationTimer, forMode: .common)
        timer = animationTimer
    }

    func demoClick() {
        handleClick()
    }

    func hide() {
        dismiss()
    }

    private func handleClick() {
        guard let view else { return }

        if view.isShowingDetails {
            dismiss()
            return
        }

        view.isShowingDetails = true
        view.detailRevealTime = Date().timeIntervalSinceReferenceDate
        view.needsDisplay = true
    }

    @objc private func animationTimerFired() {
        tick()
    }

    @objc private func dismissTimerFired() {
        dismiss()
    }

    private func tick() {
        let elapsed = Date().timeIntervalSinceReferenceDate - startTime
        view?.phase = elapsed
        view?.needsDisplay = true
    }

    private func dismiss() {
        timer?.invalidate()
        dismissTimer?.invalidate()
        timer = nil
        dismissTimer = nil
        window?.orderOut(nil)
        view?.isShowingDetails = false
        view?.needsDisplay = true
    }

    private func ensureWindow() -> NSWindow? {
        if let window {
            reposition(window)
            return window
        }

        guard let screen = NSScreen.main else { return nil }

        let size = NSSize(width: 500, height: 190)
        let frame = NSRect(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.maxY - size.height + 8,
            width: size.width,
            height: size.height
        )

        let overlayWindow = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        overlayWindow.isReleasedWhenClosed = false
        overlayWindow.isOpaque = false
        overlayWindow.backgroundColor = .clear
        overlayWindow.level = .screenSaver
        overlayWindow.hasShadow = false
        overlayWindow.animationBehavior = .none
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        overlayWindow.ignoresMouseEvents = false
        overlayWindow.hidesOnDeactivate = false

        let dudeView = PixelDudeView(frame: NSRect(origin: .zero, size: size))
        dudeView.mode = .recovery(.available())
        dudeView.onClick = { [weak self] in
            self?.handleClick()
        }
        overlayWindow.contentView = dudeView

        window = overlayWindow
        view = dudeView
        return overlayWindow
    }

    private func reposition(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let size = window.frame.size
        window.setFrame(
            NSRect(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.maxY - size.height + 8,
                width: size.width,
                height: size.height
            ),
            display: false
        )
    }
}

final class PixelDudeView: NSView {
    var phase: TimeInterval = 0
    var detailRevealTime: TimeInterval = 0
    var mode: PixelDudeMode = .recovery(.available())
    var isShowingDetails = false
    var onClick: (() -> Void)?

    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let entrance = entranceTransform()
        let centerX = bounds.midX
        let baseY: CGFloat = 52
        let isBored = phase > boredStartTime && !isShowingDetails
        let boredScene = currentBoredScene()
        let bodyOrigin = NSPoint(
            x: centerX - 48 + entrance.x,
            y: baseY + entrance.y
        )

        drawShadow(centerX: centerX, y: baseY - 12, scale: entrance.shadowScale)
        if isBored {
            switch boredScene {
            case .soccer:
                drawGoal(origin: NSPoint(x: centerX + 104, y: baseY + 10))
                drawBoredDude(origin: bodyOrigin, pixel: 8)
                drawBall(centerX: centerX, floorY: baseY - 2)
            case .nap:
                drawSleepingDude(origin: bodyOrigin, pixel: 8)
                drawZzz(origin: NSPoint(x: centerX + 62, y: baseY + 68))
            case .dance:
                drawDanceLights(centerX: centerX, baseY: baseY)
                drawDancingDude(origin: bodyOrigin, pixel: 8)
                drawMusicNotes(origin: NSPoint(x: centerX + 82, y: baseY + 54))
            }
        } else {
            drawDude(origin: bodyOrigin, pixel: 8, squash: entrance.squash)
            if case .recovery = mode {
                drawConfetti(centerX: centerX, baseY: baseY)
            }
        }

        if mode.isTaskDone && !isShowingDetails {
            drawAvailableSign(centerX: centerX, baseY: baseY)
        } else if isShowingDetails {
            drawBubble(origin: NSPoint(x: centerX - 166, y: 112), text: mode.detailText, width: 332, height: 70)
        } else if isBored {
            drawBubble(origin: NSPoint(x: centerX - 74, y: 122), text: boredBubbleText(for: boredScene), width: 148, height: 42)
        } else {
            drawBubble(origin: NSPoint(x: centerX - 112, y: 122), text: mode.signText, width: 224, height: 42)
        }
    }

    private func currentBoredScene() -> BoredScene {
        let sceneIndex = Int((phase - boredStartTime) / boredSceneDuration) % 3
        switch sceneIndex {
        case 0:
            return .soccer
        case 1:
            return .nap
        default:
            return .dance
        }
    }

    private func boredBubbleText(for scene: BoredScene) -> String {
        switch scene {
        case .soccer:
            return "goal?"
        case .nap:
            return "zzz..."
        case .dance:
            return "still here"
        }
    }

    private func entranceTransform() -> (x: CGFloat, y: CGFloat, squash: CGFloat, shadowScale: CGFloat) {
        if phase < 0.18 {
            return (0, 92, 1.0, 0.2)
        }

        if phase < 0.72 {
            let t = CGFloat((phase - 0.18) / 0.54)
            let y = 92 + (-12 - 92) * easeIn(t)
            return (0, y, 1.0, 0.35 + 0.5 * t)
        }

        if phase < 0.9 {
            let t = CGFloat((phase - 0.72) / 0.18)
            let y = -12 + 12 * easeOut(t)
            let squash = 1.0 - 0.16 * sin(t * .pi)
            return (0, y, squash, 1.0)
        }

        let idle = CGFloat(sin((phase - 0.9) * 3.4))
        let glance = CGFloat(sin((phase - 0.9) * 1.2))
        return (glance * 2.0, idle * 2.6, 1.0, 0.92 + abs(idle) * 0.05)
    }

    private func drawDude(origin: NSPoint, pixel: CGFloat, squash: CGFloat) {
        let body = NSColor(calibratedRed: 0.87, green: 0.47, blue: 0.36, alpha: 1)
        let dark = NSColor(calibratedRed: 0.09, green: 0.08, blue: 0.07, alpha: 1)
        let legStretch = phase < 0.9 ? CGFloat(1.0 + max(0, -entranceTransform().y) * 0.01) : CGFloat(1.0)
        let eyeShift = phase > 1.2 ? Int(round(sin(phase * 1.35))) : 0
        let blink = Int(phase * 2.2) % 9 == 0
        let antennaWave = Int(phase * 5.0) % 2

        drawRect(x: 2, y: 4, w: 9, h: Int(round(5 * squash)), pixel: pixel, origin: origin, color: body)
        drawRect(x: 0, y: 5, w: 2, h: 2, pixel: pixel, origin: origin, color: body)
        drawRect(x: 11, y: 5, w: 2, h: 2, pixel: pixel, origin: origin, color: body)

        drawRect(x: 3, y: Int(1 - legStretch), w: 1, h: Int(round(3 * legStretch)), pixel: pixel, origin: origin, color: body)
        drawRect(x: 6, y: Int(1 - legStretch), w: 1, h: Int(round(3 * legStretch)), pixel: pixel, origin: origin, color: body)
        drawRect(x: 9, y: Int(1 - legStretch), w: 1, h: Int(round(3 * legStretch)), pixel: pixel, origin: origin, color: body)

        drawRect(x: 5 + eyeShift, y: 7, w: 1, h: blink ? 0 : 1, pixel: pixel, origin: origin, color: dark)
        drawRect(x: 9 + eyeShift, y: 7, w: 1, h: blink ? 0 : 1, pixel: pixel, origin: origin, color: dark)
        if blink {
            drawRect(x: 5 + eyeShift, y: 7, w: 1, h: 1, pixel: pixel, origin: NSPoint(x: origin.x, y: origin.y - pixel * 0.25), color: dark)
            drawRect(x: 9 + eyeShift, y: 7, w: 1, h: 1, pixel: pixel, origin: NSPoint(x: origin.x, y: origin.y - pixel * 0.25), color: dark)
        }

        drawRect(x: 6, y: 10, w: 1, h: 1, pixel: pixel, origin: origin, color: dark)
        drawRect(x: 7 + antennaWave, y: 11, w: 1, h: 1, pixel: pixel, origin: origin, color: dark)
        drawRect(x: 6 + antennaWave, y: 12, w: 1, h: 1, pixel: pixel, origin: origin, color: dark)
    }

    private func drawBoredDude(origin: NSPoint, pixel: CGFloat) {
        let body = NSColor(calibratedRed: 0.87, green: 0.47, blue: 0.36, alpha: 1)
        let dark = NSColor(calibratedRed: 0.09, green: 0.08, blue: 0.07, alpha: 1)
        let sway = Int(round(sin(phase * 2.0)))
        let keepyPhase = CGFloat((phase - boredStartTime).truncatingRemainder(dividingBy: 3.6) / 3.6)
        let isKicking = keepyPhase > 0.68 && keepyPhase < 0.78

        drawRect(x: 2 + sway, y: 4, w: 9, h: 5, pixel: pixel, origin: origin, color: body)
        drawRect(x: 0 + sway, y: 5, w: 2, h: 2, pixel: pixel, origin: origin, color: body)
        drawRect(x: 11 + sway, y: 4, w: 2, h: 2, pixel: pixel, origin: origin, color: body)

        drawRect(x: 3 + sway, y: 1, w: 1, h: 3, pixel: pixel, origin: origin, color: body)
        drawRect(x: 6 + sway, y: 1, w: 1, h: 3, pixel: pixel, origin: origin, color: body)
        if isKicking {
            drawRect(x: 9 + sway, y: 2, w: 3, h: 1, pixel: pixel, origin: origin, color: body)
        } else {
            drawRect(x: 9 + sway, y: 1, w: 1, h: 3, pixel: pixel, origin: origin, color: body)
        }

        drawRect(x: 5 + sway, y: 7, w: 1, h: 1, pixel: pixel, origin: origin, color: dark)
        drawRect(x: 9 + sway, y: 7, w: 1, h: 1, pixel: pixel, origin: origin, color: dark)

        drawRect(x: 6 + sway, y: 10, w: 1, h: 1, pixel: pixel, origin: origin, color: dark)
        drawRect(x: 7 + sway, y: 11, w: 1, h: 1, pixel: pixel, origin: origin, color: dark)
        drawRect(x: 6 + sway, y: 12, w: 1, h: 1, pixel: pixel, origin: origin, color: dark)
    }

    private func drawSleepingDude(origin: NSPoint, pixel: CGFloat) {
        let body = NSColor(calibratedRed: 0.87, green: 0.47, blue: 0.36, alpha: 1)
        let dark = NSColor(calibratedRed: 0.09, green: 0.08, blue: 0.07, alpha: 1)
        let blanket = NSColor(calibratedRed: 0.96, green: 0.73, blue: 0.66, alpha: 1)
        let breathe = CGFloat(sin(phase * 2.2)) * 2

        NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: origin.x + 4, y: origin.y + 12, width: 84, height: 18), xRadius: 8, yRadius: 8).fill()

        drawRect(x: 2, y: 4, w: 9, h: 4, pixel: pixel, origin: NSPoint(x: origin.x, y: origin.y + breathe), color: body)
        drawRect(x: 0, y: 5, w: 2, h: 2, pixel: pixel, origin: NSPoint(x: origin.x, y: origin.y + breathe), color: body)
        drawRect(x: 11, y: 5, w: 2, h: 2, pixel: pixel, origin: NSPoint(x: origin.x, y: origin.y + breathe), color: body)

        drawRect(x: 4, y: 7, w: 2, h: 1, pixel: pixel, origin: NSPoint(x: origin.x, y: origin.y + breathe), color: dark)
        drawRect(x: 8, y: 7, w: 2, h: 1, pixel: pixel, origin: NSPoint(x: origin.x, y: origin.y + breathe), color: dark)

        drawRect(x: 2, y: 3, w: 9, h: 2, pixel: pixel, origin: origin, color: blanket)
        drawRect(x: 3, y: 1, w: 1, h: 2, pixel: pixel, origin: origin, color: body)
        drawRect(x: 8, y: 1, w: 1, h: 2, pixel: pixel, origin: origin, color: body)
    }

    private func drawDancingDude(origin: NSPoint, pixel: CGFloat) {
        let body = NSColor(calibratedRed: 0.87, green: 0.47, blue: 0.36, alpha: 1)
        let dark = NSColor(calibratedRed: 0.09, green: 0.08, blue: 0.07, alpha: 1)
        let beat = Int(phase * 4.0) % 2
        let jump = beat == 0 ? CGFloat(5) : CGFloat(0)
        let poseOrigin = NSPoint(x: origin.x, y: origin.y + jump)

        drawRect(x: 2, y: 4, w: 9, h: 5, pixel: pixel, origin: poseOrigin, color: body)
        drawRect(x: beat == 0 ? -1 : 0, y: 8, w: 3, h: 1, pixel: pixel, origin: poseOrigin, color: body)
        drawRect(x: beat == 0 ? 11 : 10, y: 8, w: 3, h: 1, pixel: pixel, origin: poseOrigin, color: body)
        drawRect(x: 3, y: 1, w: 1, h: 3, pixel: pixel, origin: poseOrigin, color: body)
        drawRect(x: beat == 0 ? 8 : 9, y: 1, w: 1, h: 3, pixel: pixel, origin: poseOrigin, color: body)

        drawRect(x: 5, y: 7, w: 1, h: 1, pixel: pixel, origin: poseOrigin, color: dark)
        drawRect(x: 9, y: 7, w: 1, h: 1, pixel: pixel, origin: poseOrigin, color: dark)
        drawRect(x: 6, y: 10, w: 1, h: 1, pixel: pixel, origin: poseOrigin, color: dark)
        drawRect(x: 7 + beat, y: 11, w: 1, h: 1, pixel: pixel, origin: poseOrigin, color: dark)
        drawRect(x: 6 + beat, y: 12, w: 1, h: 1, pixel: pixel, origin: poseOrigin, color: dark)
    }

    private func drawZzz(origin: NSPoint) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        let offset = CGFloat(sin(phase * 2.0)) * 3
        "z".draw(at: NSPoint(x: origin.x, y: origin.y + offset), withAttributes: attrs)
        "Z".draw(at: NSPoint(x: origin.x + 18, y: origin.y + 16 + offset), withAttributes: attrs)
        "Z".draw(at: NSPoint(x: origin.x + 40, y: origin.y + 32 + offset), withAttributes: attrs)
    }

    private func drawMusicNotes(origin: NSPoint) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 20, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        let bounce = CGFloat(sin(phase * 4.0)) * 4
        "♪".draw(at: NSPoint(x: origin.x, y: origin.y + bounce), withAttributes: attrs)
        "♫".draw(at: NSPoint(x: origin.x + 30, y: origin.y + 16 - bounce), withAttributes: attrs)
    }

    private func drawDanceLights(centerX: CGFloat, baseY: CGFloat) {
        let colors = [
            NSColor(calibratedRed: 0.87, green: 0.47, blue: 0.36, alpha: 0.35),
            NSColor(calibratedRed: 0.25, green: 0.55, blue: 0.95, alpha: 0.28),
            NSColor(calibratedRed: 0.20, green: 0.70, blue: 0.42, alpha: 0.25)
        ]
        for index in 0..<3 {
            colors[index].setFill()
            let x = centerX - 120 + CGFloat(index) * 120 + CGFloat(sin(phase * 2 + Double(index))) * 12
            NSBezierPath(ovalIn: NSRect(x: x, y: baseY + 12, width: 48, height: 14)).fill()
        }
    }

    private func drawConfetti(centerX: CGFloat, baseY: CGFloat) {
        let colors = [
            NSColor(calibratedRed: 0.87, green: 0.47, blue: 0.36, alpha: 1),
            NSColor(calibratedRed: 0.15, green: 0.42, blue: 0.85, alpha: 1),
            NSColor(calibratedRed: 0.20, green: 0.65, blue: 0.32, alpha: 1)
        ]
        for index in 0..<12 {
            colors[index % colors.count].setFill()
            let x = centerX - 145 + CGFloat(index * 26)
            let fall = CGFloat((phase * 28 + Double(index * 13)).truncatingRemainder(dividingBy: 90))
            let y = baseY + 94 - fall
            NSRect(x: x, y: y, width: 7, height: 7).fill()
        }
    }

    private func drawAvailableSign(centerX: CGFloat, baseY: CGFloat) {
        let reveal = easeOut(min(max(CGFloat(phase / 0.55), 0), 1))
        let wave = sin(max(phase - 0.2, 0) * 8.0) * 0.11
        let signSize = NSSize(width: 270, height: mode.taskDurationText == nil ? 54 : 62)
        let hand = NSPoint(x: centerX + 66, y: baseY + 68)
        let signOrigin = NSPoint(
            x: centerX - signSize.width / 2,
            y: baseY + 86 - (1 - reveal) * 54
        )

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: hand.x, yBy: hand.y)
        transform.rotate(byRadians: wave)
        transform.translateX(by: -hand.x, yBy: -hand.y)
        transform.concat()

        NSColor.black.setStroke()
        let pole = NSBezierPath()
        pole.move(to: hand)
        pole.line(to: NSPoint(x: signOrigin.x + signSize.width - 18, y: signOrigin.y + 8))
        pole.lineWidth = 5
        pole.stroke()

        let signRect = NSRect(origin: signOrigin, size: signSize)
        NSColor(calibratedRed: 0.13, green: 0.66, blue: 0.34, alpha: 0.98).setFill()
        signRect.fill()

        NSColor(calibratedRed: 0.72, green: 0.95, blue: 0.78, alpha: 0.65).setFill()
        NSRect(x: signRect.minX + 8, y: signRect.maxY - 13, width: signRect.width - 16, height: 5).fill()

        NSColor.black.setStroke()
        let border = NSBezierPath(rect: signRect)
        border.lineWidth = 4
        border.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping
        let hasDuration = mode.taskDurationText != nil
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: hasDuration ? 19 : 20, weight: .heavy),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let titleRect = hasDuration
            ? NSRect(x: signRect.minX + 10, y: signRect.minY + 22, width: signRect.width - 20, height: 28)
            : signRect.insetBy(dx: 10, dy: 14)
        mode.signText.draw(in: titleRect, withAttributes: attrs)

        if let taskDurationText = mode.taskDurationText {
            let durationAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .bold),
                .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.86),
                .paragraphStyle: paragraph
            ]
            taskDurationText.draw(in: NSRect(x: signRect.minX + 12, y: signRect.minY + 8, width: signRect.width - 24, height: 12), withAttributes: durationAttrs)
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawBall(centerX: CGFloat, floorY: CGFloat) {
        let cycle = CGFloat((phase - boredStartTime).truncatingRemainder(dividingBy: 3.6) / 3.6)
        let size: CGFloat = 24
        let x: CGFloat
        let y: CGFloat

        if cycle < 0.72 {
            let local = cycle / 0.72
            x = centerX + 62 + sin(local * .pi * 2.0) * 12
            y = floorY + 12 + sin(local * .pi) * 58
        } else {
            let local = (cycle - 0.72) / 0.28
            x = centerX + 62 + local * 122
            y = floorY + 18 + local * 18 + sin(local * .pi) * 28
        }

        let rect = NSRect(x: x, y: y, width: size, height: size)
        drawSoccerBall(in: rect, rotation: cycle)
    }

    private func drawSoccerBall(in rect: NSRect, rotation: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(ovalIn: rect)
        clip.addClip()

        NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
        rect.fill()

        NSColor.black.setFill()
        let centerPatch = NSBezierPath()
        let radius: CGFloat = 5.5
        for index in 0..<5 {
            let angle = CGFloat(index) * 2 * .pi / 5 - .pi / 2 + rotation * .pi * 2
            let point = NSPoint(
                x: rect.midX + cos(angle) * radius,
                y: rect.midY + sin(angle) * radius
            )
            index == 0 ? centerPatch.move(to: point) : centerPatch.line(to: point)
        }
        centerPatch.close()
        centerPatch.fill()

        NSColor.black.setStroke()
        let seams = NSBezierPath()
        for index in 0..<5 {
            let angle = CGFloat(index) * 2 * .pi / 5 - .pi / 2 + rotation * .pi * 2
            seams.move(to: NSPoint(x: rect.midX + cos(angle) * 5, y: rect.midY + sin(angle) * 5))
            seams.line(to: NSPoint(x: rect.midX + cos(angle) * 13, y: rect.midY + sin(angle) * 13))
        }
        seams.lineWidth = 1.5
        seams.stroke()

        NSGraphicsContext.restoreGraphicsState()

        NSColor.black.setStroke()
        let border = NSBezierPath(ovalIn: rect)
        border.lineWidth = 2
        border.stroke()
    }

    private func drawGoal(origin: NSPoint) {
        let width: CGFloat = 108
        let height: CGFloat = 64

        NSColor(calibratedWhite: 0.98, alpha: 0.78).setFill()
        NSRect(x: origin.x + 4, y: origin.y + 4, width: width - 8, height: height - 8).fill()

        NSColor.black.setStroke()
        let frame = NSBezierPath()
        frame.move(to: origin)
        frame.line(to: NSPoint(x: origin.x, y: origin.y + height))
        frame.line(to: NSPoint(x: origin.x + width, y: origin.y + height))
        frame.line(to: NSPoint(x: origin.x + width, y: origin.y))
        frame.move(to: NSPoint(x: origin.x - 4, y: origin.y))
        frame.line(to: NSPoint(x: origin.x + width + 4, y: origin.y))
        frame.lineWidth = 3
        frame.stroke()

        NSColor(calibratedWhite: 0.0, alpha: 0.28).setStroke()
        let net = NSBezierPath()
        for offset in stride(from: 12, through: Int(width - 12), by: 12) {
            net.move(to: NSPoint(x: origin.x + CGFloat(offset), y: origin.y + 2))
            net.line(to: NSPoint(x: origin.x + CGFloat(offset), y: origin.y + height - 2))
        }
        for offset in stride(from: 12, through: Int(height - 12), by: 12) {
            net.move(to: NSPoint(x: origin.x + 2, y: origin.y + CGFloat(offset)))
            net.line(to: NSPoint(x: origin.x + width - 2, y: origin.y + CGFloat(offset)))
        }
        net.lineWidth = 1
        net.stroke()
    }

    private func drawBubble(origin: NSPoint, text: String, width: CGFloat, height: CGFloat) {
        let reveal: CGFloat
        if isShowingDetails {
            reveal = easeOut(min(max(CGFloat((Date().timeIntervalSinceReferenceDate - detailRevealTime) / 0.18), 0), 1))
        } else {
            reveal = 1
        }

        let rect = NSRect(x: origin.x, y: origin.y, width: width * reveal, height: height)
        NSColor(calibratedWhite: 0.98, alpha: 0.97).setFill()
        rect.fill()
        NSColor.black.setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 3
        border.stroke()

        guard reveal > 0.82 else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: isShowingDetails ? 12 : 14, weight: .bold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        text.draw(in: rect.insetBy(dx: 8, dy: 7), withAttributes: attributes)
    }

    private func drawShadow(centerX: CGFloat, y: CGFloat, scale: CGFloat) {
        NSColor(calibratedWhite: 0.0, alpha: 0.12).setFill()
        let width: CGFloat = 92 * scale
        NSBezierPath(ovalIn: NSRect(x: centerX - width / 2, y: y, width: width, height: 10)).fill()
    }

    private func drawRect(x: Int, y: Int, w: Int, h: Int, pixel: CGFloat, origin: NSPoint, color: NSColor) {
        guard w > 0, h > 0 else { return }
        color.setFill()
        NSRect(
            x: origin.x + CGFloat(x) * pixel,
            y: origin.y + CGFloat(y) * pixel,
            width: CGFloat(w) * pixel,
            height: CGFloat(h) * pixel
        ).fill()
    }

    private func easeIn(_ t: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return clamped * clamped * clamped
    }

    private func easeOut(_ t: CGFloat) -> CGFloat {
        1 - pow(1 - min(max(t, 0), 1), 3)
    }
}
