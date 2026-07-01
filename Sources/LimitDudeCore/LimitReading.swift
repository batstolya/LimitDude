import Foundation

public enum LimitState: String, Equatable, Sendable {
    case checking
    case warning
    case limited
    case available
    case unknown
}

public struct LimitReading: Equatable, Sendable {
    public let state: LimitState
    public let reason: String
    public let usagePercent: Int?
    public let resetText: String?

    public init(state: LimitState, reason: String, usagePercent: Int? = nil, resetText: String? = nil) {
        self.state = state
        self.reason = reason
        self.usagePercent = usagePercent
        self.resetText = resetText
    }

    public static func checking() -> LimitReading {
        LimitReading(state: .checking, reason: "Checking limits")
    }

    public static func warning(
        reason: String = "Claude limits are almost gone",
        usagePercent: Int? = nil,
        resetText: String? = nil
    ) -> LimitReading {
        LimitReading(state: .warning, reason: reason, usagePercent: usagePercent, resetText: resetText)
    }

    public static func limited(reason: String = "Claude limit text detected", resetText: String? = nil) -> LimitReading {
        LimitReading(state: .limited, reason: reason, resetText: resetText)
    }

    public static func available(reason: String = "Claude text readable") -> LimitReading {
        LimitReading(state: .available, reason: reason)
    }

    public static func unknown(reason: String) -> LimitReading {
        LimitReading(state: .unknown, reason: reason)
    }
}
