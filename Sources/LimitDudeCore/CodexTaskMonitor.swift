import Foundation

public struct CodexTaskSnapshot: Equatable {
    public let id: String
    public let title: String
    public let rolloutPath: String
    public let fileSize: UInt64
    public let modifiedAt: Date
    public let completionMarker: String?

    public init(id: String, title: String, rolloutPath: String, fileSize: UInt64, modifiedAt: Date, completionMarker: String? = nil) {
        self.id = id
        self.title = title
        self.rolloutPath = rolloutPath
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.completionMarker = completionMarker
    }
}

public struct CodexTaskCompletion: Equatable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public final class CodexTaskMonitor {
    private struct TrackedTask {
        var title: String
        var fileSize: UInt64
        var lastChangedAt: Date
        var activeStartedAt: Date?
        var hasBeenActive: Bool
        var didNotify: Bool
        var completionMarker: String?
    }

    private let idleSecondsBeforeDone: TimeInterval
    private let minimumActiveSecondsBeforeNotify: TimeInterval
    private var didSeedBaseline = false
    private var tasks: [String: TrackedTask] = [:]

    public init(idleSecondsBeforeDone: TimeInterval = 25, minimumActiveSecondsBeforeNotify: TimeInterval = 30) {
        self.idleSecondsBeforeDone = idleSecondsBeforeDone
        self.minimumActiveSecondsBeforeNotify = minimumActiveSecondsBeforeNotify
    }

    public func ingest(_ snapshots: [CodexTaskSnapshot], now: Date = Date()) -> [CodexTaskCompletion] {
        if !didSeedBaseline {
            didSeedBaseline = true
            tasks = Dictionary(uniqueKeysWithValues: snapshots.map {
                ($0.id, TrackedTask(
                    title: $0.title,
                    fileSize: $0.fileSize,
                    lastChangedAt: now,
                    activeStartedAt: nil,
                    hasBeenActive: false,
                    didNotify: false,
                    completionMarker: $0.completionMarker
                ))
            })
            return []
        }

        var completions: [CodexTaskCompletion] = []
        let snapshotIDs = Set(snapshots.map(\.id))
        tasks = tasks.filter { snapshotIDs.contains($0.key) }

        for snapshot in snapshots {
            var tracked = tasks[snapshot.id] ?? TrackedTask(
                title: snapshot.title,
                fileSize: snapshot.fileSize,
                lastChangedAt: now,
                activeStartedAt: nil,
                hasBeenActive: false,
                didNotify: false,
                completionMarker: snapshot.completionMarker
            )

            tracked.title = snapshot.title
            if snapshot.fileSize > tracked.fileSize {
                if !tracked.hasBeenActive {
                    tracked.activeStartedAt = snapshot.modifiedAt
                }
                tracked.fileSize = snapshot.fileSize
                tracked.lastChangedAt = now
                tracked.hasBeenActive = true
                tracked.didNotify = false
            }

            if let completionMarker = snapshot.completionMarker,
               completionMarker != tracked.completionMarker,
               tasks[snapshot.id] != nil {
                if shouldNotifyCompletion(for: tracked, now: now) {
                    completions.append(CodexTaskCompletion(id: snapshot.id, title: snapshot.title))
                }
                tracked.completionMarker = completionMarker
                tracked.lastChangedAt = now
                tracked.hasBeenActive = false
                tracked.activeStartedAt = nil
                tracked.didNotify = true
                tasks[snapshot.id] = tracked
                continue
            }

            let isIdleAfterActivity = tracked.hasBeenActive && !tracked.didNotify && now.timeIntervalSince(tracked.lastChangedAt) >= idleSecondsBeforeDone
            if isIdleAfterActivity && shouldNotifyCompletion(for: tracked, now: now) {
                completions.append(CodexTaskCompletion(id: snapshot.id, title: snapshot.title))
                tracked.didNotify = true
                tracked.hasBeenActive = false
                tracked.activeStartedAt = nil
            }

            tasks[snapshot.id] = tracked
        }

        return completions
    }

    private func shouldNotifyCompletion(for task: TrackedTask, now: Date) -> Bool {
        guard let activeStartedAt = task.activeStartedAt else { return false }
        return now.timeIntervalSince(activeStartedAt) >= minimumActiveSecondsBeforeNotify
    }
}
