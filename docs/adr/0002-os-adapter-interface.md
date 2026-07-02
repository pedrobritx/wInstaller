# ADR-0002: OS Adapter Interface

## Status

Accepted.

## Context

The shared Rust core (ADR-0001) needs exactly one seam between OS-agnostic domain
logic (the state machine, planning rules, error taxonomy) and OS-specific system
calls (disk enumeration, ISO mounting, formatting, copying, ejecting). The current
Swift codebase already has this shape informally: `OperationExecutor` depends on
the `CommandRunning` protocol (`CommandRunner.swift`) rather than calling
`Process` directly, and tests inject a `DryRunCommandRunner`. This ADR formalizes
that pattern for the Rust core and extends it to cover all three target OSes.

## Decision

Define a single trait in `core/src/adapter.rs`:

```rust
#[async_trait]
pub trait SystemAdapter: Send + Sync {
    async fn enumerate_removable_drives(&self) -> Result<Vec<UsbDrive>, EngineError>;
    async fn drive_identity(&self, id: &DriveId) -> Result<UsbDrive, EngineError>;
    async fn mount_iso(&self, path: &Path) -> Result<MountedIso, EngineError>;
    async fn inspect_iso(&self, mounted: &MountedIso) -> Result<InstallerIso, EngineError>;
    async fn unmount_iso(&self, mounted: &MountedIso) -> Result<(), EngineError>;
    async fn erase_and_format(&self, target: &DriveId, strategy: &BootStrategy) -> Result<(), EngineError>;
    async fn copy_files(&self, source: &Path, dest: &Path, progress: ProgressSink) -> Result<(), EngineError>;
    async fn split_wim(&self, wim_path: &Path, dest_dir: &Path, progress: ProgressSink) -> Result<(), EngineError>;
    async fn validate_boot_files(&self, volume: &Path) -> Result<ValidationReport, EngineError>;
    async fn eject(&self, target: &DriveId) -> Result<(), EngineError>;
    async fn detect_virtualization_apps(&self) -> Result<Vec<VirtualizationApp>, EngineError>;
}
```

The engine/orchestration code (the `OperationExecutor` equivalent) depends only on
`Box<dyn SystemAdapter>`, never on a concrete OS implementation — mirroring how
today's `OperationExecutor` depends on `CommandRunning`, not `Process`.

Three concrete implementations live behind this one interface:

- `core/src/adapters/macos.rs` — `diskutil list/info -plist`, `hdiutil attach
  -readonly -nobrowse -plist`, `wimlib-imagex`, `rsync` (same tools as today).
- `core/src/adapters/windows.rs` — `Get-Disk`/`Get-Volume` PowerShell (`-Output
  Json`), `diskpart` (scripted via stdin) for erase/format, `Mount-DiskImage` for
  ISO mount, DISM (`Export-WindowsImage`/`Split-WindowsImage`) with
  `wimlib-imagex` as a documented fallback.
- `core/src/adapters/linux.rs` — `lsblk --json -O`, `udisksctl`/`parted --script`
  for erase/format, `udisksctl loop-setup`/`mount -o loop` for ISO mount,
  `wimlib-imagex` (already cross-platform).

A fourth implementation, `DryRunAdapter`, is the direct Rust analog of
`DryRunCommandRunner` — used by tests and by the app's Simulate toggle.

## Testing strategy

Every adapter's *parsing* logic is a pure function (fixture text/JSON in, typed
struct out), matching `Tests/WInstallerCoreTests/`'s existing pattern. This means
all three adapters' parsers are unit-testable on **any single CI runner**, not
just the OS they target. Fixtures live under `core/tests/fixtures/{macos,windows,
linux}/`. Only the small number of tests that actually invoke `diskutil`/
`Get-Disk`/`lsblk` need the matching OS runner, and those are `#[ignore]`-by-
default, manual, and clearly labeled per the existing rule in `AI_RULES.md`
("Real-disk tests must be manual, isolated, and clearly labeled").

## Consequences

- Adding a new OS-specific concern (e.g. a new elevation model) never touches
  `engine.rs`; it is scoped to one adapter file.
- A safety-gate change (e.g. the pre-erase identity recheck) is written once, in
  the engine, and is applied identically regardless of which adapter is in use —
  it cannot silently diverge per platform.
- New parsing bugs are caught by fixture tests before they reach any OS-specific
  CI runner.
