# AI Rules

These rules are for AI coding agents working in this repository.

## Product Rules

- Build wInstaller as a native macOS app.
- Treat the app as an assistant, not a generic disk utility.
- Every destructive action must be explained before it is offered.
- Every operation must be local unless a future requirement explicitly says otherwise.
- Never add telemetry by default.
- Never upload ISO files, logs, disk names, or diagnostics.

## Technical Rules

- Use Swift 6.
- Prefer SwiftUI.
- Use AppKit only for macOS integrations that require it.
- Use Swift concurrency for long-running work.
- Keep command planning testable without real disks.
- Use typed state machines for the USB creation flow.
- Use typed errors with recovery actions.
- Avoid force unwraps.
- Avoid deprecated APIs.
- Avoid global mutable state.
- Avoid hardcoded user paths.
- Avoid string-interpolated shell commands.

## UI Rules

- Follow Apple's Human Interface Guidelines.
- Use native controls.
- Use SF Symbols for interface icons.
- Do not introduce Bootstrap, Material Design, Electron, React Native, Flutter, or other third-party UI frameworks.
- Do not build a marketing landing page as the first screen.
- Use the assistant workflow as the first screen.
- Respect VoiceOver, keyboard navigation, Reduce Motion, Reduce Transparency, Increase Contrast, light mode, and dark mode.

## Terminal Rules

- Never invent terminal commands.
- Prefer structured command output.
- Never run destructive commands without explicit confirmation.
- Re-check disk identity immediately before erase.
- Refuse to erase internal disks.
- Show raw command output only in technical details.
- Keep dry-run mode for tests.

## Documentation Rules

- Update the relevant spec document when behavior changes.
- Add acceptance criteria for new major features.
- Keep user-facing language plain.
- Document non-goals when rejecting a tempting feature.

## Testing Rules

- Every parser needs fixture tests.
- Every state transition needs unit coverage.
- Every destructive path needs a dry-run test.
- UI changes need at least one accessibility pass.
- Real-disk tests must be manual, isolated, and clearly labeled.

## Review Rules

Before considering a task complete:

- Run available tests.
- Confirm no destructive commands were executed during tests.
- Check Git diff for unrelated changes.
- Verify docs still match behavior.
- Explain any untested risk in the final handoff.

