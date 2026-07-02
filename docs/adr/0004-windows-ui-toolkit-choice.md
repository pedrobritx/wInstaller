# ADR-0004: Windows UI Toolkit Choice

## Status

Accepted.

## Context

The owner chose to keep three fully native UIs rather than one cross-platform UI
framework (see the top-level plan). Windows needs a concrete, currently-supported
native UI toolkit choice.

## Decision

Use **WinUI 3 + C#/.NET** for `apps/windows/`.

## Alternatives considered

- **WPF**: mature and well-documented, but Microsoft has placed it in
  maintenance mode; it does not natively support the Fluent Design System that
  gives a Windows 11-native feel, and new investment is minimal.
- **UWP**: deprecated in favor of WinUI 3 / the Windows App SDK; starting a new
  project on UWP today would mean building on a platform Microsoft is actively
  moving developers away from.
- **WinUI 3** (chosen): Microsoft's current first-party native toolkit for
  Windows 11 apps, built on the Windows App SDK, actively maintained, and gives
  Fluent Design controls, Mica/Acrylic materials, and native accessibility (UI
  Automation) out of the box — the closest Windows analog to what SwiftUI/AppKit
  give the macOS app.

## Consequences

- `apps/windows/WInstaller.App` is a WinUI3 + C#/.NET project.
- `apps/windows/WInstaller.Core.Interop` wraps the Rust core's C-ABI via P/Invoke
  (see ADR-0001), exposing idiomatic C# types to the WinUI3 layer.
- Packaging targets MSIX as primary (Section: ADR-0006), matching WinUI3's
  natural distribution path.
