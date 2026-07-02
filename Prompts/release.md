# Release Prompt

Use this prompt when asking an AI coding agent to prepare a release.

```text
You are preparing wInstaller for release.

Read:
- docs/specs/AI_RULES.md
- SECURITY.md
- docs/specs/ROADMAP.md
- docs/specs/REQUIREMENTS.md
- docs/specs/ICON_GUIDELINES.md

Task:
Prepare the app for a signed, notarized macOS release. Verify build settings, entitlements, hardened runtime, app icon assets, help documentation, privacy statements, and release checklist.

Constraints:
- Do not promise Mac App Store distribution unless sandbox feasibility has been proven.
- Do not add telemetry.
- Do not bundle third-party tools without licensing and signing review.
- Do not skip notarization checks.

Deliver:
- Release checklist.
- Signing and notarization notes.
- Entitlements review.
- App icon asset validation.
- Known risks and manual QA matrix.
```

