import AppKit
import ApplicationServices
import LimitDudeCore

@MainActor
public final class ClaudeDesktopAccessibilityProvider {
    private let bundleIdentifier = "com.anthropic.claudefordesktop"
    private let classifier = ClaudeLimitTextClassifier()

    public init() {}

    public func read() -> LimitReading {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return .unknown(reason: "Claude Desktop is not running")
        }

        guard isAccessibilityTrusted() else {
            return .unknown(reason: "Grant Accessibility permission to read Claude Desktop")
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)

        let windows = elements(from: windowsValue)
        guard result == .success, !windows.isEmpty else {
            return .unknown(reason: "No readable Claude windows")
        }

        let text = windows
            .prefix(4)
            .map { collectText(from: $0, depth: 0) }
            .joined(separator: "\n")

        return classifier.classify(text: text)
    }

    private func isAccessibilityTrusted() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func collectText(from element: AXUIElement, depth: Int) -> String {
        guard depth < 8 else { return "" }

        var fragments: [String] = []
        for attribute in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success {
                if let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    fragments.append(text)
                }
            }
        }

        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success {
            let children = elements(from: childrenValue)
            for child in children.prefix(80) {
                let childText = collectText(from: child, depth: depth + 1)
                if !childText.isEmpty {
                    fragments.append(childText)
                }
            }
        }

        return fragments.joined(separator: "\n")
    }

    private func elements(from value: CFTypeRef?) -> [AXUIElement] {
        guard let value else { return [] }
        let array = value as! NSArray
        return array.compactMap { item -> AXUIElement? in
            let object = item as AnyObject
            guard CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
            return (object as! AXUIElement)
        }
    }
}
