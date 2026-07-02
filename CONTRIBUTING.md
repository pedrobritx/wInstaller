# Contributing

wInstaller is a multi-platform project: three native UIs (SwiftUI/macOS, WinUI3/
Windows, GTK4-libadwaita/Linux) sharing one Rust core engine. Read
[AI_RULES.md](AI_RULES.md) before making any change — it applies to human and AI
contributors alike. Read the [ADRs](docs/adr/) for the architecture reasoning
behind the current shape of the project.

## Before you start

1. Read [AI_RULES.md](AI_RULES.md) and [PRODUCT.md](PRODUCT.md).
2. If your change affects behavior described in a spec doc (`BOOTABLE_USB_ENGINE.md`,
   `TERMINAL_AUTOMATION.md`, `USER_FLOW.md`, `ARCHITECTURE.md`, `SECURITY.md`,
   `DESIGN_SYSTEM.md`), update that doc in the same PR.
3. If your change is a new architectural decision (a new dependency, a new
   OS-adapter capability, a new toolkit), add an ADR under `docs/adr/` following
   the existing numbering and template.

## Feature parity across the three UIs

Because the three UIs are separate native codebases sharing only the core
engine, feature parity does not happen automatically — see
[docs/adr/0008-feature-parity-enforcement.md](docs/adr/0008-feature-parity-enforcement.md).
A PR that adds or changes a **user-visible feature** must include:

- [ ] The core engine change (`core/`) and its tests, if the feature touches
      domain logic, the state machine, or an OS adapter.
- [ ] An update to [docs/screen-inventory.yaml](docs/screen-inventory.yaml) if
      the feature adds, removes, or changes a screen/step.
- [ ] The corresponding UI change in **all three** platforms where the feature
      is user-visible — or, during the transition phases while a platform's app
      doesn't exist yet, an explicit note in the PR description tracking the gap
      (e.g. "Linux UI not yet built, tracked in #NNN").
- [ ] Any new or changed user-facing copy added to
      [shared/strings/copy.yaml](shared/strings/copy.yaml), never hardcoded in a
      single platform's source.

CI enforces what it mechanically can (the screen-inventory marker check and the
strings/design-token regeneration checks). The checklist above covers what
requires human judgment.

## Core rules (Rust, `core/`)

- OS-specific logic lives only in that OS's adapter
  (`core/src/adapters/{macos,windows,linux}.rs`) — never in the OS-agnostic
  engine.
- Every adapter parser is a pure function with a fixture test (fixture in, typed
  struct out) under `core/tests/fixtures/<os>/`.
- Real-disk execution tests are `#[ignore]`-by-default, manual, and clearly
  labeled — never run in CI.

## Testing

- Run `swift test` for the macOS app (`apps/macos/`) and `cargo test` for the
  core and any Rust-based UI (`apps/linux/`) before opening a PR.
- Confirm no destructive commands were executed during tests.
- Check your diff for unrelated changes.

## License

By contributing, you agree your contribution is licensed under the project's
[wInstaller Noncommercial License](LICENSE.md).
