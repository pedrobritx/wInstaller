# Bootable USB Engine

## Purpose

The bootable USB engine turns an ISO and a selected USB drive into a safe operation plan, executes it, and validates the result. It is a state machine, not a loose sequence of view callbacks.

## Inputs

- `InstallerISO`
- `USBDrive`
- User confirmation record
- Tool availability
- Boot compatibility preferences

## Outputs

- `OperationPlan`
- Progress events
- Validation report
- Local log references
- Final success or failure state

## State Machine

```text
idle
  -> analyzingISO
  -> waitingForUSB
  -> analyzingUSB
  -> planning
  -> awaitingEraseConfirmation
  -> preparingDrive
  -> copyingFiles
  -> splittingWIM
  -> validating
  -> ejecting
  -> completed
```

Failure can move the engine to `failed` from any active state. User cancellation can move the engine to `cancelled` when the operation is in a safe cancellation boundary.

## Planning Rules

### Windows ISO

Detect:

- `setup.exe`
- `sources/boot.wim`
- `sources/install.wim` or `sources/install.esd`
- `efi/boot/bootx64.efi` or equivalent UEFI boot files

Plan:

- FAT32-compatible target when UEFI boot is required.
- WIM split if `install.wim` exceeds FAT32 single-file limit.
- Preserve `sources` directory structure.
- Validate boot files after copy.

### Linux ISO

Detect:

- Boot directories such as `EFI`, `isolinux`, `syslinux`, or distro metadata.
- Distribution name when available.

Plan:

- First release may limit Linux support to analysis and guidance unless the copy strategy is tested per distro family.
- Do not claim universal Linux boot support without fixtures and real-device validation.

## Operation Steps

### Analyze ISO

- Mount ISO read-only.
- Read top-level structure.
- Detect OS family.
- Detect required boot files.
- Detect WIM or ESD details for Windows.
- Unmount if analysis does not need the ISO mounted.

### Analyze USB

- Enumerate disks.
- Filter unsafe disks.
- Confirm removable media.
- Confirm capacity.
- Capture pre-erase identity.

### Plan

- Select partition scheme.
- Select filesystem.
- Determine copy strategy.
- Determine WIM split requirement.
- Determine validation checks.
- Mark destructive operations.

### Confirm

- Require explicit user confirmation.
- Bind confirmation to disk identity.
- Re-check disk identity before execution.

### Prepare Drive

- Unmount selected disk.
- Erase and format according to plan.
- Wait for target volume to mount.
- Verify target volume path.

### Copy Files

- Copy all files except oversized `install.wim` when splitting.
- Preserve directory layout.
- Track byte progress.
- Report long-running file names only in technical details.

### Split WIM

- Split `install.wim` into `.swm` parts under the target `sources` directory.
- Use a chunk size below FAT32 limit.
- Validate expected output files.
- Ensure Windows Setup-compatible naming.

### Validate

Validation checks for Windows:

- Target volume exists.
- `boot` directory exists.
- `efi` directory exists when UEFI boot is expected.
- `sources/boot.wim` exists.
- `sources/install.wim` exists or split `.swm` files exist.
- No required file exceeds target filesystem limits.

Validation checks for all media:

- Copy operation completed without fatal errors.
- Target volume has expected free space behavior.
- Disk can be ejected or user is told why it cannot.

### Eject

- Eject the USB drive.
- If ejection fails, report that creation may be complete but physical removal is not yet safe.

## Error Recovery

### ISO Mount Failed

- Ask user to choose another ISO.
- Suggest verifying the download.
- Preserve no mounted partial state.

### USB Disappeared

- Stop the operation.
- Explain that the selected drive was removed or changed.
- Require the flow to restart from USB selection.

### WIM Tool Missing

- Pause before copy if WIM split is required.
- Explain why the tool is needed.
- Offer setup instructions or alternative strategy if implemented.

### Copy Failed

- Mark target USB incomplete.
- Offer retry from the copy phase only if the drive identity is unchanged and partial cleanup is safe.
- Otherwise require restart.

### Validation Failed

- Show which required file or condition failed.
- Offer to show log.
- Do not report success.

## Acceptance Criteria

- The engine can produce a dry-run plan without touching disk.
- Every destructive plan includes a confirmation gate.
- Every state transition is unit-tested.
- Disk identity changes after confirmation abort the run.
- Missing WIM split support blocks Windows ISOs that require splitting.
- Validation failure prevents the success screen.

