# ADR-0008: Feature Parity Enforcement

## Status

Accepted.

## Context

The owner chose three native UIs sharing only a core engine. Sharing the core
does not, by itself, guarantee the three UIs stay in sync at the feature/screen
level — that requires explicit process and tooling, or the three apps will
silently diverge over time as features get added to one platform and forgotten on
the others.

## Decision

Four concrete, complementary mechanisms:

1. **Canonical screen registry**: `docs/screen-inventory.yaml` lists every
   canonical step ID derived from `USER_FLOW.md` (e.g. `welcome`, `choose-iso`,
   `verify-iso`, `insert-usb`, `analyze-usb`, `confirm-erase`, `create-usb`,
   `done`, `use-with-vmware`), each with a purpose, required data fields, and a
   per-platform status (`implemented` / `planned` / `not-applicable`).
   `scripts/check_screen_parity.py` greps each platform's UI source tree for a
   marker referencing the step ID (e.g. `// SCREEN: confirm-erase`) and fails CI
   if a step marked `implemented` for a platform has no matching marker, or a
   marker exists with no registry entry — catching both "forgot to build it" and
   "the registry drifted from what was actually built."
2. **Shared copy source of truth**: `shared/strings/copy.yaml`, keyed by step ID
   plus a sub-key (e.g. `confirm-erase.title`). Generator scripts compile it into
   each platform's native string format (Swift String Catalog, .NET `.resx`,
   gettext `.po`). A CI job regenerates all three and fails if the regenerated
   output differs from what's committed, so `copy.yaml` stays the only
   hand-edited source of user-facing text.
3. **Shared design tokens**: `shared/design-tokens/tokens.json` extends
   `DESIGN_SYSTEM.md`'s existing color/spacing/radius scale into machine-readable
   form, consumed by each platform's native theming system. Each platform still
   uses its native materials/system colors as the base — tokens only pin the
   small set of product-specific accents and spacing constants.
4. **Contribution workflow gate**: `CONTRIBUTING.md` states that a PR adding or
   changing a user-visible feature must include the core change, the
   `screen-inventory.yaml` update, the corresponding change in all three UI
   shells (or an explicit, reviewed exception noted in the PR description during
   the transition phases when not all three UIs exist yet), and any new strings
   added to `copy.yaml`. `.github/PULL_REQUEST_TEMPLATE.md` encodes this as a
   literal checklist.

CI enforces what it mechanically can (1 and 2, and the tokens regeneration
check); the PR template enforces what requires human judgment (4).

## Consequences

- A feature cannot merge with a screen implemented on one platform and silently
  missing from another's registry entry, once `parity.yml` is a required check
  (Phase 4).
- Copy text cannot drift between platforms because there is exactly one place to
  edit it.
- The visual language (accent colors, spacing) stays consistent across three
  independently-coded UIs without forcing them into a shared UI framework.
