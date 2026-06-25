# Requirements

## Functional Requirements

### ISO Handling

- REQ-ISO-001: Let the user choose an `.iso` file through a native file importer.
- REQ-ISO-002: Reject unsupported file types before analysis.
- REQ-ISO-003: Mount the ISO read-only for analysis.
- REQ-ISO-004: Detect Windows installation media by expected setup files and source layout.
- REQ-ISO-005: Detect Linux installation media by known boot directories and metadata when available.
- REQ-ISO-006: Surface ISO name, size, volume label, detected operating system, and confidence level.
- REQ-ISO-007: Unmount the ISO after analysis or completion.
- REQ-ISO-008: Support checksum display when the user provides or imports a checksum.

### USB Detection

- REQ-USB-001: Enumerate physical disks using structured command output.
- REQ-USB-002: Show only removable external drives by default.
- REQ-USB-003: Allow advanced users to reveal additional disks only after a warning.
- REQ-USB-004: Display device name, BSD identifier, capacity, connection type, partition scheme, and current filesystem.
- REQ-USB-005: Refuse to erase internal system disks.
- REQ-USB-006: Require explicit user selection before any disk operation.

### Destructive Confirmation

- REQ-CONFIRM-001: Before erasing, show the exact drive name, identifier, and capacity.
- REQ-CONFIRM-002: Require the user to type the drive name or use an equivalent high-friction native confirmation.
- REQ-CONFIRM-003: Provide a final cancel path with no side effects.
- REQ-CONFIRM-004: Record a local log entry that confirmation occurred, without storing sensitive file contents.

### Bootable USB Creation

- REQ-BOOT-001: Plan the required operations before executing them.
- REQ-BOOT-002: Format the selected USB drive using a boot-compatible partition and filesystem strategy.
- REQ-BOOT-003: Copy all required ISO files to the USB drive.
- REQ-BOOT-004: Detect Windows `install.wim` files larger than FAT32's single-file limit.
- REQ-BOOT-005: Split oversized WIM files into `.swm` files.
- REQ-BOOT-006: Preserve required boot directory structure.
- REQ-BOOT-007: Validate that required boot files exist after copying.
- REQ-BOOT-008: Eject the USB safely when complete.

### VMware and Virtualization Handoff

- REQ-VM-001: Detect VMware Fusion if installed.
- REQ-VM-002: Provide a guided next-step checklist for VMware Fusion.
- REQ-VM-003: Detect UTM, Parallels Desktop, and VirtualBuddy as optional future integrations.
- REQ-VM-004: Never create, modify, or start a virtual machine without clear user intent.

### Logging and Diagnostics

- REQ-LOG-001: Store logs locally.
- REQ-LOG-002: Separate user-readable status from raw command output.
- REQ-LOG-003: Redact home-directory paths from exported support bundles when possible.
- REQ-LOG-004: Let users reveal technical details for troubleshooting.

### Help

- REQ-HELP-001: Include a local user guide.
- REQ-HELP-002: Explain common issues: missing USB, wrong filesystem, WIM splitting, insufficient capacity, copy failure, mount failure, and permission failure.
- REQ-HELP-003: Link to official vendor resources only when useful and clearly labeled.

## Non-Functional Requirements

- NFR-001: All ISO and USB operations happen locally.
- NFR-002: The app has no telemetry by default.
- NFR-003: The app must remain responsive during long operations.
- NFR-004: Long operations must support cancellation where the underlying operation can safely be cancelled.
- NFR-005: The app must support VoiceOver labels for every control.
- NFR-006: The app must support keyboard navigation through the full assistant flow.
- NFR-007: The app must respect Reduce Motion and Reduce Transparency.
- NFR-008: The app must support light mode, dark mode, and high contrast.
- NFR-009: The app must produce deterministic command plans in dry-run mode.
- NFR-010: The app must avoid deprecated APIs.

## Platform Requirements

- Target macOS 26+ for the first design pass.
- Use Swift 6.
- Use SwiftUI for the app shell and primary screens.
- Use AppKit only when SwiftUI cannot express a required macOS integration.
- Support Apple Silicon and Intel Macs when the chosen dependencies allow it.

## Distribution Requirements

- Initial distribution may be direct download with Developer ID signing and notarization.
- Mac App Store feasibility must be evaluated before promising Store release because raw disk operations and privileged workflows can conflict with sandbox constraints.
- Release builds must include a signed and notarized app bundle.

## Test Requirements

- Unit-test ISO detection with fixture directory layouts.
- Unit-test command-output parsing.
- Unit-test state transitions in the bootable USB engine.
- Integration-test dry-run command planning.
- UI-test the happy path and major failure paths.
- Add manual test scripts for real removable media only after safety review.

