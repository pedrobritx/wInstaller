# ADR-0001: Core Engine Language and FFI Strategy

## Status

Accepted.

## Context

wInstaller is moving from a macOS-only Swift app to three native UIs (macOS,
Windows, Linux) that share one core engine: the state machine, disk/ISO domain
models, error taxonomy, and OS-adapter interface currently implemented in
`Sources/WInstallerCore/` (~1,500 lines of Swift). The owner chose to keep three
fully native UI shells rather than a single cross-platform UI framework, which
means the core is the *only* thing that can be shared — it must be genuinely one
implementation, not three parallel reimplementations, or the project reintroduces
the exact risk this decision was meant to avoid: safety-critical logic (the
pre-erase disk-identity recheck, the state machine's transition rules) drifting
between platforms.

Requirements driving the choice:

- Memory safety matters for privileged, destructive disk operations (this is
  already this project's stated ethos in `SECURITY.md`).
- The core must parse untrusted structured command output per OS: `diskutil
  -plist`/`hdiutil -plist` (macOS, today), PowerShell JSON (Windows), `lsblk
  --json`/`udisksctl` (Linux).
- The core must be callable idiomatically from SwiftUI (macOS), WinUI3/C#
  (Windows), and GTK4 (Linux) without a heavy runtime or large binary footprint.
- No telemetry, no bundled network stack, small dependency surface.

## Decision

Rewrite the shared core in **Rust**, structured as a Cargo workspace at `core/`.

Consumption per platform:

- **macOS**: `cbindgen` generates a C header from the Rust core; a thin,
  hand-written Swift wrapper package (`apps/macos/WInstallerCoreFFI`) exposes it as
  an XCFramework. The SwiftUI app calls the wrapper instead of in-process Swift
  domain types.
- **Windows**: the same C-ABI is consumed via P/Invoke (or a C++/WinRT shim if
  COM-activatable objects become useful later) from a `WInstaller.Core.Interop`
  project, used by the WinUI3 app.
- **Linux**: **no FFI boundary at all** — the Linux UI is written directly in Rust
  using `gtk4-rs`, and imports the `core` crate as a normal Rust dependency. This
  is the single strongest practical argument for Rust over any alternative: one of
  the three platforms needs zero interop layer, which reduces total surface area
  and gives the team a reference consumer that always exercises the core with
  maximum fidelity.

## Alternatives considered

| Option | Why rejected |
|---|---|
| Keep Swift as the shared core (Swift has official Linux/Windows toolchains) | Swift-on-Linux and Swift-on-Windows exist, but calling Swift from a native WinUI3 (C#) or GTK4 (C) app has no mature, first-party interop story today. The team would be pioneering a C-shim-plus-P/Invoke bridge with little prior art — a real risk for a solo/small-team project without ecosystem support to lean on. |
| Kotlin Multiplatform | Reasonable middle ground with a real Swift interop story (proven in mobile KMP), but the desktop-3-native-UI shape is far less proven than mobile KMP, and bundling a JVM/Kotlin-Native runtime adds footprint inappropriate for a small local utility that must start instantly. |
| C/C++ core | Universally interoperable (every platform can call a C ABI trivially), but reintroduces manual memory management for privileged disk-erase code — directly working against this project's existing safety-first ethos in `SECURITY.md`, for no offsetting benefit once Rust's interop maturity is established. |

## Consequences

- The ~1,500 lines of Swift domain logic in `WInstallerCore.swift` and its
  adapters must be **ported** (rewritten with full behavioral understanding,
  re-deriving tests from `Tests/WInstallerCoreTests/`), not mechanically
  translated. This is the largest single cost of this decision and is scoped as
  Phase 1 of the delivery plan.
- The existing SwiftUI app continues to work throughout the migration — the old
  Swift core is only removed once the Rust replacement passes the full ported test
  suite (see Phase 1 exit criteria).
- `core/`'s public surface (the `SystemAdapter` trait, see ADR-0002) becomes the
  single point of contact between platforms; changes to it should land alongside
  their consumer updates in all three UIs where practical.
