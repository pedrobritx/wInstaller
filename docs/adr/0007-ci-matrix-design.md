# ADR-0007: CI Matrix Design

## Status

Accepted.

## Context

The repository has no CI today. As the project grows to three platforms sharing
one Rust core, CI needs to (a) build and test each platform on its native OS
runner, and (b) enforce that the three UIs don't drift apart at the feature level
(ADR-0008).

## Decision

GitHub Actions workflows under `.github/workflows/`:

- `ci-macos.yml` (`macos-latest`): `swift build`/`swift test` for `apps/macos`
  (today: the relocated existing SwiftPM package), plus, once Phase 1 lands,
  `cargo build`/`cargo test` for `core/` and an XCFramework link-check step.
- `ci-windows.yml` (`windows-latest`, added in Phase 3): `cargo build`/`cargo
  test` for `core/` (Windows target) plus `dotnet build`/`dotnet test` for
  `apps/windows/WInstaller.sln`.
- `ci-linux.yml` (`ubuntu-latest`, added in Phase 2): `cargo build`/`cargo test`
  for `core/` and `apps/linux` together as one Cargo workspace, with GTK4/
  libadwaita dev packages installed as a setup step.
- `parity.yml` (cross-cutting, all PRs, from Phase 0 onward in skeleton form):
  runs `scripts/check_screen_parity.py`, the strings-sync regeneration diff, and
  the design-tokens regeneration diff (ADR-0008).
- `docs-lint.yml` (from Phase 0): markdown link-check across root docs and
  `docs/site`, plus a check that `LICENSE.md`/`COMMERCIAL-LICENSE.md` exist.
- `deploy-pages.yml` (from Phase 0): builds and deploys `docs/site/` to GitHub
  Pages on push to the default branch, scoped to changes under `docs/site/**`.

Each per-OS job also runs `core`'s fixture-driven adapter parser tests
(ADR-0002), so, for example, the Windows-adapter JSON-parsing tests actually
execute on `windows-latest`, not only the OS-agnostic engine tests.

`parity.yml` starts advisory (non-blocking) while only one or two platforms
exist, and becomes a hard-required check once all three platforms are far enough
along that the check is meaningful (Phase 4 exit criterion).

## Consequences

- CI exists starting in Phase 0, even before the Rust core exists, giving an
  immediate regression safety net for the current Swift app.
- Each phase of the delivery plan adds exactly one new workflow file rather than
  requiring a CI redesign later.
