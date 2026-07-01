#!/usr/bin/env python3
"""Fail CI if a platform's UI code and docs/screen-inventory.yaml disagree.

For every step marked "implemented" for a platform, this script requires a
`// SCREEN: <id>` (or `# SCREEN: <id>` / `<!-- SCREEN: <id> -->`) marker
somewhere in that platform's UI source tree. It also flags markers that exist
in code with no corresponding registry entry, so the registry can't silently
drift from what's actually built either.

See docs/adr/0008-feature-parity-enforcement.md.
"""
import re
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
INVENTORY_PATH = REPO_ROOT / "docs" / "screen-inventory.yaml"

# Candidate source roots per platform. The macOS app currently lives at
# Sources/WInstallerApp (pre-Phase-1 layout); apps/macos is the post-Phase-1
# location. Both are checked so this script stays correct across the move.
PLATFORM_ROOTS = {
    "macos": ["apps/macos", "Sources/WInstallerApp"],
    "windows": ["apps/windows"],
    "linux": ["apps/linux"],
}

MARKER_RE = re.compile(r"SCREEN:\s*([a-z0-9-]+)")


def existing_roots(candidates):
    return [REPO_ROOT / c for c in candidates if (REPO_ROOT / c).exists()]


def find_markers(root: Path) -> set[str]:
    found = set()
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix not in {".swift", ".cs", ".xaml", ".rs", ".py"}:
            continue
        try:
            text = path.read_text(errors="ignore")
        except OSError:
            continue
        for match in MARKER_RE.finditer(text):
            found.add(match.group(1))
    return found


def main() -> int:
    inventory = yaml.safe_load(INVENTORY_PATH.read_text())
    steps = inventory["steps"]

    errors: list[str] = []

    for platform, candidates in PLATFORM_ROOTS.items():
        roots = existing_roots(candidates)
        required_ids = {
            step["id"] for step in steps if step["platforms"].get(platform) == "implemented"
        }

        if not roots:
            if required_ids:
                errors.append(
                    f"[{platform}] {len(required_ids)} step(s) marked 'implemented' "
                    f"but no source root found among {candidates}"
                )
            continue

        found_ids: set[str] = set()
        for root in roots:
            found_ids |= find_markers(root)

        missing = required_ids - found_ids
        for step_id in sorted(missing):
            errors.append(
                f"[{platform}] step '{step_id}' is marked 'implemented' in "
                f"screen-inventory.yaml but no 'SCREEN: {step_id}' marker was found"
            )

        known_ids = {step["id"] for step in steps}
        orphaned = found_ids - known_ids
        for step_id in sorted(orphaned):
            errors.append(
                f"[{platform}] found a 'SCREEN: {step_id}' marker in code with no "
                f"matching entry in screen-inventory.yaml"
            )

    if errors:
        print("Screen parity check failed:\n")
        for e in errors:
            print(f"  - {e}")
        print(f"\nSee {INVENTORY_PATH.relative_to(REPO_ROOT)} and CONTRIBUTING.md.")
        return 1

    print("Screen parity check passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
