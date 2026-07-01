## Summary

<!-- What does this PR change, and why? -->

## Type of change

- [ ] Bug fix (no user-visible feature/behavior change)
- [ ] Feature (user-visible change — complete the parity checklist below)
- [ ] Docs / ADR only
- [ ] Infra / CI only

## Feature parity checklist (required for any user-visible feature)

See [CONTRIBUTING.md](../CONTRIBUTING.md) and
[docs/adr/0008-feature-parity-enforcement.md](../docs/adr/0008-feature-parity-enforcement.md).

- [ ] Core engine change (`core/`) included, with tests, if this touches domain
      logic, the state machine, or an OS adapter.
- [ ] `docs/screen-inventory.yaml` updated if this adds/removes/changes a screen.
- [ ] Implemented on **all three** platforms where user-visible, or the gap is
      explicitly tracked (link the tracking issue): ______
- [ ] New/changed copy added to `shared/strings/copy.yaml` (not hardcoded
      per-platform).

## Testing

- [ ] `swift test` passes (macOS)
- [ ] `cargo test` passes (core / Linux, once applicable)
- [ ] No destructive commands were run against real hardware during testing
- [ ] Relevant spec doc(s) updated to match new behavior

## Risk / rollback notes

<!-- Anything untested, any risk this PR introduces, how to roll back if needed. -->
