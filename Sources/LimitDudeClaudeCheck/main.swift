import Foundation
import LimitDudeMac

@main
struct LimitDudeClaudeCheck {
    @MainActor
    static func main() {
        let reading = ClaudeDesktopAccessibilityProvider().read()
        print("\(reading.state.rawValue): \(reading.reason)")
    }
}
