# Build Prompt

Use this prompt when asking an AI coding agent to start implementing wInstaller.

```text
You are building wInstaller, a native macOS assistant for creating bootable USB drives from Windows and Linux ISO files.

Read these files first:
- docs/specs/AI_RULES.md
- docs/specs/PRODUCT.md
- docs/specs/REQUIREMENTS.md
- docs/specs/USER_FLOW.md
- docs/specs/ARCHITECTURE.md
- docs/specs/BOOTABLE_USB_ENGINE.md
- docs/specs/TERMINAL_AUTOMATION.md
- SECURITY.md

Task:
Scaffold the macOS app using Swift 6 and SwiftUI. Build the assistant shell, domain models, dry-run bootable USB engine, and fixture-driven tests. Do not execute real disk operations. Use fake command runners and mock data until destructive workflows are explicitly implemented and reviewed.

Constraints:
- Native macOS UI only.
- No telemetry.
- No shell-interpolated commands.
- No destructive commands.
- Every state transition must be testable.

Deliver:
- App target.
- Test target.
- Initial assistant UI.
- Domain models.
- Dry-run operation planner.
- README update with build and test commands.
```

