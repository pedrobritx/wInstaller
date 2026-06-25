# Terminal Automation

## Purpose

This document defines how wInstaller may interact with macOS command-line tools. The app should make Terminal-grade operations safer by planning, explaining, confirming, executing, and validating them.

## Policy

- Never run destructive commands before explicit user confirmation.
- Never build shell commands through string interpolation.
- Always execute commands as executable plus argument array.
- Prefer structured output flags such as `-plist` when available.
- Capture standard output, standard error, exit status, start time, end time, and cancellation state.
- Redact sensitive paths before displaying or exporting logs.
- Keep dry-run mode available for tests and command review.
- Treat command output as untrusted input.

## Command Lifecycle

1. Build typed operation plan.
2. Identify destructive steps.
3. Present user-readable summary.
4. Require confirmation if destructive.
5. Execute command through command runner.
6. Parse structured output.
7. Emit typed progress event.
8. Validate expected side effects.
9. Log local technical details.

## Core Tools

### Disk Enumeration

Tool: `diskutil`

Preferred command:

```sh
/usr/sbin/diskutil list -plist
```

Purpose:

- Detect disks and volumes.
- Identify removable drives.
- Collect identifiers and capacity.

Expected parser behavior:

- Parse property list output with `PropertyListDecoder`.
- Ignore disks that cannot be parsed safely.
- Mark internal disks as unsafe for erase.

Failure recovery:

- Ask the user to reconnect the USB drive.
- Offer refresh.
- Show technical details only on request.

### Disk Detail

Preferred command:

```sh
/usr/sbin/diskutil info -plist /dev/diskN
```

Purpose:

- Confirm physical device details before erase.
- Verify removable and internal flags.
- Read partition scheme and media name.

Safety:

- Run immediately before destructive work.
- Abort if the device identity changed after confirmation.

### Unmount Disk

Preferred command:

```sh
/usr/sbin/diskutil unmountDisk /dev/diskN
```

Purpose:

- Prepare the drive for formatting.

Failure recovery:

- Retry once after a short delay.
- Explain that another app may be using the drive.
- Offer to reveal technical details.

### Format Disk

The exact format command must be selected by `BootStrategy`.

Example pattern:

```sh
/usr/sbin/diskutil eraseDisk FAT32 WINSTALL GPT /dev/diskN
```

Purpose:

- Erase and format the selected removable drive.

Safety:

- Requires confirmation.
- Re-query disk identity immediately before execution.
- Refuse if disk is internal, system, or no longer matches the confirmed device.

Notes:

- The app must test GPT and MBR compatibility assumptions against target boot scenarios.
- The first release should document the selected default and provide advanced override only if tested.

### Rename Volume

Example:

```sh
/usr/sbin/diskutil rename /Volumes/OLD_NAME WINSTALL
```

Purpose:

- Apply a readable installer volume name.

Failure recovery:

- Continue if rename fails but bootability is unaffected.
- Report the final mounted volume name.

### Mount ISO

Preferred command:

```sh
/usr/bin/hdiutil attach -readonly -nobrowse -plist /path/to/file.iso
```

Purpose:

- Mount the ISO for analysis and copying.

Expected parser behavior:

- Parse mount point from property list output.
- Track device identifiers for later detach.

Failure recovery:

- Report unsupported or damaged ISO.
- Unmount any partial attachments.

### Detach ISO

Preferred command:

```sh
/usr/bin/hdiutil detach /dev/diskN
```

Purpose:

- Clean up ISO mount after analysis or copy.

Failure recovery:

- Retry once.
- If still mounted, explain how to eject through Finder.

### Copy Files

Preferred APIs:

- Use Foundation file APIs for controllable copy progress when possible.
- Use system tools only if they provide reliability or metadata behavior that Foundation does not.

Potential command:

```sh
/usr/bin/rsync -a --info=progress2 /source/ /destination/
```

Policy:

- Validate paths before copy.
- Never delete destination files except within the confirmed erased target volume.
- Report progress by bytes when possible.

### Split Windows WIM

Tool: `wimlib-imagex`

Example:

```sh
/usr/local/bin/wimlib-imagex split /source/sources/install.wim /destination/sources/install.swm 3800
```

Purpose:

- Split a Windows image file into parts compatible with FAT32.

Dependency policy:

- Detect whether `wimlib-imagex` exists.
- Do not silently install Homebrew or third-party tools.
- Offer clear setup guidance or a bundled, signed helper only after licensing and security review.

### Verify Disk

Example:

```sh
/usr/sbin/diskutil verifyDisk /dev/diskN
```

Purpose:

- Run a disk-level sanity check after formatting or copying when useful.

Limit:

- Disk verification does not prove bootability by itself. It is one validation input.

### Eject USB

Preferred command:

```sh
/usr/sbin/diskutil eject /dev/diskN
```

Purpose:

- Safely eject the completed USB drive.

Failure recovery:

- Explain that the drive is complete but still mounted.
- Offer retry.
- Tell the user to eject from Finder if retry fails.

## Logging

Each command log entry includes:

- Operation id.
- Tool name.
- Arguments with redaction.
- Start and end timestamps.
- Exit status.
- Parsed result summary.
- User-facing message.
- Technical stdout and stderr when revealed.

Do not log raw ISO file contents, license keys, or unrelated disk contents.

## Timeouts

Recommended timeout classes:

- Fast metadata command: 10 seconds.
- Mount or unmount: 60 seconds.
- Format: 120 seconds.
- Copy: no fixed short timeout; progress watchdog instead.
- WIM split: no fixed short timeout; progress watchdog instead.
- Eject: 60 seconds.

## Cancellation

Cancellation behavior must be explicit:

- Before erase: safe and immediate.
- During format: may need to wait for command completion.
- During copy: can stop copying, then mark USB incomplete.
- During WIM split: can stop, then remove incomplete `.swm` files if safe.
- During validation: safe.

The UI must not imply instant cancellation when the underlying command cannot safely stop.

