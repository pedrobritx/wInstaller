import Foundation

/// The result of running a single command.
///
/// Command output is treated as untrusted input (see `TERMINAL_AUTOMATION.md`).
/// Callers must parse it defensively and never evaluate it as code.
public struct CommandResult: Sendable, Equatable {
    public var executable: String
    public var arguments: [String]
    public var standardOutput: Data
    public var standardError: Data
    public var exitCode: Int32
    public var startedAt: Date
    public var finishedAt: Date

    public init(
        executable: String,
        arguments: [String],
        standardOutput: Data,
        standardError: Data,
        exitCode: Int32,
        startedAt: Date,
        finishedAt: Date
    ) {
        self.executable = executable
        self.arguments = arguments
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    public var succeeded: Bool { exitCode == 0 }

    public var standardOutputString: String {
        String(decoding: standardOutput, as: UTF8.self)
    }

    public var standardErrorString: String {
        String(decoding: standardError, as: UTF8.self)
    }
}

/// Timeout classes recommended by `TERMINAL_AUTOMATION.md`.
public enum CommandTimeout: Sendable {
    /// Fast metadata command (10s).
    case metadata
    /// Mount / unmount (60s).
    case mount
    /// Format (120s).
    case format
    /// Eject (60s).
    case eject
    /// Long-running work watched by a progress watchdog rather than a hard timeout.
    case watched
    /// Explicit override in seconds.
    case seconds(TimeInterval)

    public var interval: TimeInterval? {
        switch self {
        case .metadata: 10
        case .mount, .eject: 60
        case .format: 120
        case .watched: nil
        case .seconds(let value): value
        }
    }
}

/// A minimal thread-safe flag used to signal a timeout across the watchdog task.
final class BoolBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

public enum CommandRunnerError: Error, Equatable, Sendable {
    case launchFailed(String)
    case timedOut(executable: String, seconds: TimeInterval)
    case cancelled
    case nonZeroExit(executable: String, exitCode: Int32, standardError: String)
}

/// Abstraction over command execution so the whole pipeline stays testable
/// without touching a real disk. Commands are always represented as an
/// executable plus an argument array — never a shell-interpolated string.
public protocol CommandRunning: Sendable {
    func run(_ command: PlannedCommand, timeout: CommandTimeout) async throws -> CommandResult
}

public extension CommandRunning {
    func run(_ command: PlannedCommand) async throws -> CommandResult {
        try await run(command, timeout: .metadata)
    }
}

/// Executes commands for real with Foundation `Process`. Captures stdout/stderr
/// and exit status, supports Task cancellation, and enforces the timeout classes
/// above.
///
/// Output is redirected to temporary files rather than pipes so a large stream
/// (e.g. `rsync --info=progress2`) cannot deadlock against a full pipe buffer.
public final class ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ command: PlannedCommand, timeout: CommandTimeout) async throws -> CommandResult {
        try Task.checkCancellation()

        let tmp = FileManager.default.temporaryDirectory
        let outURL = tmp.appendingPathComponent("winstaller-\(UUID().uuidString).out")
        let errURL = tmp.appendingPathComponent("winstaller-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: outURL)
            try? FileManager.default.removeItem(at: errURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.standardOutput = try FileHandle(forWritingTo: outURL)
        process.standardError = try FileHandle(forWritingTo: errURL)

        let startedAt = Date()
        // `process` is confined to this call; terminate() from the cancellation
        // and timeout handlers is safe.
        nonisolated(unsafe) let proc = process

        // Timeout watchdog.
        let timeoutFlag = BoolBox()
        let timeoutTask: Task<Void, Never>? = timeout.interval.map { interval in
            Task {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if proc.isRunning {
                    timeoutFlag.value = true
                    proc.terminate()
                }
            }
        }

        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    proc.terminationHandler = { _ in continuation.resume() }
                    do {
                        try proc.run()
                    } catch {
                        proc.terminationHandler = nil
                        continuation.resume(throwing: CommandRunnerError.launchFailed(error.localizedDescription))
                    }
                }
            } onCancel: {
                if proc.isRunning { proc.terminate() }
            }
        } catch {
            timeoutTask?.cancel()
            throw error
        }
        timeoutTask?.cancel()
        let timedOut = timeoutFlag.value

        let result = CommandResult(
            executable: command.executable,
            arguments: command.arguments,
            standardOutput: (try? Data(contentsOf: outURL)) ?? Data(),
            standardError: (try? Data(contentsOf: errURL)) ?? Data(),
            exitCode: process.terminationStatus,
            startedAt: startedAt,
            finishedAt: Date()
        )

        if Task.isCancelled { throw CommandRunnerError.cancelled }
        if timedOut, let interval = timeout.interval {
            throw CommandRunnerError.timedOut(executable: command.executable, seconds: interval)
        }
        return result
    }
}

/// Records commands and returns canned output. Used by tests and the
/// user-facing "Simulate (dry-run)" mode so no destructive command ever runs.
public final class DryRunCommandRunner: CommandRunning, @unchecked Sendable {
    public struct Stub: Sendable {
        public var standardOutput: Data
        public var standardError: Data
        public var exitCode: Int32

        public init(standardOutput: Data = Data(), standardError: Data = Data(), exitCode: Int32 = 0) {
            self.standardOutput = standardOutput
            self.standardError = standardError
            self.exitCode = exitCode
        }

        public static func text(_ string: String, exitCode: Int32 = 0) -> Stub {
            Stub(standardOutput: Data(string.utf8), exitCode: exitCode)
        }
    }

    private let lock = NSLock()
    private var _invocations: [PlannedCommand] = []
    private let responder: @Sendable (PlannedCommand) -> Stub

    /// - Parameter responder: Supplies canned output per command. Defaults to a
    ///   successful empty result, which is enough to exercise the state machine.
    public init(responder: @escaping @Sendable (PlannedCommand) -> Stub = { _ in Stub() }) {
        self.responder = responder
    }

    public var invocations: [PlannedCommand] {
        lock.withLock { _invocations }
    }

    public func run(_ command: PlannedCommand, timeout: CommandTimeout) async throws -> CommandResult {
        try Task.checkCancellation()
        lock.withLock { _invocations.append(command) }
        let stub = responder(command)
        let now = Date()
        return CommandResult(
            executable: command.executable,
            arguments: command.arguments,
            standardOutput: stub.standardOutput,
            standardError: stub.standardError,
            exitCode: stub.exitCode,
            startedAt: now,
            finishedAt: now
        )
    }
}
