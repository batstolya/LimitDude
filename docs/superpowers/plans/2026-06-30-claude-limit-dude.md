# Claude Limit Dude Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar utility that detects Claude Desktop limit recovery and shows a pixel character overlay animation.

**Architecture:** A Swift Package contains a testable `LimitDudeCore` library and a `LimitDude` AppKit executable. Core classifies provider readings and decides when animation should fire; the executable polls Claude Desktop through Accessibility and renders a non-activating overlay window.

**Tech Stack:** Swift 6, Swift Package Manager, AppKit, ApplicationServices Accessibility APIs, XCTest.

## Global Constraints

- Platform target is macOS 13 or newer.
- Claude Desktop bundle id is `com.anthropic.claudefordesktop`.
- First version must include simulation controls for manual animation verification.
- The overlay must not steal app focus.
- Animation triggers only on `.limited -> .available`.
- Codex detection is future scope and must be isolated behind provider-shaped interfaces.

---

## File Structure

- `Package.swift`: declares `LimitDudeCore`, `LimitDude`, and tests.
- `Sources/LimitDudeCore/LimitReading.swift`: shared state model.
- `Sources/LimitDudeCore/ClaudeLimitTextClassifier.swift`: maps readable Claude text to `LimitReading`.
- `Sources/LimitDudeCore/LimitRecoveryMonitor.swift`: tracks readings and emits animation triggers.
- `Tests/LimitDudeCoreTests/LimitDudeCoreTests.swift`: core behavior tests.
- `Sources/LimitDude/main.swift`: app entrypoint.
- `Sources/LimitDude/AppDelegate.swift`: status item, polling loop, menu actions.
- `Sources/LimitDude/ClaudeDesktopAccessibilityProvider.swift`: Claude process/window Accessibility text reader.
- `Sources/LimitDude/PixelDudeOverlay.swift`: transparent overlay window and pixel-art animation view.

### Task 1: Core State Logic

**Files:**
- Create: `Package.swift`
- Create: `Sources/LimitDudeCore/LimitReading.swift`
- Create: `Sources/LimitDudeCore/ClaudeLimitTextClassifier.swift`
- Create: `Sources/LimitDudeCore/LimitRecoveryMonitor.swift`
- Test: `Tests/LimitDudeCoreTests/LimitDudeCoreTests.swift`

**Interfaces:**
- Produces: `enum LimitState`, `struct LimitReading`, `struct ClaudeLimitTextClassifier`, `final class LimitRecoveryMonitor`.
- Consumes: no earlier project files.

- [ ] Write tests for text classification and transition triggering.
- [ ] Run `swift test` and verify the tests fail because the package/core code is not implemented.
- [ ] Implement the core library.
- [ ] Run `swift test` and verify the tests pass.

### Task 2: Menu Bar App Shell

**Files:**
- Create: `Sources/LimitDude/main.swift`
- Create: `Sources/LimitDude/AppDelegate.swift`

**Interfaces:**
- Consumes: `LimitReading`, `LimitState`, and `LimitRecoveryMonitor` from Task 1.
- Produces: a menu bar app with actions `checkNow`, `simulateLimited`, `simulateReset`, `showDude`, and `quit`.

- [ ] Add an AppKit `NSApplication` entrypoint.
- [ ] Add an `NSStatusItem` menu with the required controls.
- [ ] Wire simulation actions through `LimitRecoveryMonitor`.
- [ ] Build with `swift build`.

### Task 3: Pixel Overlay Animation

**Files:**
- Create: `Sources/LimitDude/PixelDudeOverlay.swift`
- Modify: `Sources/LimitDude/AppDelegate.swift`

**Interfaces:**
- Consumes: menu actions and monitor trigger from Task 2.
- Produces: `final class PixelDudeOverlay` with `show()`.

- [ ] Implement a borderless transparent overlay window.
- [ ] Draw the reference-inspired pixel character using AppKit rectangles.
- [ ] Animate rise, bounce, blink, and exit without activating the app.
- [ ] Build with `swift build`.

### Task 4: Claude Desktop Provider

**Files:**
- Create: `Sources/LimitDude/ClaudeDesktopAccessibilityProvider.swift`
- Modify: `Sources/LimitDude/AppDelegate.swift`

**Interfaces:**
- Consumes: `ClaudeLimitTextClassifier.classify(text:)`.
- Produces: `final class ClaudeDesktopAccessibilityProvider` with `read() -> LimitReading`.

- [ ] Find the running Claude Desktop app by bundle id.
- [ ] Request/check Accessibility trust.
- [ ] Walk Claude windows and collect `AXTitle`, `AXValue`, and selected child text.
- [ ] Classify collected text and update menu state.
- [ ] Build with `swift build`.

### Task 5: Verification

**Files:**
- Verify all files above.

**Interfaces:**
- Consumes: complete implementation.
- Produces: verified local commands and run instructions.

- [ ] Run `swift test`.
- [ ] Run `swift build`.
- [ ] Run `swift run LimitDude` for manual verification if a GUI session is available.
- [ ] Document how to grant Accessibility permission if Claude text cannot be read.

## Plan Self-Review

- Spec coverage: the plan covers the provider-shaped core, Claude Desktop detection, menu bar controls, overlay animation, simulation, and verification.
- Placeholder scan: no placeholder requirements are left.
- Type consistency: provider returns `LimitReading`; monitor consumes `LimitReading`; AppDelegate calls overlay only on monitor trigger.
