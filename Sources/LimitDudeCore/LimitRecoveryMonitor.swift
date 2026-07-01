import Foundation

public enum LimitDudeAction: Equatable {
    case none
    case warning(LimitReading)
    case recovery(LimitReading)
}

public final class LimitRecoveryMonitor {
    private var lastStableState: LimitState?

    public init() {}

    @discardableResult
    public func ingest(_ reading: LimitReading) -> LimitDudeAction {
        guard reading.state == .warning || reading.state == .limited || reading.state == .available else {
            return .none
        }

        let previousState = lastStableState
        lastStableState = reading.state

        if previousState == .limited && reading.state == .available {
            return .recovery(reading)
        }

        if previousState != .warning && reading.state == .warning {
            return .warning(reading)
        }

        return .none
    }
}
