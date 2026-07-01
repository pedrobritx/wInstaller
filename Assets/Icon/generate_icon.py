#!/usr/bin/env python3
"""Generate the wInstaller app icon with no third-party dependencies.

The icon follows ICON_GUIDELINES.md: a rounded macOS tile, a brushed-aluminum
USB-C flash drive, a sapphire connector, a small status LED, and a neutral "OS"
glyph. No Windows logo, no long text.

Rendering uses signed-distance fields with analytic anti-aliasing, supersampled
2x and box-downsampled, then written as PNG via the standard library only.

Outputs (relative to the repo root):
  Assets/AppIcon.appiconset/   -> Xcode asset catalog (icon_<size>.png + Contents.json)
  Assets/AppIcon.iconset/      -> iconutil input (icon_16x16.png ... icon_512x512@2x.png)

Run `Scripts/make-icns.sh` on a Mac to turn the iconset into AppIcon.icns.
"""

import math
import os
import struct
import zlib

SS = 2  # supersample factor
MASTER = 1024


# ---------------------------------------------------------------------------
# Vector math helpers (all in 1024-pt space)
# ---------------------------------------------------------------------------

def clamp(x, lo=0.0, hi=1.0):
    return lo if x < lo else hi if x > hi else x


def smoothcov(dist, aa=1.1):
    """Coverage (0..1) for a signed distance where <0 is inside."""
    return clamp(0.5 - dist / aa)


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c0, c1, t):
    return tuple(lerp(c0[i], c1[i], t) for i in range(3))


def sd_round_rect(px, py, cx, cy, hw, hh, r):
    qx = abs(px - cx) - (hw - r)
    qy = abs(py - cy) - (hh - r)
    ax = max(qx, 0.0)
    ay = max(qy, 0.0)
    return math.hypot(ax, ay) + min(max(qx, qy), 0.0) - r


def sd_circle(px, py, cx, cy, r):
    return math.hypot(px - cx, py - cy) - r


def sd_segment(px, py, ax, ay, bx, by):
    pax, pay = px - ax, py - ay
    bax, bay = bx - ax, by - ay
    denom = bax * bax + bay * bay
    h = 0.0 if denom == 0 else clamp((pax * bax + pay * bay) / denom)
    dx = pax - bax * h
    dy = pay - bay * h
    return math.hypot(dx, dy)


def sd_polyline(px, py, pts):
    d = 1e9
    for i in range(len(pts) - 1):
        ax, ay = pts[i]
        bx, by = pts[i + 1]
        d = min(d, sd_segment(px, py, ax, ay, bx, by))
    return d


# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------

TILE_TOP = (0.937, 0.953, 0.976)
TILE_BOTTOM = (0.831, 0.878, 0.937)
BODY_TOP = (0.964, 0.972, 0.984)
BODY_BOTTOM = (0.772, 0.800, 0.843)
BODY_EDGE = (0.627, 0.663, 0.717)
CONNECTOR = (0.227, 0.247, 0.286)
SLOT_TOP = (0.184, 0.451, 0.922)
SLOT_BOTTOM = (0.098, 0.310, 0.741)
LED = (0.196, 0.640, 1.0)
GLYPH = (0.30, 0.34, 0.40)
WHITE = (1.0, 1.0, 1.0)


def over(dst, src_rgb, src_a):
    """Straight-alpha 'over' compositing. dst/src are (r,g,b,a) / rgb+a."""
    dr, dg, db, da = dst
    out_a = src_a + da * (1 - src_a)
    if out_a <= 0:
        return (0.0, 0.0, 0.0, 0.0)
    r = (src_rgb[0] * src_a + dr * da * (1 - src_a)) / out_a
    g = (src_rgb[1] * src_a + dg * da * (1 - src_a)) / out_a
    b = (src_rgb[2] * src_a + db * da * (1 - src_a)) / out_a
    return (r, g, b, out_a)


def _arc(cx, cy, r, deg0, deg1, n=28):
    pts = []
    for k in range(n + 1):
        t = math.radians(deg0 + (deg1 - deg0) * k / n)
        pts.append((cx + r * math.cos(t), cy + r * math.sin(t)))
    return pts


# Precompute the "OS" glyph geometry within the drive body face.
def build_glyph(cx, cy, scale):
    # 'O' as an ellipse ring; 'S' as two joined circular bowls (screen coords,
    # y increases downward). The two bowls touch at (s_cx, cy) forming a clean S.
    gap = 92 * scale
    o_cx = cx - gap
    o_cy = cy
    o_rx = 60 * scale
    o_ry = 82 * scale

    s_cx = cx + gap
    a = 41 * scale  # bowl radius
    upper = _arc(s_cx, o_cy - a, a, 90, 390)   # top bowl, opens lower-right
    lower = _arc(s_cx, o_cy + a, a, 270, 570)  # bottom bowl, opens upper-left
    return {
        "o": (o_cx, o_cy, o_rx, o_ry),
        "s_arcs": [upper, lower],
        "stroke": 24 * scale,
    }


def sd_ellipse_ring(px, py, cx, cy, rx, ry):
    # Approximate signed distance to an ellipse outline.
    nx = (px - cx) / rx
    ny = (py - cy) / ry
    d = math.hypot(nx, ny) - 1.0
    # scale back to roughly pixel units
    return d * min(rx, ry)


def shade(x, y):
    """Return (r,g,b,a) for a point in 1024-pt space."""
    px, py = x, y
    out = (0.0, 0.0, 0.0, 0.0)

    margin = 96.0
    tile_cx = tile_cy = MASTER / 2.0
    tile_hw = tile_hh = (MASTER - 2 * margin) / 2.0
    tile_r = 200.0

    # Soft drop shadow behind the tile.
    sd_shadow = sd_round_rect(px, py, tile_cx, tile_cy + 26, tile_hw, tile_hh, tile_r)
    shadow_cov = smoothcov(sd_shadow, aa=60.0) * 0.35
    out = over(out, (0.10, 0.14, 0.22), shadow_cov)

    # Tile.
    sd_tile = sd_round_rect(px, py, tile_cx, tile_cy, tile_hw, tile_hh, tile_r)
    tile_cov = smoothcov(sd_tile)
    if tile_cov > 0:
        t = clamp((py - margin) / (MASTER - 2 * margin))
        tile_col = mix(TILE_TOP, TILE_BOTTOM, t)
        # subtle top-left sheen
        sheen = clamp(1.0 - math.hypot(px - 360, py - 360) / 900.0) * 0.06
        tile_col = mix(tile_col, WHITE, sheen)
        out = over(out, tile_col, tile_cov)

    # USB-C drive geometry.
    body_cx = MASTER / 2.0
    body_top = 300.0
    body_bottom = 690.0
    body_cy = (body_top + body_bottom) / 2.0
    body_hw = 150.0
    body_hh = (body_bottom - body_top) / 2.0
    body_r = 92.0

    # Drive shadow on tile.
    sd_bshadow = sd_round_rect(px, py, body_cx + 10, body_cy + 22, body_hw, body_hh, body_r)
    bshadow = smoothcov(sd_bshadow, aa=40.0) * 0.28 * tile_cov
    out = over(out, (0.12, 0.16, 0.24), bshadow)

    # Drive body.
    sd_body = sd_round_rect(px, py, body_cx, body_cy, body_hw, body_hh, body_r)
    body_cov = smoothcov(sd_body)
    if body_cov > 0:
        t = clamp((py - body_top) / (body_bottom - body_top))
        col = mix(BODY_TOP, BODY_BOTTOM, t)
        # left vertical highlight, right soft shade for a metallic feel
        hx = clamp(1.0 - abs(px - (body_cx - 70)) / 120.0) * 0.10
        col = mix(col, WHITE, hx)
        sx = clamp((px - (body_cx + 40)) / 130.0) * 0.10
        col = mix(col, BODY_EDGE, sx)
        out = over(out, col, body_cov)

    # Connector (USB-C) below the body.
    conn_cy = 748.0
    conn_hw = 104.0
    conn_hh = 58.0
    conn_r = 54.0
    sd_conn = sd_round_rect(px, py, body_cx, conn_cy, conn_hw, conn_hh, conn_r)
    conn_cov = smoothcov(sd_conn)
    if conn_cov > 0:
        out = over(out, CONNECTOR, conn_cov)
        # sapphire slot
        sd_slot = sd_round_rect(px, py, body_cx, conn_cy, conn_hw - 26, conn_hh - 24, 26)
        slot_cov = smoothcov(sd_slot)
        if slot_cov > 0:
            t = clamp((py - (conn_cy - conn_hh)) / (2 * conn_hh))
            out = over(out, mix(SLOT_TOP, SLOT_BOTTOM, t), slot_cov)

    # Status LED near the top of the body.
    sd_led_glow = sd_circle(px, py, body_cx, body_top + 66, 40)
    out = over(out, LED, smoothcov(sd_led_glow, aa=34.0) * 0.35 * body_cov)
    sd_led = sd_circle(px, py, body_cx, body_top + 66, 17)
    out = over(out, LED, smoothcov(sd_led) * body_cov)

    # "OS" glyph on the body face.
    g = build_glyph(body_cx, body_cy + 6, 0.62)
    o_cx, o_cy, o_rx, o_ry = g["o"]
    stroke = g["stroke"]
    d_o = abs(sd_ellipse_ring(px, py, o_cx, o_cy, o_rx, o_ry)) - stroke * 0.5
    d_s = min(sd_polyline(px, py, arc) for arc in g["s_arcs"]) - stroke * 0.5
    d_glyph = min(d_o, d_s)
    glyph_cov = smoothcov(d_glyph) * body_cov
    if glyph_cov > 0:
        out = over(out, GLYPH, glyph_cov)

    return out


# ---------------------------------------------------------------------------
# Rendering + PNG output
# ---------------------------------------------------------------------------

def render_master(res):
    """Render the supersampled RGBA buffer (res x res) as list of floats."""
    buf = [[(0.0, 0.0, 0.0, 0.0)] * res for _ in range(res)]
    scale = MASTER / res
    for j in range(res):
        y = (j + 0.5) * scale
        row = buf[j]
        for i in range(res):
            x = (i + 0.5) * scale
            row[i] = shade(x, y)
    return buf


def downsample(master, res, target):
    """Box-downsample the float RGBA master to target x target uint8 bytes."""
    factor = res // target
    out = bytearray(target * target * 4)
    inv = 1.0 / (factor * factor)
    idx = 0
    for j in range(target):
        for i in range(target):
            r = g = b = a = 0.0
            for dj in range(factor):
                srow = master[j * factor + dj]
                base = i * factor
                for di in range(factor):
                    pr, pg, pb, pa = srow[base + di]
                    # accumulate premultiplied for correct edges
                    r += pr * pa
                    g += pg * pa
                    b += pb * pa
                    a += pa
            a_avg = a * inv
            if a_avg > 0:
                out[idx] = int(clamp(r / a) * 255 + 0.5)
                out[idx + 1] = int(clamp(g / a) * 255 + 0.5)
                out[idx + 2] = int(clamp(b / a) * 255 + 0.5)
            out[idx + 3] = int(clamp(a_avg) * 255 + 0.5)
            idx += 4
    return bytes(out)


def write_png(path, size, rgba):
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))

    raw = bytearray()
    stride = size * 4
    for j in range(size):
        raw.append(0)  # filter type 0
        raw.extend(rgba[j * stride:(j + 1) * stride])
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n" +
           chunk(b"IHDR", ihdr) +
           chunk(b"IDAT", zlib.compress(bytes(raw), 9)) +
           chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


APPICON_SIZES = [16, 32, 64, 128, 256, 512, 1024]

# (size, scale, base) tuples for the .appiconset Contents.json and .iconset names.
APPICON_ENTRIES = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
    (256, 1), (256, 2), (512, 1), (512, 2),
]


def contents_json():
    images = []
    for base, scale in APPICON_ENTRIES:
        px = base * scale
        images.append(
            '    {\n'
            f'      "size" : "{base}x{base}",\n'
            '      "idiom" : "mac",\n'
            f'      "filename" : "icon_{px}.png",\n'
            f'      "scale" : "{scale}x"\n'
            '    }'
        )
    return (
        '{\n  "images" : [\n' + ',\n'.join(images) +
        '\n  ],\n  "info" : {\n    "version" : 1,\n    "author" : "xcode"\n  }\n}\n'
    )


def main():
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    appiconset = os.path.join(root, "Assets", "AppIcon.appiconset")
    iconset = os.path.join(root, "Assets", "AppIcon.iconset")
    os.makedirs(appiconset, exist_ok=True)
    os.makedirs(iconset, exist_ok=True)

    res = MASTER * SS
    print(f"Rendering supersampled master {res}x{res} …")
    master = render_master(res)

    pngs = {}
    for size in APPICON_SIZES:
        print(f"  downsampling -> {size}px")
        pngs[size] = downsample(master, res, size)
        write_png(os.path.join(appiconset, f"icon_{size}.png"), size, pngs[size])

    # Xcode Contents.json
    with open(os.path.join(appiconset, "Contents.json"), "w") as f:
        f.write(contents_json())

    # iconutil .iconset names
    iconset_map = [
        (16, 1, "icon_16x16.png"), (16, 2, "icon_16x16@2x.png"),
        (32, 1, "icon_32x32.png"), (32, 2, "icon_32x32@2x.png"),
        (128, 1, "icon_128x128.png"), (128, 2, "icon_128x128@2x.png"),
        (256, 1, "icon_256x256.png"), (256, 2, "icon_256x256@2x.png"),
        (512, 1, "icon_512x512.png"), (512, 2, "icon_512x512@2x.png"),
    ]
    for base, scale, name in iconset_map:
        px = base * scale
        write_png(os.path.join(iconset, name), px, pngs[px])

    # 1024 master for reference / App Store.
    write_png(os.path.join(appiconset, "icon_1024.png"), 1024, pngs[1024])
    print("Done.")


if __name__ == "__main__":
    main()
