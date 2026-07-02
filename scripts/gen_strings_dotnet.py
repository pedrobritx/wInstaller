#!/usr/bin/env python3
"""Generate the Windows app's .resx string table from shared/strings/copy.yaml.

shared/strings/copy.yaml is the single hand-edited source of user-facing copy
across the three native UIs (docs/adr/0008-feature-parity-enforcement.md).
This script flattens it to "<step-id>.<sub-key>" resources and writes a
deterministic apps/windows/WInstaller.App/Strings/AppStrings.resx.

Usage:
    python3 scripts/gen_strings_dotnet.py          # regenerate the .resx
    python3 scripts/gen_strings_dotnet.py --check  # fail if committed output is stale
"""
import sys
from pathlib import Path
from xml.sax.saxutils import escape

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
COPY_PATH = REPO_ROOT / "shared" / "strings" / "copy.yaml"
OUTPUT_PATH = REPO_ROOT / "apps" / "windows" / "WInstaller.App" / "Strings" / "AppStrings.resx"

HEADER = """\
<?xml version="1.0" encoding="utf-8"?>
<!--
  GENERATED FILE - DO NOT EDIT BY HAND.
  Source of truth: shared/strings/copy.yaml
  Regenerate with: python3 scripts/gen_strings_dotnet.py
-->
<root>
  <resheader name="resmimetype">
    <value>text/microsoft-resx</value>
  </resheader>
  <resheader name="version">
    <value>2.0</value>
  </resheader>
  <resheader name="reader">
    <value>System.Resources.ResXResourceReader, System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value>
  </resheader>
  <resheader name="writer">
    <value>System.Resources.ResXResourceWriter, System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value>
  </resheader>
"""

FOOTER = "</root>\n"


def flatten(copy: dict) -> dict[str, str]:
    flat: dict[str, str] = {}
    for section, entries in copy.items():
        if not isinstance(entries, dict):
            raise SystemExit(f"copy.yaml section '{section}' must be a mapping")
        for key, value in entries.items():
            if not isinstance(value, str):
                raise SystemExit(f"copy.yaml value '{section}.{key}' must be a string")
            flat[f"{section}.{key}"] = value
    return flat


def render(flat: dict[str, str]) -> str:
    body = []
    for key in sorted(flat):
        value = escape(flat[key])
        body.append(f'  <data name="{escape(key)}" xml:space="preserve">\n'
                    f"    <value>{value}</value>\n"
                    "  </data>\n")
    return HEADER + "".join(body) + FOOTER


def main() -> int:
    check_only = "--check" in sys.argv[1:]
    copy = yaml.safe_load(COPY_PATH.read_text(encoding="utf-8"))
    rendered = render(flatten(copy))

    if check_only:
        committed = OUTPUT_PATH.read_text(encoding="utf-8") if OUTPUT_PATH.exists() else ""
        if committed != rendered:
            print(
                f"{OUTPUT_PATH.relative_to(REPO_ROOT)} is out of date with "
                "shared/strings/copy.yaml.\nRegenerate it with: "
                "python3 scripts/gen_strings_dotnet.py"
            )
            return 1
        print("Windows strings are in sync with copy.yaml.")
        return 0

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(rendered, encoding="utf-8")
    print(f"Wrote {OUTPUT_PATH.relative_to(REPO_ROOT)} ({len(flatten(copy))} strings).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
