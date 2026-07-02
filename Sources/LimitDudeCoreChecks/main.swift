import Foundation
import LimitDudeCore

private var failures: [String] = []

@MainActor
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failures.append(message)
    }
}

@MainActor
private func runChecks() {
    let classifier = ClaudeLimitTextClassifier()

    let limited = classifier.classify(text: "You have reached your message limit. Try again at 5:00 PM.")
    expect(limited.state == .limited, "Expected Claude limit text to classify as limited")

    let available = classifier.classify(text: "Good afternoon. How can I help you today?")
    expect(available.state == .available, "Expected readable non-limit text to classify as available")

    let unknown = classifier.classify(text: "   ")
    expect(unknown.state == .unknown, "Expected empty text to classify as unknown")
    expect(unknown.reason == "No readable Claude text", "Expected empty text reason to explain unreadable Claude text")

    let warning = classifier.classify(text: "Claude usage 82%. Resets at 7:00 PM.")
    expect(warning.state == .warning, "Expected 80 percent or higher usage to classify as warning")
    expect(warning.usagePercent == 82, "Expected warning to preserve usage percent")
    expect(warning.resetText == "7:00 PM", "Expected warning to extract reset time")
    expect(RemainingLimitTone.tone(forRemainingPercent: 4) == .critical, "Expected 4 percent remaining to be critical")
    expect(RemainingLimitTone.tone(forRemainingPercent: 20) == .critical, "Expected 20 percent remaining to be critical")
    expect(RemainingLimitTone.tone(forRemainingPercent: 21) == .caution, "Expected 21 percent remaining to be caution")
    expect(RemainingLimitTone.tone(forRemainingPercent: 50) == .caution, "Expected 50 percent remaining to be caution")
    expect(RemainingLimitTone.tone(forRemainingPercent: 51) == .healthy, "Expected 51 percent remaining to be healthy")
    expect(RemainingLimitTone.tone(forRemainingPercent: 100) == .healthy, "Expected 100 percent remaining to be healthy")

    let setupReport = SetupReport(checks: [
        SetupCheck(title: "Codex.app", state: .ok, detail: "Found at /Applications/Codex.app"),
        SetupCheck(title: "Codex login", state: .missing, detail: "Rate limits are not readable", action: "Open Codex and sign in")
    ])
    expect(setupReport.hasMissingRequiredSetup, "Setup report should flag missing setup")
    expect(
        setupReport.plainText.contains("[MISSING] Codex login: Rate limits are not readable\nAction: Open Codex and sign in"),
        "Setup report should include missing check action"
    )

    let monitor = LimitRecoveryMonitor()
    expect(monitor.ingest(.available()) == .none, "Initial available reading must not trigger animation")
    expect(monitor.ingest(.warning(usagePercent: 82, resetText: "7:00 PM")) == .warning(.warning(usagePercent: 82, resetText: "7:00 PM")), "First warning reading must trigger warning animation")
    expect(monitor.ingest(.warning(usagePercent: 83, resetText: "7:00 PM")) == .none, "Repeated warning reading must not trigger animation")
    expect(monitor.ingest(.warning(usagePercent: 91, resetText: "7:00 PM")) == .warning(.warning(usagePercent: 91, resetText: "7:00 PM")), "Crossing a higher warning band must trigger warning animation")
    expect(monitor.ingest(.warning(usagePercent: 96, resetText: "7:00 PM")) == .warning(.warning(usagePercent: 96, resetText: "7:00 PM")), "Crossing the critical warning band must trigger warning animation")
    expect(monitor.ingest(.warning(usagePercent: 99, resetText: "7:00 PM")) == .warning(.warning(usagePercent: 99, resetText: "7:00 PM")), "Crossing the final warning band must trigger warning animation")
    expect(monitor.ingest(.available(reason: "Left: 5h 100%, weekly 100%")) == .recovery(.available(reason: "Limits reset. Left: 5h 100%, weekly 100%")), "Warning to available transition must trigger reset recovery animation")
    expect(monitor.ingest(.limited()) == .none, "Initial limited reading must not trigger animation")
    expect(monitor.ingest(.limited()) == .none, "Repeated limited reading must not trigger animation")
    expect(monitor.ingest(.available()) == .recovery(.available(reason: "Limits reset. Claude text readable")), "Limited to available transition must trigger recovery animation")
    expect(monitor.ingest(.available()) == .none, "Repeated available reading must not trigger animation")
    expect(monitor.ingest(.unknown(reason: "Claude is closed")) == .none, "Unknown reading must not trigger animation")

    let usageDropMonitor = LimitRecoveryMonitor()
    expect(usageDropMonitor.ingest(LimitReading(state: .available, reason: "Left: 5h 25%, weekly 60%", usagePercent: 75)) == .none, "Initial high available usage must not trigger reset")
    expect(
        usageDropMonitor.ingest(LimitReading(state: .available, reason: "Left: 5h 75%, weekly 70%", usagePercent: 25)) == .recovery(.available(reason: "Limits reset. Left: 5h 75%, weekly 70%")),
        "Large usage drop must trigger reset recovery animation"
    )
    expect(usageDropMonitor.ingest(LimitReading(state: .available, reason: "Left: 5h 76%, weekly 70%", usagePercent: 24)) == .none, "Repeated low usage must not trigger reset twice")

    let taskMonitor = CodexTaskMonitor(idleSecondsBeforeDone: 5, minimumActiveSecondsBeforeNotify: 0)
    let start = Date(timeIntervalSince1970: 100)
    let firstSnapshot = CodexTaskSnapshot(
        id: "thread-1",
        title: "Build app",
        rolloutPath: "/tmp/thread-1.jsonl",
        fileSize: 100,
        modifiedAt: start
    )
    expect(taskMonitor.ingest([firstSnapshot], now: start).isEmpty, "Initial task baseline must not trigger a done notification")

    let activeSnapshot = CodexTaskSnapshot(
        id: "thread-1",
        title: "Build app",
        rolloutPath: "/tmp/thread-1.jsonl",
        fileSize: 140,
        modifiedAt: start.addingTimeInterval(1)
    )
    expect(taskMonitor.ingest([activeSnapshot], now: start.addingTimeInterval(1)).isEmpty, "Growing rollout file should only mark task active")
    expect(taskMonitor.ingest([activeSnapshot], now: start.addingTimeInterval(4)).isEmpty, "Active task should not complete before idle window")
    expect(taskMonitor.ingest([activeSnapshot], now: start.addingTimeInterval(7)).isEmpty, "Silent active task must not complete without a task_complete marker")
    expect(taskMonitor.ingest([activeSnapshot], now: start.addingTimeInterval(45)).isEmpty, "Long silent command must not show Codex available before Codex reports task_complete")

    let markerMonitor = CodexTaskMonitor(idleSecondsBeforeDone: 30, minimumActiveSecondsBeforeNotify: 30)
    let markerBaseline = CodexTaskSnapshot(
        id: "thread-2",
        title: "Finish turn",
        rolloutPath: "/tmp/thread-2.jsonl",
        fileSize: 200,
        modifiedAt: start,
        completionMarker: "old-marker"
    )
    expect(markerMonitor.ingest([markerBaseline], now: start).isEmpty, "Initial task completion marker must only seed baseline")

    let markerCompleted = CodexTaskSnapshot(
        id: "thread-2",
        title: "Finish turn",
        rolloutPath: "/tmp/thread-2.jsonl",
        fileSize: 240,
        modifiedAt: start.addingTimeInterval(1),
        completionMarker: "new-marker"
    )
    expect(
        markerMonitor.ingest([markerCompleted], now: start.addingTimeInterval(2)).isEmpty,
        "Fast Codex task_complete marker must not trigger an available notification"
    )

    let markerStillActive = CodexTaskSnapshot(
        id: "thread-2",
        title: "Finish turn",
        rolloutPath: "/tmp/thread-2.jsonl",
        fileSize: 280,
        modifiedAt: start.addingTimeInterval(10),
        completionMarker: "new-marker"
    )
    expect(markerMonitor.ingest([markerStillActive], now: start.addingTimeInterval(10)).isEmpty, "Continued rollout growth should keep task active")

    let markerCompletedAfterLongRun = CodexTaskSnapshot(
        id: "thread-2",
        title: "Finish turn",
        rolloutPath: "/tmp/thread-2.jsonl",
        fileSize: 320,
        modifiedAt: start.addingTimeInterval(41),
        completionMarker: "long-run-marker"
    )
    expect(
        markerMonitor.ingest([markerCompletedAfterLongRun], now: start.addingTimeInterval(41)) == [CodexTaskCompletion(id: "thread-2", title: "Finish turn", duration: 31)],
        "Long Codex task_complete marker should trigger an available notification"
    )
    expect(markerMonitor.ingest([markerCompletedAfterLongRun], now: start.addingTimeInterval(42)).isEmpty, "Same completion marker must not notify twice")
}

runChecks()

if failures.isEmpty {
    print("LimitDudeCoreChecks passed")
} else {
    failures.forEach { print("FAIL: \($0)") }
    exit(1)
}
