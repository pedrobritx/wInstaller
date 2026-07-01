import Foundation

/// A single local log entry. No ISO contents, license keys, or unrelated disk
/// contents are ever recorded (`TERMINAL_AUTOMATION.md` logging rules).
public struct LogEntry: Sendable, Codable, Equatable {
    public var timestamp: Date
    public var operationID: String
    public var tool: String
    public var arguments: [String]
    public var exitCode: Int32?
    public var userMessage: String
    public var technicalDetail: String?

    public init(
        timestamp: Date = Date(),
        operationID: String,
        tool: String,
        arguments: [String] = [],
        exitCode: Int32? = nil,
        userMessage: String,
        technicalDetail: String? = nil
    ) {
        self.timestamp = timestamp
        self.operationID = operationID
        self.tool = tool
        self.arguments = arguments
        self.exitCode = exitCode
        self.userMessage = userMessage
        self.technicalDetail = technicalDetail
    }
}

/// Local-only logging (`REQ-LOG-001..004`). Logs are stored under Application
/// Support and can be exported with home-directory paths redacted.
public actor LocalLogger {
    private let fileURL: URL?
    private var entries: [LogEntry] = []

    public init(directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory()
        if let base {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            self.fileURL = base.appendingPathComponent("winstaller.log")
        } else {
            self.fileURL = nil
        }
    }

    public func record(_ entry: LogEntry) {
        entries.append(entry)
        persist()
    }

    public var allEntries: [LogEntry] { entries }

    /// A redacted, human-readable transcript suitable for support bundles.
    public func exportText() -> String {
        entries.map(Self.format).joined(separator: "\n")
    }

    private func persist() {
        guard let fileURL else { return }
        let text = entries.map(Self.format).joined(separator: "\n")
        try? text.data(using: .utf8)?.write(to: fileURL, options: .atomic)
    }

    static func format(_ entry: LogEntry) -> String {
        let formatter = ISO8601DateFormatter()
        let time = formatter.string(from: entry.timestamp)
        let args = redact(entry.arguments.joined(separator: " "))
        let exit = entry.exitCode.map { " exit=\($0)" } ?? ""
        var line = "[\(time)] \(entry.operationID) \(entry.tool) \(args)\(exit) — \(entry.userMessage)"
        if let detail = entry.technicalDetail, !detail.isEmpty {
            line += "\n    " + redact(detail).replacingOccurrences(of: "\n", with: "\n    ")
        }
        return line
    }

    /// Redacts the current user's home directory and any `/Users/<name>` prefix.
    static func redact(_ string: String) -> String {
        var result = string
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if !home.isEmpty {
            result = result.replacingOccurrences(of: home, with: "~")
        }
        if let regex = try? NSRegularExpression(pattern: "/Users/[^/ ]+", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "/Users/<redacted>")
        }
        return result
    }

    private static func defaultDirectory() -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return support.appendingPathComponent("wInstaller/logs", isDirectory: true)
    }
}
