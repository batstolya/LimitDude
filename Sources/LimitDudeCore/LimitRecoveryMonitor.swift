import Foundation

public enum LimitDudeAction: Equatable {
    case none
    case warning(LimitReading)
    case recovery(LimitReading)
}

public final class LimitRecoveryMonitor {
    private var lastStableState: LimitState?
    private var lastWarningBand: Int?

    public init() {}

    @discardableResult
    public func ingest(_ reading: LimitReading) -> LimitDudeAction {
        guard reading.state == .warning || reading.state == .limited || reading.state == .available else {
            return .none
        }

        let previousState = lastStableState
        lastStableState = reading.state

        if (previousState == .limited || previousState == .warning) && reading.state == .available {
            lastWarningBand = nil
            return .recovery(.available(reason: "Limits reset. \(reading.reason)"))
        }

        if reading.state == .warning {
            let currentBand = warningBand(for: reading)
            defer {
                lastWarningBand = currentBand
            }

            guard previousState == .warning else {
                return .warning(reading)
            }

            if let currentBand,
               let lastWarningBand,
               currentBand > lastWarningBand {
                return .warning(reading)
            }
        }

        return .none
    }

    private func warningBand(for reading: LimitReading) -> Int? {
        guard let usagePercent = reading.usagePercent else { return nil }
        if usagePercent >= 99 { return 99 }
        if usagePercent >= 95 { return 95 }
        if usagePercent >= 90 { return 90 }
        if usagePercent >= 80 { return 80 }
        return nil
    }
}
