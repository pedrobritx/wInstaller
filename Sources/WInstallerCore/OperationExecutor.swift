import Foundation

public enum ExecutionError: Error, Sendable, Equatable {
    case identityMismatch(expected: String, found: String)
    case refusedInternalDisk
    case mountFailed(String)
    case commandFailed(step: String, exitCode: Int32, message: String)
    case validationFailed([String])
    case cancelled

    public var userMessage: String {
        switch self {
        case .identityMismatch:
            "The USB drive changed since it was confirmed. wInstaller stopped before erasing anything."
        case .refusedInternalDisk:
            "The target became an internal disk. wInstaller refuses to erase internal disks."
        case .mountFailed:
            "wInstaller could not mount the ISO to copy its files."
        case .commandFailed(let step, _, _):
            "A step failed while \(step). See technical details for the command output."
        case .validationFailed(let missing):
            "The bootable USB is missing required files: \(missing.joined(separator: ", "))."
        case .cancelled:
            "The operation was cancelled."
        }
    }
}

/// Executes an `OperationPlan` for real, one step at a time, through a
/// `CommandRunning`. Emits typed `EngineEvent`s so the UI never has to infer
/// progress from raw command strings (`ARCHITECTURE.md`).
///
/// The destructive pipeline follows `TERMINAL_AUTOMATION.md`: the drive identity
/// is re-queried immediately before erase and the run aborts on any mismatch,
/// internal disk, or system disk. Cancellation is honoured before erase and is
/// best-effort afterward.
public actor OperationExecutor {
    public static let targetVolumeName = "WINSTALLER"
    private static let targetVolumePath = "/Volumes/WINSTALLER"

    private let runner: CommandRunning
    private let enumerator: DiskEnumerator
    private let logger: LocalLogger?
    private let fileManager: FileManager
    /// Injectable so tests can assert validation without a real volume.
    private let validateExisting: @Sendable ([String]) -> [String]

    public init(
        runner: CommandRunning = ProcessCommandRunner(),
        enumerator: DiskEnumerator? = nil,
        logger: LocalLogger? = nil,
        fileManager: FileManager = .default,
        validateExisting: (@Sendable ([String]) -> [String])? = nil
    ) {
        self.runner = runner
        self.enumerator = enumerator ?? DiskEnumerator(runner: runner)
        self.logger = logger
        self.fileManager = fileManager
        let fm = fileManager
        self.validateExisting = validateExisting ?? { paths in
            paths.filter { !fm.fileExists(atPath: $0) }
        }
    }

    /// Runs the plan and streams progress. Cancelling the consuming task cancels
    /// the run.
    public nonisolated func run(plan: OperationPlan) -> AsyncThrowingStream<EngineEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.execute(plan: plan, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: ExecutionError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func execute(
        plan: OperationPlan,
        continuation: AsyncThrowingStream<EngineEvent, Error>.Continuation
    ) async throws {
        var mountedDevice: String?
        func cleanup() async {
            if let mountedDevice {
                _ = try? await runner.run(
                    PlannedCommand(executable: ISOInspector.hdiutil, arguments: ["detach", mountedDevice], isDestructive: false),
                    timeout: .mount
                )
            }
        }

        do {
            // 1. Mount the ISO read-only.
            let attach = try await runStep(
                id: "mount-iso", state: .analyzingISO, title: "Mount ISO read-only",
                command: PlannedCommand(
                    executable: ISOInspector.hdiutil,
                    arguments: ["attach", "-readonly", "-nobrowse", "-plist", plan.iso.url.path],
                    isDestructive: false
                ),
                timeout: .mount, continuation: continuation
            )
            let attachment = try ISOInspector.parseAttach(attach.standardOutput)
            mountedDevice = attachment.devEntry
            guard let mountPoint = attachment.mountPoint else {
                throw ExecutionError.mountFailed("no mount point")
            }

            // 2. Re-check the USB identity immediately before any destructive work.
            try Task.checkCancellation()
            let fresh = try await enumerator.info(for: plan.drive.bsdIdentifier)
            guard !fresh.isInternal else { throw ExecutionError.refusedInternalDisk }
            guard fresh.bsdIdentifier == plan.drive.bsdIdentifier,
                  fresh.size == plan.drive.size,
                  fresh.mediaName == plan.drive.mediaName else {
                throw ExecutionError.identityMismatch(expected: plan.drive.bsdIdentifier, found: fresh.bsdIdentifier)
            }
            continuation.yield(EngineEvent(
                id: "verify-usb", state: .analyzingUSB, title: "USB identity re-checked",
                detail: "\(fresh.displayName) (\(fresh.bsdIdentifier)) confirmed.", status: .complete
            ))

            // 3. Unmount the whole disk so it can be formatted.
            _ = try await runStep(
                id: "unmount", state: .preparingDrive, title: "Unmount USB drive",
                command: PlannedCommand(
                    executable: DiskEnumerator.diskutil,
                    arguments: ["unmountDisk", plan.drive.bsdIdentifier],
                    isDestructive: false
                ),
                timeout: .mount, continuation: continuation
            )

            // 4. Erase + format (DESTRUCTIVE).
            _ = try await runStep(
                id: "erase-disk", state: .preparingDrive, title: "Erase and format USB drive",
                command: PlannedCommand(
                    executable: DiskEnumerator.diskutil,
                    arguments: ["eraseDisk", "MS-DOS", Self.targetVolumeName, "GPT", plan.drive.bsdIdentifier],
                    isDestructive: true
                ),
                timeout: .format, continuation: continuation
            )

            // 5. Copy installer files. When a WIM split is required, exclude the
            //    oversized image and split it separately in step 6.
            var rsyncArgs = ["-aE", "--info=progress2"]
            if plan.strategy.requiresWIMSplit {
                rsyncArgs.append("--exclude=sources/install.wim")
                rsyncArgs.append("--exclude=sources/Install.wim")
            }
            rsyncArgs.append(trailingSlash(mountPoint))
            rsyncArgs.append(trailingSlash(Self.targetVolumePath))
            _ = try await runStep(
                id: "copy-files", state: .copyingFiles, title: "Copy installer files",
                command: PlannedCommand(executable: "/usr/bin/rsync", arguments: rsyncArgs, isDestructive: false),
                timeout: .watched, continuation: continuation
            )

            // 6. Split the Windows image when it exceeds the FAT32 file limit.
            if plan.strategy.requiresWIMSplit {
                _ = try await runStep(
                    id: "split-wim", state: .splittingWIM, title: "Split oversized Windows image",
                    command: PlannedCommand(
                        executable: wimlibPath(),
                        arguments: [
                            "split",
                            "\(mountPoint)/sources/install.wim",
                            "\(Self.targetVolumePath)/sources/install.swm",
                            "3800"
                        ],
                        isDestructive: false
                    ),
                    timeout: .watched, continuation: continuation
                )
            }

            // 7. Validate required boot files exist on the target.
            let missing = validateExisting(expectedFiles(for: plan))
            guard missing.isEmpty else {
                continuation.yield(EngineEvent(
                    id: "validate", state: .validating, title: "Boot validation failed",
                    detail: missing.joined(separator: ", "), status: .failed
                ))
                throw ExecutionError.validationFailed(missing)
            }
            continuation.yield(EngineEvent(
                id: "validate", state: .validating, title: "Boot files validated",
                detail: plan.validationChecks.joined(separator: ", "), status: .complete
            ))

            // 8. Eject safely.
            _ = try await runStep(
                id: "eject", state: .ejecting, title: "Eject USB safely",
                command: PlannedCommand(
                    executable: DiskEnumerator.diskutil,
                    arguments: ["eject", plan.drive.bsdIdentifier],
                    isDestructive: false
                ),
                timeout: .eject, continuation: continuation
            )

            await cleanup()
            continuation.yield(EngineEvent(
                id: "completed", state: .completed, title: "Bootable USB ready",
                detail: "\(plan.iso.detectedOS.displayName) on \(plan.drive.displayName).", status: .complete
            ))
        } catch {
            await cleanup()
            throw error
        }
    }

    private func runStep(
        id: String,
        state: EngineState,
        title: String,
        command: PlannedCommand,
        timeout: CommandTimeout,
        continuation: AsyncThrowingStream<EngineEvent, Error>.Continuation
    ) async throws -> CommandResult {
        try Task.checkCancellation()
        continuation.yield(EngineEvent(id: id, state: state, title: title, detail: "Running…", status: .running))

        let result = try await runner.run(command, timeout: timeout)
        await logger?.record(LogEntry(
            operationID: id,
            tool: command.executable,
            arguments: command.arguments,
            exitCode: result.exitCode,
            userMessage: title,
            technicalDetail: result.standardErrorString
        ))

        guard result.succeeded else {
            continuation.yield(EngineEvent(id: id, state: .failed, title: title, detail: "Failed (exit \(result.exitCode)).", status: .failed))
            throw ExecutionError.commandFailed(step: title, exitCode: result.exitCode, message: result.standardErrorString)
        }

        continuation.yield(EngineEvent(id: id, state: state, title: title, detail: "Complete.", status: .complete))
        return result
    }

    private func expectedFiles(for plan: OperationPlan) -> [String] {
        let root = Self.targetVolumePath
        switch plan.iso.detectedOS {
        case .windows:
            var files = ["\(root)/sources/boot.wim", "\(root)/efi"]
            if plan.strategy.requiresWIMSplit {
                files.append("\(root)/sources/install.swm")
            } else {
                files.append("\(root)/sources/install.wim")
            }
            return files
        case .linux:
            return ["\(root)"]
        case .unknown:
            return ["\(root)"]
        }
    }

    private func trailingSlash(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }

    private func wimlibPath() -> String {
        for candidate in ["/opt/homebrew/bin/wimlib-imagex", "/usr/local/bin/wimlib-imagex"] {
            if fileManager.fileExists(atPath: candidate) { return candidate }
        }
        return "/opt/homebrew/bin/wimlib-imagex"
    }
}
