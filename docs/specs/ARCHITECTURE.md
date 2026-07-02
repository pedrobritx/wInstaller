# Architecture

## Overview

wInstaller is a native macOS app with a SwiftUI assistant shell, a pure Swift planning engine, and narrow adapters around system tools such as `diskutil`, `hdiutil`, and `wimlib-imagex`.

The core rule: business logic must be testable without touching a real disk.

## App Layers

### Presentation

- SwiftUI app shell.
- Assistant sidebar and step content.
- Native sheets, alerts, file importers, progress views, and toolbars.
- AppKit bridges only for macOS integrations that SwiftUI cannot represent cleanly.

### Application

- Coordinates the assistant flow.
- Owns user intent and confirmation state.
- Starts and cancels long-running tasks.
- Converts engine events into user-facing progress.

### Domain

- ISO analysis model.
- USB drive model.
- Boot strategy model.
- Bootable USB state machine.
- Validation results.
- Error taxonomy.

### Infrastructure

- Command runner.
- Disk utility adapter.
- ISO mount adapter.
- File copy adapter.
- WIM splitting adapter.
- Virtualization detection adapter.
- Local logging adapter.

## Suggested Modules

- `WInstallerApp`: SwiftUI entry point and window configuration.
- `AssistantFlow`: screen state, navigation rules, and view models.
- `DesignSystem`: shared UI components, symbols, spacing, and materials.
- `ISOAnalysis`: ISO mounting, inspection, and operating system detection.
- `DiskManagement`: disk enumeration, safety filtering, formatting, ejecting.
- `BootableUSBEngine`: command planning and state transitions.
- `TerminalAutomation`: command execution, parsing, logging, and redaction.
- `VirtualizationIntegration`: VMware Fusion and other app detection.
- `Security`: confirmation gates, permission policy, and privileged operation boundaries.
- `TestSupport`: fixtures, fake command runners, and dry-run helpers.

## Domain Models

### InstallerISO

- `url`
- `displayName`
- `size`
- `volumeLabel`
- `detectedOS`
- `confidence`
- `mountPoint`
- `windowsImageInfo`
- `bootFiles`

### USBDrive

- `bsdIdentifier`
- `displayName`
- `mediaName`
- `size`
- `isRemovable`
- `isInternal`
- `connectionType`
- `partitionScheme`
- `fileSystem`
- `volumes`

### BootStrategy

- `targetPartitionScheme`
- `targetFileSystem`
- `requiresErase`
- `requiresWimSplit`
- `estimatedOperations`
- `warnings`

### OperationPlan

- `steps`
- `destructiveSteps`
- `requiresAuthorization`
- `estimatedBytesToCopy`
- `validationChecks`

## State Machine

The engine exposes explicit states:

- `idle`
- `analyzingISO`
- `waitingForUSB`
- `analyzingUSB`
- `planning`
- `awaitingEraseConfirmation`
- `preparingDrive`
- `copyingFiles`
- `splittingWIM`
- `validating`
- `ejecting`
- `completed`
- `failed`
- `cancelled`

No view should infer progress from raw command strings. The engine emits typed events.

## Command Runner

The command runner must support:

- Dry-run planning.
- Structured output capture.
- Standard error capture.
- Exit status.
- Timeouts.
- Cancellation.
- Redaction before display or export.

Commands must be represented as argument arrays, not shell-interpolated strings.

## Error Taxonomy

- `permissionDenied`
- `diskNotFound`
- `diskNotRemovable`
- `insufficientCapacity`
- `isoMountFailed`
- `isoUnsupported`
- `formatFailed`
- `copyFailed`
- `wimSplitFailed`
- `validationFailed`
- `ejectFailed`
- `toolMissing`
- `cancelledByUser`
- `unknown`

Each error should include a user message, technical message, recovery options, and optional log references.

## Concurrency

- Long tasks run in cancellable Swift tasks.
- UI updates happen on the main actor.
- Engine work should report progress through async sequences or equivalent typed event streams.
- Cancellation should be best-effort and honest. If an operation cannot be interrupted safely, the UI says so.

## Persistence

First release persistence should be minimal:

- Last opened directory.
- Non-sensitive user preferences.
- Recent successful operation summaries if explicitly useful.

Do not store ISO contents, checksums of private files unless user initiated, or raw disk inventories longer than necessary.

## Testing Strategy

- Pure unit tests for state transitions.
- Fixture tests for `diskutil` and `hdiutil` parsing.
- Dry-run tests for command plan generation.
- Fake command runner tests for failure recovery.
- UI tests for the assistant flow.

## Implementation Map

The layers above map to these source files:

- Domain + planner: `Sources/WInstallerCore/WInstallerCore.swift`
  (`BootableUSBEngine`, models, error taxonomy).
- Command runner: `CommandRunner.swift` (`CommandRunning`, `ProcessCommandRunner`,
  `DryRunCommandRunner`).
- Disk management: `DiskEnumerator.swift` (`diskutil -plist` parsing + filtering).
- ISO analysis: `ISOInspector.swift` (`hdiutil` mount + directory scan).
- Execution: `OperationExecutor.swift` (actor; streams typed `EngineEvent`s,
  re-checks disk identity before erase).
- Virtualization: `VirtualizationDetector.swift` (injectable `ApplicationLocating`).
- Logging: `LocalLogger.swift` (actor; redacted local transcript).
- Presentation: `Sources/WInstallerApp/` — `AssistantModel` (flow coordinator),
  `DesignSystem/` (Liquid Glass), `Components.swift`, `Steps.swift`.

