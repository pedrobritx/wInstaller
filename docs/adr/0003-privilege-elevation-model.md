# ADR-0003: Privilege Elevation Model Per OS

## Status

Accepted.

## Context

`SECURITY.md` already establishes the principle that privileged, destructive
operations must be isolated behind a narrow interface rather than run with
blanket elevated permissions. As wInstaller expands to Windows and Linux, each OS
has a different native way to request elevation for exactly the operations that
need it (erasing/formatting a removable disk) without elevating the whole app.

## Decision

- **macOS**: continue using the current user-owned-removable-disk model — most
  `diskutil eraseDisk`/`diskutil eraseVolume` operations on a user's own external
  drive do not require elevation beyond the standard removable-media permission
  prompt macOS already shows. Where elevation is genuinely required (e.g. certain
  `diskutil` operations on some drive types), use `AuthorizationServices` scoped to
  the specific privileged call, or an `osascript "with administrator privileges"`
  prompt as a fallback — never elevate the whole app process. Document the actual
  finding (which calls need elevation, if any) once this is verified against the
  Rust adapter's `erase_and_format` implementation.
- **Windows**: do not request elevation at launch. When `erase_and_format` is
  invoked, either (a) the app's manifest requests `requestedExecutionLevel
  highestAvailable` and the operation checks/prompts contextually, or (b) the
  specific privileged step is re-launched via `ShellExecute` with `"runas"`,
  triggering a single UAC prompt scoped to that operation. Prefer (b) — it keeps
  the main app process unprivileged.
- **Linux**: use `pkexec`/PolicyKit with a narrow `.policy` action definition
  (e.g. `com.winstaller.erase-disk`) that describes exactly the erase/format
  helper invocation being authorized — never request blanket root for the whole
  app.

In all three cases, the elevation prompt must occur at the moment of the actual
destructive operation, after the user has already seen and confirmed the
type-the-drive-name (or equivalent) confirmation dialog — elevation is not a
substitute for that confirmation, it is in addition to it.

## Consequences

- No platform runs the wInstaller UI process itself with admin/root privileges.
- Each adapter (ADR-0002) is responsible for triggering its own OS's elevation
  path at the narrowest possible point — the engine never knows or cares how
  elevation happens on a given OS.
- This must be verified against real hardware per OS before 1.0 (tracked in the
  manual QA matrix, `docs/QA_MATRIX.md`).
