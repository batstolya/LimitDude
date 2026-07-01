import Foundation
import LimitDudeCore

public final class CodexTaskSnapshotProvider {
    private let databasePath: String

    public init(databasePath: String = "\(NSHomeDirectory())/.codex/state_5.sqlite") {
        self.databasePath = databasePath
    }

    public func recentTasks(limit: Int = 8) -> [CodexTaskSnapshot] {
        guard FileManager.default.fileExists(atPath: databasePath) else { return [] }

        let rows = queryRecentThreadRows(limit: limit)
        return rows.compactMap { row in
            guard row.count >= 3 else { return nil }
            let id = row[0]
            let rolloutPath = row[1]
            let title = row[2].isEmpty ? "Codex task" : row[2]
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: rolloutPath),
                  let fileSize = attributes[.size] as? UInt64,
                  let modifiedAt = attributes[.modificationDate] as? Date else {
                return nil
            }

            return CodexTaskSnapshot(
                id: id,
                title: title,
                rolloutPath: rolloutPath,
                fileSize: fileSize,
                modifiedAt: modifiedAt,
                completionMarker: latestCompletionMarker(in: rolloutPath)
            )
        }
    }

    private func queryRecentThreadRows(limit: Int) -> [[String]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            "-separator", "\u{1f}",
            databasePath,
            """
            select id, rollout_path, coalesce(nullif(title,''), nullif(first_user_message,''), 'Codex task')
            from threads
            where archived = 0
            order by updated_at desc
            limit \(max(1, min(limit, 30)));
            """
        ]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text
            .split(separator: "\n")
            .map { line in
                line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            }
    }

    private func latestCompletionMarker(in rolloutPath: String) -> String? {
        guard let data = tailData(path: rolloutPath, byteLimit: 160_000),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        for line in text.split(separator: "\n").reversed() {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "task_complete" else {
                continue
            }

            let timestamp = object["timestamp"] as? String ?? "unknown-time"
            let turnID = payload["turn_id"] as? String ?? rolloutPath
            return "\(turnID):\(timestamp)"
        }

        return nil
    }

    private func tailData(path: String, byteLimit: UInt64) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return nil
        }

        defer {
            try? handle.close()
        }

        do {
            let size = try handle.seekToEnd()
            let offset = size > byteLimit ? size - byteLimit : 0
            try handle.seek(toOffset: offset)
            return try handle.readToEnd()
        } catch {
            return nil
        }
    }
}
