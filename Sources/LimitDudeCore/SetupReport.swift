public enum SetupCheckState: Equatable {
    case ok
    case warning
    case missing

    public var marker: String {
        switch self {
        case .ok:
            return "OK"
        case .warning:
            return "WARN"
        case .missing:
            return "MISSING"
        }
    }
}

public struct SetupCheck: Equatable {
    public let title: String
    public let state: SetupCheckState
    public let detail: String
    public let action: String?

    public init(title: String, state: SetupCheckState, detail: String, action: String? = nil) {
        self.title = title
        self.state = state
        self.detail = detail
        self.action = action
    }
}

public struct SetupReport: Equatable {
    public let checks: [SetupCheck]

    public init(checks: [SetupCheck]) {
        self.checks = checks
    }

    public var hasMissingRequiredSetup: Bool {
        checks.contains { $0.state == .missing }
    }

    public var plainText: String {
        checks.map { check in
            var lines = ["[\(check.state.marker)] \(check.title): \(check.detail)"]
            if let action = check.action {
                lines.append("Action: \(action)")
            }
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }
}
