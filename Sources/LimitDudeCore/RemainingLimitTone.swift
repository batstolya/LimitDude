public enum RemainingLimitTone: Equatable {
    case critical
    case caution
    case healthy

    public static func tone(forRemainingPercent percent: Int) -> RemainingLimitTone {
        if percent <= 20 {
            return .critical
        }

        if percent <= 50 {
            return .caution
        }

        return .healthy
    }
}
