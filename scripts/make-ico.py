#!/usr/bin/env python3
"""Build the Windows app icon (.ico) from the existing PNG icon set.

ICO files may embed PNG-compressed images directly (supported since Windows
Vista), so this needs no imaging library. Output:
apps/windows/WInstaller.App/Assets/wInstaller.ico
"""
import struct
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ICONSET = REPO_ROOT / "Assets" / "AppIcon.appiconset"
OUTPUT = REPO_ROOT / "apps" / "windows" / "WInstaller.App" / "Assets" / "wInstaller.ico"

SIZES = [16, 32, 64, 128, 256]


def main() -> None:
    images = [(size, (ICONSET / f"icon_{size}.png").read_bytes()) for size in SIZES]

    header = struct.pack("<HHH", 0, 1, len(images))
    entries = b""
    offset = len(header) + 16 * len(images)
    payload = b""
    for size, data in images:
        dimension = 0 if size >= 256 else size  # 0 encodes 256 in ICO entries
        entries += struct.pack(
            "<BBBBHHII", dimension, dimension, 0, 0, 1, 32, len(data), offset
        )
        payload += data
        offset += len(data)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(header + entries + payload)
    print(f"Wrote {OUTPUT.relative_to(REPO_ROOT)} ({OUTPUT.stat().st_size} bytes).")


if __name__ == "__main__":
    main()
