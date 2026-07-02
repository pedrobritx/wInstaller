# Testing Prompt

Use this prompt when asking an AI coding agent to improve test coverage.

```text
You are strengthening wInstaller's test suite.

Read:
- docs/specs/AI_RULES.md
- docs/specs/REQUIREMENTS.md
- docs/specs/ARCHITECTURE.md
- docs/specs/BOOTABLE_USB_ENGINE.md
- docs/specs/TERMINAL_AUTOMATION.md
- SECURITY.md

Task:
Add focused tests for parser behavior, engine state transitions, dry-run command planning, safety gates, and error recovery. Use fixtures instead of real disks. Do not execute destructive commands.

Required test areas:
- ISO detection.
- Disk enumeration parsing.
- Internal disk filtering.
- Removable drive selection.
- Operation planning.
- Confirmation gate.
- Disk identity mismatch.
- WIM split requirement.
- Validation failure.
- Cancellation boundaries.

Deliver:
- Unit tests.
- Fixture files.
- Test documentation for manual real-device QA.
```

