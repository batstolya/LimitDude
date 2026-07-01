# Claude Limit Dude Design

## Goal

Build a small macOS utility that watches Claude Desktop limit state and shows a pixel character animation when limits become available again.

## Scope

The first version targets Claude Desktop on macOS. It creates a menu bar app with a transparent overlay animation, a polling loop, and a Claude Desktop detector based on macOS Accessibility text. Codex support is explicitly out of scope for this first version, but the detector API is provider-shaped so Codex can be added later without changing the animation layer.

## Architecture

The app is a Swift Package with one executable and one testable core library.

- `LimitDudeCore` owns limit text classification and state transitions.
- `LimitDude` owns the macOS menu bar app, Claude Desktop polling, Accessibility text collection, and overlay animation.
- Providers return `LimitReading` values. The app reacts only to state transitions, not provider-specific details.

## Claude Desktop Detection

The detector looks for a running app with bundle id `com.anthropic.claudefordesktop`. If Claude is not running, the reading is `.unknown`.

When Claude is running, the app reads exposed Accessibility text from Claude windows. If the text contains limit phrases such as `limit reached`, `message limit`, `try again`, or `available at`, the reading is `.limited`. If text is readable and does not contain those phrases, the reading is `.available`.

If Accessibility permission is missing or no readable text is exposed, the reading is `.unknown` with a short reason shown in the menu.

## Animation

The animation is a borderless, transparent, non-activating overlay window. It draws a pixel-art character inspired by the reference image directly in AppKit, using blocky rectangles so there are no external image assets.

The first animation sequence:

1. Start hidden just below the bottom of the main screen.
2. Rise into view.
3. Bounce twice.
4. Blink a small black antenna/checker shape.
5. Drop out of view and close the overlay window.

The overlay must not steal focus from Claude or other apps.

## Menu Bar UX

The menu bar item shows the current state:

- `Checking` while a poll is in progress.
- `Limited` when a Claude limit phrase is detected.
- `Available` when Claude text is readable and no limit phrase is found.
- `Unknown` when Claude is closed, permission is missing, or text cannot be read.

The menu includes:

- `Check Now`
- `Show Dude`
- `Simulate Limited`
- `Simulate Reset`
- `Quit`

Simulation controls are part of the first version so the animation can be verified before relying on live Claude detection.

## State Rules

Only one transition triggers the animation:

- Previous stable state was `.limited`.
- New reading is `.available`.

The animation does not trigger on app launch if the first reading is `.available`, and it does not repeatedly trigger while state remains `.available`.

## Testing

Automated tests cover:

- Classifying representative Claude limit text as `.limited`.
- Classifying readable non-limit text as `.available`.
- Returning `.unknown` for empty or inaccessible text.
- Triggering animation only on `.limited -> .available`.

Manual verification covers:

- `swift test`
- `swift build`
- Running the app with `swift run LimitDude`
- Using `Simulate Limited` then `Simulate Reset` to see the overlay.
- Granting Accessibility permission and using `Check Now` with Claude Desktop open.

## Future Expansion

Codex support should be added as another provider conforming to the same provider shape. The state machine, overlay animation, and menu controls should not need structural changes.
