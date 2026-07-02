import Foundation
import LimitDudeCore

public final class CodexRateLimitProvider: @unchecked Sendable {
    private let codexPath = "/Applications/Codex.app/Contents/Resources/codex"

    public init() {}

    public func read() -> LimitReading {
        guard FileManager.default.isExecutableFile(atPath: codexPath) else {
            return .unknown(reason: "Codex CLI was not found inside Codex.app")
        }

        do {
            let output = try requestRateLimits()
            guard let result = responseResult(withID: 2, in: output) else {
                return .unknown(reason: "Codex did not return rate limit data")
            }
            return classify(result: result)
        } catch {
            return .unknown(reason: "Codex rate limit check failed: \(error.localizedDescription)")
        }
    }

    private func requestRateLimits() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--stdio"]

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        try process.run()

        let stdoutBuffer = PipeTextBuffer()
        let stderrBuffer = PipeTextBuffer()
        let initialized = DispatchSemaphore(value: 0)
        let gotRateLimits = DispatchSemaphore(value: 0)

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = stdoutBuffer.appendAndRead(data)
            let hasInitialized = text.split(separator: "\n").contains { line in
                line.contains(#""id":1"#)
            }
            let hasRateLimits = text.split(separator: "\n").contains { line in
                line.contains(#""id":2"#)
            }

            if hasInitialized {
                initialized.signal()
            }

            if hasRateLimits {
                gotRateLimits.signal()
            }
        }

        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stderrBuffer.append(data)
        }

        writeJSONLine(
            """
            {"id":1,"method":"initialize","params":{"clientInfo":{"name":"limit-dude","title":"Limit Dude","version":"0.1"},"capabilities":{"experimentalApi":true,"requestAttestation":false,"optOutNotificationMethods":[]}}}
            """,
            to: input
        )

        guard initialized.wait(timeout: .now() + 8) == .success else {
            input.fileHandleForWriting.closeFile()
            throw CodexRateLimitError.emptyResponse(stderrBuffer.text)
        }

        writeJSONLine(#"{"method":"initialized"}"#, to: input)
        Thread.sleep(forTimeInterval: 0.2)
        writeJSONLine(#"{"id":2,"method":"account/rateLimits/read"}"#, to: input)

        let gotResponse = gotRateLimits.wait(timeout: .now() + 15) == .success
        input.fileHandleForWriting.closeFile()
        let gracefulDeadline = Date().addingTimeInterval(gotResponse ? 2 : 0)
        while process.isRunning && Date() < gracefulDeadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil

        let text = stdoutBuffer.text
        let errorText = stderrBuffer.text.isEmpty ? "empty response" : stderrBuffer.text

        if !text.isEmpty {
            return text
        }

        throw CodexRateLimitError.emptyResponse(errorText)
    }

    private func writeJSONLine(_ text: String, to pipe: Pipe) {
        pipe.fileHandleForWriting.write(Data((text + "\n").utf8))
    }

    private func responseResult(withID id: Int, in text: String) -> [String: Any]? {
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["id"] as? Int == id else {
                continue
            }
            return object["result"] as? [String: Any]
        }
        return nil
    }

    private func classify(result: [String: Any]) -> LimitReading {
        let snapshot = codexSnapshot(from: result)
        guard !snapshot.isEmpty else {
            return .unknown(reason: "Codex returned no codex rate limit bucket")
        }

        let reachedType = snapshot["rateLimitReachedType"] as? String
        let primary = window(named: "5h", from: snapshot["primary"])
        let secondary = window(named: "weekly", from: snapshot["secondary"])
        let windows = [primary, secondary].compactMap { $0 }
        let busiest = windows.max { $0.usedPercent < $1.usedPercent }
        let resetText = busiest.flatMap { formatReset(epochSeconds: $0.resetsAt) }

        if let reachedType {
            return .limited(reason: "Codex limit reached: \(reachedType)", resetText: resetText)
        }

        guard let busiest else {
            return .available(reason: "Codex rate limit bucket is readable")
        }

        let reason = resetText.map {
            "Left: \(remainingSummary(primary: primary, secondary: secondary)). Reset: \($0)"
        } ?? "Left: \(remainingSummary(primary: primary, secondary: secondary))"
        if busiest.usedPercent >= 80 {
            return .warning(reason: reason, usagePercent: busiest.usedPercent, resetText: resetText)
        }

        return LimitReading(state: .available, reason: reason, usagePercent: busiest.usedPercent, resetText: resetText)
    }

    private func codexSnapshot(from result: [String: Any]) -> [String: Any] {
        if let byID = result["rateLimitsByLimitId"] as? [String: Any],
           let codex = byID["codex"] as? [String: Any] {
            return codex
        }
        return result["rateLimits"] as? [String: Any] ?? [:]
    }

    private func window(named name: String, from value: Any?) -> CodexRateLimitWindow? {
        guard let object = value as? [String: Any],
              let usedPercent = object["usedPercent"] as? Int else {
            return nil
        }

        return CodexRateLimitWindow(
            name: name,
            usedPercent: usedPercent,
            resetsAt: object["resetsAt"] as? TimeInterval
        )
    }

    private func remainingSummary(primary: CodexRateLimitWindow?, secondary: CodexRateLimitWindow?) -> String {
        [primary, secondary]
            .compactMap { window in
                window.map { "\($0.name) \(max(0, 100 - $0.usedPercent))%" }
            }
            .joined(separator: ", ")
    }

    private func formatReset(epochSeconds: TimeInterval?) -> String? {
        guard let epochSeconds else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: epochSeconds))
    }
}

private struct CodexRateLimitWindow {
    let name: String
    let usedPercent: Int
    let resetsAt: TimeInterval?
}

private final class PipeTextBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func appendAndRead(_ chunk: Data) -> String {
        lock.lock()
        data.append(chunk)
        let value = String(data: data, encoding: .utf8) ?? ""
        lock.unlock()
        return value
    }
}

private enum CodexRateLimitError: LocalizedError {
    case emptyResponse(String)

    var errorDescription: String? {
        switch self {
        case .emptyResponse(let text):
            return text
        }
    }
}
