# wInstaller

wInstaller is a macOS installation assistant for creating bootable USB drives from Windows and Linux ISO files, then helping the user continue into VMware Fusion or another local virtualization app.

The product goal is simple: make a risky, command-heavy workflow feel like a calm first-party macOS assistant. The app must explain what it is doing, ask before destructive actions, validate the result, and keep all files local.

## Status

✅ **Feature-complete assistant with real system integration.**

- ✅ Domain models and typed state machine (`WInstallerCore`)
- ✅ Unit + fixture tests (engine, parsers, executor)
- ✅ Real command runner (`Process`, argv-only) plus a dry-run runner for tests
- ✅ Live USB enumeration (`diskutil -plist`) with internal-disk filtering
- ✅ ISO mount + inspection (`hdiutil`, read-only)
- ✅ Real bootable-USB execution pipeline with the full safety gate
- ✅ VMware Fusion / UTM / Parallels detection and handoff
- ✅ Local logging with home-path redaction
- ✅ Liquid Glass SwiftUI interface (macOS 26) with native-material fallback
- ✅ App icon (`AppIcon.appiconset` / `.iconset`) and `.app` packaging script

**Current State:** wInstaller is a native macOS assistant that walks the user
through ISO selection, live USB detection, an explicit typed-name erase
confirmation, and real bootable-media creation — or a full **Simulate (dry-run)**
pass that exercises the same code path without touching a disk. Every
destructive step is gated: the drive identity is re-checked immediately before
erase and the run aborts on any mismatch or internal disk.

> **Safety note:** Real disk operations format the selected removable drive.
> Always verify the target and prefer the Simulate toggle first. Destructive
> operations have not been run on hardware in CI — test on a spare USB.

## Installation

### Running the App

```bash
# Clone the repository
git clone https://github.com/yourusername/wInstaller.git
cd wInstaller

# Build everything
swift build

# Run tests
swift test

# Run the app (bare SwiftPM executable)
swift run WInstallerApp

# Or open in Xcode
open Package.swift
```

> **Build requirement for Liquid Glass:** the interface uses macOS 26 Liquid
> Glass APIs (`.glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`)
> gated behind `if #available(macOS 26.0, *)`. Building therefore requires the
> **macOS 26 SDK (Xcode 26+)**, while the app still runs on macOS 15 via the
> native-material fallback (deployment target stays at macOS 15).

### Build a real `.app` bundle

```bash
# Generate the app icon assets (pure Python, no dependencies)
python3 Assets/Icon/generate_icon.py

# Assemble build/wInstaller.app (builds .icns, copies Info.plist, ad-hoc signs)
Scripts/build-app.sh
open build/wInstaller.app
```

For distribution, replace the ad-hoc signature in `Scripts/build-app.sh` with a
Developer ID identity and notarize the result.

### Command Line Tools only (no full Xcode)

With only the Xcode Command Line Tools installed, `swift build` and
`swift run WInstallerApp` work as-is. The Swift Testing macro plugin and
runtime framework are not on the default search paths, so `swift test`
needs a few extra flags:

```bash
swift test \
  -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

If the project lives in iCloud Drive, code-signing the test bundle can fail
on extended-attribute "detritus"; add `--scratch-path /tmp/winstaller-build`
(any path outside iCloud) to the command above.

**Requirements:**
- Swift 6.0+
- macOS 15.0+
- Xcode 16+ or the Command Line Tools (for development)

**Note:** The app now performs real ISO inspection, live USB enumeration, and
(on confirmation) real disk operations through `diskutil`, `hdiutil`, `rsync`,
and `wimlib-imagex`. A **Simulate (dry-run)** toggle on the confirmation screen
runs the identical pipeline through a fake command runner so no disk is touched.
See [BOOTABLE_USB_ENGINE.md](BOOTABLE_USB_ENGINE.md) for the engine's state
machine and [TERMINAL_AUTOMATION.md](TERMINAL_AUTOMATION.md) for the command
policy.

## Planned Features

- Detect and verify ISO files.
- Detect Windows and Linux installation media.
- Detect removable USB drives and explain their current state.
- Confirm all destructive operations before erasing a drive.
- Format a selected USB drive for UEFI boot.
- Copy ISO contents to the USB drive.
- Split large Windows `install.wim` files when FAT32 limits require it.
- Validate the final bootable USB structure.
- Detect VMware Fusion and provide next-step guidance.
- Keep logs local and readable.
- Avoid telemetry, uploads, and hidden network behavior.

## Design Direction

The visual direction is documented in [UI_GUIDELINES.md](UI_GUIDELINES.md), [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md), and [ICON_GUIDELINES.md](ICON_GUIDELINES.md).

Reference mockup:

![wInstaller product direction](Assets/Screens/product-direction.png)

Official Apple design references:

- [Apple Human Interface Guidelines: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Apple Human Interface Guidelines: Icons](https://developer.apple.com/design/human-interface-guidelines/icons)
- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines)

## Documentation Map

- [PRODUCT.md](PRODUCT.md): mission, users, success criteria, and non-goals.
- [VISION.md](VISION.md): product philosophy and interaction principles.
- [REQUIREMENTS.md](REQUIREMENTS.md): functional and non-functional requirements.
- [USER_FLOW.md](USER_FLOW.md): screen-by-screen assistant flow.
- [ARCHITECTURE.md](ARCHITECTURE.md): app structure, modules, and state model.
- [UI_GUIDELINES.md](UI_GUIDELINES.md): macOS interface rules.
- [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md): reusable visual and component standards.
- [TERMINAL_AUTOMATION.md](TERMINAL_AUTOMATION.md): allowed commands, policies, and error recovery.
- [BOOTABLE_USB_ENGINE.md](BOOTABLE_USB_ENGINE.md): bootable media engine state machine.
- [VMWARE_INTEGRATION.md](VMWARE_INTEGRATION.md): virtualization detection and handoff behavior.
- [SECURITY.md](SECURITY.md): local-only trust model and permission strategy.
- [ICON_GUIDELINES.md](ICON_GUIDELINES.md): app icon and interface icon direction.
- [AI_RULES.md](AI_RULES.md): implementation rules for coding agents.
- [ROADMAP.md](ROADMAP.md): phased delivery plan.
- [Prompts](Prompts): focused prompts for future implementation passes.

## Recommended Build Order

1. Read [AI_RULES.md](AI_RULES.md).
2. Implement the Swift domain models and state machine from [BOOTABLE_USB_ENGINE.md](BOOTABLE_USB_ENGINE.md).
3. Build dry-run command wrappers from [TERMINAL_AUTOMATION.md](TERMINAL_AUTOMATION.md).
4. Build the SwiftUI assistant from [USER_FLOW.md](USER_FLOW.md).
5. Add VMware detection from [VMWARE_INTEGRATION.md](VMWARE_INTEGRATION.md).
6. Add integration tests and fixture-driven command parsing.
7. Package, sign, notarize, and document the release.

## Technology Direction

- Platform: macOS 26+ target, with compatibility decisions documented before lowering deployment targets.
- Language: Swift 6.
- UI: SwiftUI first, AppKit only where platform integration requires it.
- Concurrency: Swift concurrency with cancellation-aware tasks.
- Persistence: lightweight local preferences; SwiftData only if durable history becomes necessary.
- Testing: unit tests for parsing and state transitions, integration tests for dry-run command planning, UI tests for the assistant flow.

## Contributing

Before implementing a feature, read [AI_RULES.md](AI_RULES.md) and update the relevant specification file when behavior changes.

## License

No license has been selected yet.
