# Roadmap

## 0.1: Product Foundation

Goals:

- Finalize product documentation.
- Scaffold native macOS app.
- Build assistant shell.
- Add static welcome, ISO selection, USB selection, and done screens.
- Add local mock data for UI development.

Exit criteria:

- App launches.
- Assistant navigation works.
- UI matches the design direction.
- No real disk operations yet.

## 0.2: ISO and USB Analysis

Goals:

- Mount ISO read-only.
- Detect Windows ISO structure.
- Enumerate removable USB drives.
- Add disk safety filtering.
- Add dry-run command planning.

Exit criteria:

- ISO metadata appears in UI.
- Removable USB drives appear in UI.
- Internal disks are hidden by default.
- Tests cover parsers and planning.

## 0.3: USB Automation

Goals:

- Add erase confirmation.
- Format selected USB.
- Copy ISO files.
- Validate required boot files.
- Eject drive.

Exit criteria:

- Happy path works on a dedicated test USB.
- Disk identity mismatch aborts.
- Validation failure blocks success.
- Logs are local and readable.

## 0.4: Windows WIM Support

Goals:

- Detect oversized `install.wim`.
- Integrate or guide setup for `wimlib-imagex`.
- Split WIM files.
- Validate `.swm` output.

Exit criteria:

- Windows ISOs with large WIM files produce bootable media in tested scenarios.
- Missing WIM tool produces clear recovery guidance.

## 0.5: VMware Fusion Handoff

Goals:

- Detect VMware Fusion.
- Show version and launch action.
- Add guided VM setup checklist.
- Add help content for common Windows VM choices.

Exit criteria:

- VMware installed and absent states are tested.
- Handoff does not modify VM state automatically.

## 0.6: Linux Support Expansion

Goals:

- Add distro detection fixtures.
- Define tested copy strategies.
- Validate boot structures per distro family.

Exit criteria:

- Linux support is described honestly by tested distro family.
- Unsupported distros produce guidance instead of false success.

## 0.7: Advanced Recovery

Goals:

- Better retry behavior.
- Partial cleanup.
- Support bundle export with redaction.
- Expanded user guide.

Exit criteria:

- Common failure paths have recovery actions.
- Exported logs pass redaction checks.

## 1.0: Production Release

Goals:

- Developer ID signing.
- Hardened runtime.
- Notarization.
- Final app icon.
- Full accessibility pass.
- Public documentation.

Exit criteria:

- Release build is signed and notarized.
- Manual QA matrix is complete.
- No known data-loss bugs.
- Security review is complete.

## Future Ideas

- Parallels, UTM, and VirtualBuddy handoff.
- Ventoy guidance or integration after security review.
- Driver downloader, only from official vendor sources and only with explicit user consent.
- Optional checksum database integration, only if privacy and trust concerns are solved.
- Mac App Store release if sandbox constraints can be satisfied.

