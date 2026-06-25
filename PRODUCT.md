# Product

## Mission

wInstaller helps Mac users create bootable operating system USB drives and continue into local virtualization without learning disk utilities, ISO internals, FAT32 limits, or boot firmware rules.

## Problem

Creating a Windows or Linux installer USB on macOS often requires a brittle chain of Terminal commands. Users need to identify the correct disk, erase it, mount an ISO, copy files, split large Windows image files, and validate boot files. One mistake can erase the wrong drive or produce media that appears complete but does not boot.

## Target Users

- Mac users who need to install Windows in VMware Fusion.
- Developers and IT users who repeatedly prepare Windows or Linux installer media.
- Non-expert users who can follow a guided assistant but should not be asked to reason about `diskutil` output.
- Power users who want transparent logs and predictable command behavior.

## Success Criteria

- A user can create a bootable Windows 10 or Windows 11 USB without manually typing Terminal commands.
- The app refuses to proceed when it cannot confidently identify the selected USB drive.
- Destructive steps require an explicit confirmation that names the physical drive and the consequences.
- Windows ISOs with `install.wim` files larger than 4 GB are handled automatically through WIM splitting.
- The final USB is validated before the app reports success.
- VMware Fusion handoff guidance is clear enough that a user can continue without searching the web.
- All work happens locally on the Mac.

## Non-Goals

- wInstaller is not a cloud service.
- wInstaller does not download pirated operating system images or bypass licensing.
- wInstaller does not replace VMware Fusion, Parallels Desktop, UTM, or Boot Camp.
- wInstaller does not hide destructive operations behind vague progress text.
- wInstaller does not introduce cross-platform UI frameworks.
- wInstaller does not upload ISO contents, disk names, logs, or diagnostics.

## Competitive Context

Existing tools often optimize for raw capability, not explanation. wInstaller should differentiate itself by acting as an assistant that explains what is happening, checks assumptions before touching disks, and recovers gracefully from common failure states.

## Unique Value

wInstaller combines three jobs in one local macOS experience:

- Prepare bootable USB media.
- Explain installation constraints in plain language.
- Bridge the user into a virtual machine workflow.

The defining feature is the live checklist. The app should tell the user what it has confirmed, what remains uncertain, and what it will do next.

Example checklist items:

- Windows ISO detected.
- USB drive is removable.
- USB capacity is sufficient.
- UEFI boot files found.
- `install.wim` requires splitting.
- FAT32 format selected.
- Copy operation completed.
- Boot files validated.
- USB ejected safely.

## Product Tone

wInstaller should feel calm, precise, and local. It should avoid jargon when possible, explain jargon when unavoidable, and never make the user feel like they are being asked to operate a hidden shell script.

