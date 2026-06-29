# wInstaller

wInstaller is a macOS installation assistant for creating bootable USB drives from Windows and Linux ISO files, then helping the user continue into VMware Fusion or another local virtualization app.

The product goal is simple: make a risky, command-heavy workflow feel like a calm first-party macOS assistant. The app must explain what it is doing, ask before destructive actions, validate the result, and keep all files local.

## Status

✅ **Steps 1-4 Complete** - The core application is implemented and functional!

- ✅ Domain models and state machine
- ✅ Unit tests with fixtures (6 tests passing)
- ✅ Dry-run command runner for testing
- ✅ Complete SwiftUI UI with all screens
- ⏳ UI tests (Step 5 - Next)
- ⏳ Real hardware integration (Step 6 - After UI tests)

**Current State:** The app has a complete, working UI that simulates the full user flow. All screens are implemented, accessible, and polished. Ready for UI testing and hardware integration.

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

# Run the app
swift run WInstallerApp

# Or open in Xcode
open Package.swift
```

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

**Note:** The app currently operates in simulation (dry-run) mode. ISO analysis and USB operations are not yet connected to real hardware — the engine plans every command but executes none. See [BOOTABLE_USB_ENGINE.md](BOOTABLE_USB_ENGINE.md) for the engine's state machine.

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
