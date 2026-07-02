# ADR-0009: License Model

## Status

Accepted.

## Context

wInstaller has never had a LICENSE file (`README.md` previously read "No license
has been selected yet"). The owner wants: source-available, free to use/share/fork
for any purpose **except** commercial use; commercial use requires contacting the
developer for a separate negotiated license; and forks/derivatives must remain
under the same noncommercial terms in perpetuity (no relicensing a fork to
something permissive or commercial).

## Decision

Base the license on **PolyForm Noncommercial 1.0.0**, with a custom addendum
("Additional Terms" section appended after the stock PolyForm text) that:

1. Requires any distributed derivative or fork to remain licensed under
   equivalent noncommercial terms — PolyForm Noncommercial alone permits forks to
   exist but does not, by itself, prevent a fork from being redistributed under a
   different (e.g. permissive or commercial) license. The addendum closes this
   gap.
2. Adds a clearly labeled "Commercial Use" section directing anyone wanting
   commercial use to contact `pedrohbrito@me.com` for a separately negotiated,
   paid license.

## Alternatives considered

- **AGPLv3**: strong copyleft, but is not noncommercial-only — commercial use
  would be permitted as long as source is shared, which doesn't match the
  owner's requirement that commercial use specifically requires a separate
  license.
- **A fully custom license from scratch**: would require bespoke legal drafting
  with no community precedent, higher risk of ambiguity or unenforceability
  compared to layering a small addendum on a well-known, reviewed template.
- **PolyForm Noncommercial 1.0.0 as-is (no addendum)**: closest fit but does not
  satisfy the "forks must remain noncommercial" requirement on its own.

## Consequences

- `LICENSE.md` holds the full legal text: stock PolyForm Noncommercial 1.0.0 text
  followed by the addendum as a clearly separated "Additional Terms" section
  (keeps clear what's stock template vs. custom clause). Legal text is drafted
  during implementation of this ADR, not specified here.
- `COMMERCIAL-LICENSE.md` gives a plain-language explainer of what counts as
  commercial use in this project's context and the contact/negotiation path.
- `README.md`, the landing page, and new source file headers reference
  `LICENSE.md`/`COMMERCIAL-LICENSE.md` rather than duplicating the terms.
