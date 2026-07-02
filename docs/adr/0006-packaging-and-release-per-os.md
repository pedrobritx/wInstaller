# ADR-0006: Packaging and Release Strategy Per OS

## Status

Accepted.

## Context

wInstaller has no release packaging today beyond a local ad-hoc-signed `.app`
build script (`Scripts/build-app.sh`). Expanding to three OSes requires a
packaging plan for each, consistent with the "no telemetry, no silent
installs" trust model in `SECURITY.md`.

## Decision

- **macOS**: signed and notarized `.app` bundled into a `.dmg`, continuing the
  existing `Scripts/build-app.sh` path but upgraded from an ad-hoc signature to a
  Developer ID identity, followed by `notarytool` submission. This was already
  planned in `ROADMAP.md` 1.0 and is not changed by this ADR, only extended to sit
  alongside the other two OSes' release artifacts in the same GitHub Release.
- **Windows**: MSIX as the primary package format (modern, auto-update-friendly,
  optionally Store-compatible, and WinUI3's natural distribution path per
  ADR-0004), signed with a code-signing certificate. A signed MSI or EXE built via
  WiX is offered as a secondary "portable/enterprise" install path for
  environments that restrict MSIX/AppX installation.
- **Linux**: `.deb` and `.rpm` packages built from the same Rust binary,
  distributed alongside a Flatpak manifest as the primary recommended cross-distro
  install path (sandboxing benefits, single install path across distros), with a
  no-install-required AppImage as a fallback for users who can't or don't want to
  install a package.

All release artifacts are attached to a single tagged GitHub Release per version,
which is also what the landing page's download buttons link to (see the landing
page plan).

## Consequences

- Signing/notarization credentials must be provisioned per OS before Phase 4
  (packaging) can complete; this is out of scope for Phase 0-3 and tracked as a
  Phase 4 exit criterion.
- Until real release artifacts exist, the landing page and README download links
  are explicitly placeholders (see the landing page and README plans).
