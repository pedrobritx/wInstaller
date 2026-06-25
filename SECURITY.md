# Security

## Trust Model

wInstaller handles sensitive local resources: ISO files, physical disks, removable drives, and potentially privileged system operations. The app must behave conservatively.

Core promise:

- No uploads.
- No telemetry by default.
- No hidden network operations.
- No destructive disk operation without confirmation.
- No shell interpolation with user-controlled strings.

## Local-Only Behavior

wInstaller must not upload:

- ISO files.
- USB contents.
- Disk inventory.
- Logs.
- File paths.
- Hardware identifiers.

Any future update check, support export, or diagnostic sharing must be opt-in and documented.

## Disk Safety

Before erasing:

- Enumerate disks through structured output.
- Filter internal disks.
- Show exact selected disk identity.
- Require explicit confirmation.
- Re-query the disk immediately before execution.
- Abort if identity changed.

Never rely on UI selection alone for destructive work.

## Privileges

Disk operations may require elevated privileges. The implementation must choose a macOS-appropriate privilege model after prototyping and security review.

Allowed directions:

- Use system authorization prompts where appropriate.
- Isolate privileged operations behind a narrow interface.
- Keep privileged helper scope minimal if one becomes necessary.
- Sign and verify helper tools.

Disallowed directions:

- Running arbitrary shell scripts as administrator.
- Passing unsanitized paths into shell strings.
- Asking users to paste `sudo` commands as the normal product path.
- Silently installing dependencies.

## Dependency Policy

- Prefer system tools already present on macOS.
- For `wimlib-imagex`, evaluate licensing, signing, packaging, and update strategy before bundling.
- Do not install Homebrew automatically.
- If the user must install a dependency, explain why and provide a reversible path.

## Sandboxing and Distribution

Mac App Store distribution may be constrained by sandboxing and disk access requirements. Treat the App Store as a roadmap item, not a first-release promise.

Initial release path:

- Developer ID signed app.
- Notarized app bundle.
- Hardened runtime.
- Clear permissions explanation.

## Logging Security

Logs should be local and transparent.

Redact or avoid:

- Full home-directory paths when exporting.
- License keys.
- User document contents.
- Unrelated mounted volume details.

Keep:

- Operation type.
- Tool names.
- Redacted arguments.
- Exit status.
- Parsed error category.
- Recovery action.

## Threats

### Wrong Disk Erased

Mitigations:

- Internal disk filtering.
- Disk identity confirmation.
- Re-query before erase.
- High-friction confirmation.
- Tests for disk filtering.

### Malicious ISO Name or Path

Mitigations:

- Treat paths as data, not shell.
- Use argument arrays.
- Display escaped or sanitized names.
- Avoid executing files from the ISO.

### Dependency Tampering

Mitigations:

- Verify bundled tool signatures if included.
- Store expected tool hashes.
- Prefer notarized packaged dependencies.
- Refuse unknown tool paths in normal mode.

### Log Disclosure

Mitigations:

- Local logs only.
- Redaction before export.
- User-controlled sharing.

## Security Acceptance Criteria

- Destructive operations cannot be reached without confirmation.
- Command runner has no shell-interpolated execution path.
- Disk identity mismatch aborts erase.
- Logs are local by default.
- Network access is not required for the main workflow.

