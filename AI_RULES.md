# AI Rules

These rules are for AI coding agents working in this repository.

## Product Rules

- Build wInstaller as **three native apps** — macOS, Windows, Linux — sharing
  **one Rust core engine**. No platform ships a second-class or web-wrapped UI.
- Treat each app as an assistant, not a generic disk utility.
- Every destructive action must be explained before it is offered.
- Every operation must be local unless a future requirement explicitly says otherwise.
- Never add telemetry by default.
- Never upload ISO files, logs, disk names, or diagnostics.
- A feature that is user-visible must be reflected in `docs/screen-inventory.yaml`
  and implemented (or explicitly, visibly tracked as pending) across all three
  UIs — see `CONTRIBUTING.md` and `docs/adr/0008-feature-parity-enforcement.md`.

## Core Rules (shared engine, `core/`)

- The core is Rust. It contains the state machine, domain models, error
  taxonomy, and the `SystemAdapter` trait — see `docs/adr/0001-core-language-and-ffi.md`
  and `docs/adr/0002-os-adapter-interface.md`.
- OS-specific logic (which command to run, how to parse its output) lives only
  in that OS's adapter (`core/src/adapters/{macos,windows,linux}.rs`) — never in
  the OS-agnostic engine.
- Every adapter's parsing logic must be a pure function with fixture tests
  (fixture in, typed struct out) — no adapter parser ships without a fixture
  test, regardless of which OS it targets.
- Keep command planning testable without real disks, on every OS.
- Use typed state machines for the USB creation flow.
- Use typed errors with recovery actions.
- Avoid string-interpolated shell commands on any OS — argv-only invocation.
- Avoid hardcoded user paths.

## Technical Rules (per-platform UI shells)

- **macOS** (`apps/macos/`): Swift 6, SwiftUI first, AppKit only for macOS
  integrations that require it, Swift concurrency for long-running work, calling
  into the core via the `WInstallerCoreFFI` wrapper package. Avoid force
  unwraps, deprecated APIs, and global mutable state.
- **Windows** (`apps/windows/`): WinUI 3 + C#/.NET, calling into the core via
  `WInstaller.Core.Interop`. Avoid global mutable state and hardcoded paths.
- **Linux** (`apps/linux/`): Rust + `gtk4-rs` + libadwaita, importing the `core`
  crate directly (no FFI boundary). Avoid global mutable state and hardcoded
  paths.

## UI Rules

- Follow each OS's native human-interface guidelines (Apple HIG on macOS,
  Fluent on Windows, GNOME HIG on Linux).
- Use native controls on every platform — no Bootstrap, Material Design,
  Electron, React Native, Flutter, or other cross-platform *UI* framework on any
  OS. (A shared non-UI Rust core is not a cross-platform UI framework — see
  `PRODUCT.md`'s Multi-Platform Direction section.)
- Use each platform's native icon system (SF Symbols on macOS, Fluent/Segoe
  icons on Windows, Adwaita/symbolic icons on Linux).
- Do not build a marketing landing page as the first screen of any app.
- Use the assistant workflow as the first screen, on every platform.
- User-facing copy comes from `shared/strings/copy.yaml`, not hardcoded
  per-platform strings, so text cannot drift between OSes.
- Visual accents/spacing come from `shared/design-tokens/tokens.json`, layered on
  top of each platform's native materials/system colors — never a fully custom
  theme that overrides native look-and-feel.
- Respect each platform's accessibility settings: VoiceOver/keyboard navigation/
  Reduce Motion/Reduce Transparency/Increase Contrast/light+dark mode on macOS;
  Narrator/keyboard navigation/high contrast/light+dark theme on Windows;
  Orca/keyboard navigation/high contrast/light+dark theme on Linux.

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

