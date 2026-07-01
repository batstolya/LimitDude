import Foundation
import LimitDudeMac

@main
struct LimitDudeCodexCheck {
    static func main() {
        let reading = CodexRateLimitProvider().read()
        let percent = reading.usagePercent.map { " \($0)%" } ?? ""
        let reset = reading.resetText.map { " reset: \($0)" } ?? ""
        print("\(reading.state.rawValue):\(percent) \(reading.reason)\(reset)")
    }
}
