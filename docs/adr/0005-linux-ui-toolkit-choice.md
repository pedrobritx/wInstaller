# ADR-0005: Linux UI Toolkit Choice

## Status

Accepted.

## Context

Linux needs a concrete native UI toolkit choice, evaluated the same way as
Windows (ADR-0004): must feel native, must be realistically maintainable by a
small team, and should minimize the interop cost to the Rust core chosen in
ADR-0001.

## Decision

Use **GTK4 + libadwaita**, written directly in Rust via `gtk4-rs`, for
`apps/linux/`.

## Alternatives considered

- **Qt6**: excellent cross-desktop reach (native-feeling on KDE especially) and
  mature C++ tooling, but its Rust bindings are less idiomatic and less actively
  maintained than `gtk4-rs`, and choosing Qt6 would mean either writing the Linux
  app in C++ (a fourth language in the project, alongside Swift, C#, and Rust) or
  fighting a thinner Rust-Qt interop layer.
- **GTK4 + libadwaita** (chosen): `gtk4-rs` is a mature, actively maintained,
  idiomatic Rust binding, which means the Linux app can import the `core` crate
  **directly, with zero FFI boundary** (see ADR-0001) — the strongest practical
  argument in this whole toolkit evaluation. libadwaita's HIG-consistent adaptive
  widgets closely match the "calm assistant" native feel already established for
  macOS in `VISION.md`, and align with GNOME's default desktop experience.

## Trade-off acknowledged

GTK4/libadwaita apps feel slightly less native on KDE/Plasma desktops than a Qt6
app would. This is accepted as a reasonable cost given the zero-FFI Rust
integration and the reduced total language surface (Rust everywhere except the
thin Swift/C# UI-interop wrappers).

## Consequences

- `apps/linux/` is a Rust binary crate depending directly on `core/` — no
  generated bindings, no C header, no marshaling layer for this platform.
  This also makes `apps/linux` a natural "reference consumer" of the core API:
  because it has no interop friction, it's the first place core API ergonomics
  problems will surface.
- Distribution targets `.deb` + `.rpm` + Flatpak as primary, AppImage as a
  no-install-required fallback (ADR-0006).
