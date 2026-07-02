# VMware Integration

## Purpose

wInstaller should help the user continue from bootable media creation into local virtualization. VMware Fusion is the first target because it is common for installing Windows on macOS.

## First Release Scope

- Detect whether VMware Fusion is installed.
- Offer to open VMware Fusion.
- Provide a guided checklist for creating or configuring a virtual machine.
- Do not automate virtual machine creation in the first release.
- Do not modify existing virtual machines.

## Detection

Detection should use LaunchServices and application bundle inspection.

Known app path:

```text
/Applications/VMware Fusion.app
```

Likely bundle identifier:

```text
com.vmware.fusion
```

Detection must be tolerant:

- App may be installed outside `/Applications`.
- Bundle identifiers should be verified at runtime.
- The app may be present but not licensed or fully configured.

## Handoff UI

When VMware Fusion is detected:

- Show installed app name and version if available.
- Offer "Open VMware Fusion".
- Show steps for creating a new VM from ISO or USB workflow, depending on what the user created.

When VMware Fusion is not detected:

- Explain that wInstaller can still create USB media.
- Provide neutral guidance that the user can install VMware Fusion or use another virtualization app.
- Do not make VMware a hard requirement for USB creation.

## Suggested VMware Checklist

- Open VMware Fusion.
- Create a new virtual machine.
- Choose installation method.
- Select the Windows ISO if installing directly in a VM.
- Attach the prepared USB only if the VM workflow requires it.
- Allocate CPU, memory, and disk according to VMware recommendations.
- Start installation.

## Future Virtualization Targets

### UTM

Potential bundle identifier:

```text
com.utmapp.UTM
```

First integration:

- Detect installation.
- Offer generic guidance.

### Parallels Desktop

Detection should verify current bundle identifiers at runtime instead of relying on static assumptions.

First integration:

- Detect installation.
- Offer generic guidance.

### VirtualBuddy

Detection should verify current bundle identifiers at runtime.

First integration:

- Detect installation.
- Offer generic guidance.

## Safety Rules

- Never start a VM automatically.
- Never attach host USB devices to a VM automatically.
- Never change VM configuration without explicit user intent.
- Never claim compatibility without testing the specific virtualization path.

## Test Fixtures

- VMware installed in `/Applications`.
- VMware installed in a custom folder.
- VMware absent.
- App bundle present but unreadable.
- Multiple virtualization apps installed.

