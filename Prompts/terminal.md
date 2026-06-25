# Terminal Automation Prompt

Use this prompt when asking an AI coding agent to implement command planning and execution.

```text
You are implementing wInstaller's terminal automation layer.

Read:
- AI_RULES.md
- TERMINAL_AUTOMATION.md
- BOOTABLE_USB_ENGINE.md
- SECURITY.md
- REQUIREMENTS.md

Task:
Implement a command runner abstraction, dry-run command planning, structured parsers for disk and ISO metadata, and a fake runner for tests. Do not run destructive commands. Do not add real formatting or erase execution until the confirmation flow and safety checks are implemented.

Constraints:
- Commands are executable plus argument arrays.
- Prefer `diskutil` and `hdiutil` structured plist output.
- No shell interpolation.
- No sudo paste workflows.
- Redact logs before display or export.
- Disk identity mismatch must abort destructive plans.

Deliver:
- Command model.
- Dry-run planner.
- Parser tests with fixtures.
- Fake command runner.
- Safety tests for internal disk filtering and identity mismatch.
```

