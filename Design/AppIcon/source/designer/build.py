#!/usr/bin/env python3
"""Builds the round 2 Daydreaming icon concepts: bold color, the wallpaper as
the subject, and change over the day.

For every concept this writes an Icon Composer document (icon.json plus
Assets/*.svg), a template menu bar glyph (SVG, PDF, PNG @1x and @2x), and
renders every appearance with ictool.

    python3 design/icons/tools/build.py             # build and render all
    python3 design/icons/tools/build.py shift sweep  # only these concepts
"""

import json
import math
import sys

from iconkit import build, circle, drop, f, flake, gradient, group, layer, linear, solid, specialized, svg

STROKE = 'fill="none" stroke="#000" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"'


def bezier(p0, p1, p2, p3, t):
    u = 1 - t
    return (
        u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
        u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1],
    )


def swoosh(p0, p1, p2, p3, thin, thick, steps=80):
    """A filled brush stroke along a cubic curve, tapering at both ends."""
    left, right = [], []
    for i in range(steps + 1):
        t = i / steps
        x, y = bezier(p0, p1, p2, p3, t)
        x2, y2 = bezier(p0, p1, p2, p3, min(1, t + 0.001))
        x1, y1 = bezier(p0, p1, p2, p3, max(0, t - 0.001))
        dx, dy = x2 - x1, y2 - y1
        n = math.hypot(dx, dy)
        nx, ny = -dy / n, dx / n
        w = (thin + (thick - thin) * math.sin(math.pi * t) ** 0.7) / 2
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    pts = left + right[::-1]
    return "M" + " L".join(f"{f(x)},{f(y)}" for x, y in pts) + " Z"


def rounded_rect(x, y, w, h, r):
    return (
        f"M{f(x + r)},{f(y)} H{f(x + w - r)} A{f(r)},{f(r)} 0 0 1 {f(x + w)},{f(y + r)} V{f(y + h - r)} "
        f"A{f(r)},{f(r)} 0 0 1 {f(x + w - r)},{f(y + h)} H{f(x + r)} A{f(r)},{f(r)} 0 0 1 {f(x)},{f(y + h - r)} "
        f"V{f(y + r)} A{f(r)},{f(r)} 0 0 1 {f(x + r)},{f(y)} Z"
    )


def arc_band(cx, cy, r, width, start_deg, end_deg):
    """A thick arc with round caps as a filled outline, going clockwise from start to end.

    Icon Composer derives the glass edge from a shape's fill area, so stroked open
    paths get a highlight along their closing chord. Filled outlines don't.
    """
    ro, ri, w = r + width / 2, r - width / 2, width / 2
    pt = lambda rad, deg: (cx + rad * math.cos(math.radians(deg)), cy - rad * math.sin(math.radians(deg)))
    sweep = (start_deg - end_deg) % 360
    large = 1 if sweep > 180 else 0
    o0, o1, i1, i0 = pt(ro, start_deg), pt(ro, end_deg), pt(ri, end_deg), pt(ri, start_deg)
    return (
        f"M{f(o0[0])},{f(o0[1])} A{f(ro)},{f(ro)} 0 {large} 1 {f(o1[0])},{f(o1[1])} "
        f"A{f(w)},{f(w)} 0 0 1 {f(i1[0])},{f(i1[1])} "
        f"A{f(ri)},{f(ri)} 0 {large} 0 {f(i0[0])},{f(i0[1])} "
        f"A{f(w)},{f(w)} 0 0 1 {f(o0[0])},{f(o0[1])} Z"
    )


# Concepts. Each returns (assets, icon_json, glyphs).
# Groups are listed front to back, like Icon Composer stores them.

def concept_shift():
    # The moment the wallpaper changes: one bold color giving way to the next along a single curve.
    curve = "M676,-20 C590,250 790,410 530,560 C300,692 452,860 392,1044"
    warm = svg(
        f'<path d="{curve} H-20 V-20 Z" fill="url(#w)"/>',
        defs=linear("w", [(0, "#FFC21A"), (0.55, "#FF7A12"), (1, "#FF4A1C")], x1=0.1, y1=0, x2=0.6, y2=0.9),
    )
    assets = {"1-warm.svg": warm}
    icon = {
        "fill-specializations": specialized(
            gradient("#3D63FF", "#1428B8", 0.2, 1.0, 0.8, 0.4),
            dark=gradient("#1D2F9E", "#070D45", 0.2, 1.0, 0.8, 0.4),
        ),
        "groups": [
            group("Before", [layer("Warm wallpaper", "1-warm.svg")], specular=True, shadow=0.45),
        ],
    }
    frame = rounded_rect(2.25, 3.25, 13.5, 11.5, 2.75)
    glyph_curve = "M10.9,3.25 C9.9,5.6 12.2,7.4 9.1,9.1 C6.4,10.6 8.2,12.6 7.4,14.75"
    glyphs = {
        "": (
            f'<clipPath id="c"><path d="{frame}"/></clipPath>'
            f'<path d="{glyph_curve} H2 V3 Z" clip-path="url(#c)" fill="#000"/>'
            f'<path d="{frame}" {STROKE}/>'
        ),
    }
    return assets, icon, glyphs


WARM = [(0, "#FFC21A"), (0.55, "#FF7A12"), (1, "#FF4A1C")]
BLUE_BG = gradient("#3D63FF", "#1428B8", 0.2, 1.0, 0.8, 0.4)
BLUE_BG_DARK = gradient("#1D2F9E", "#070D45", 0.2, 1.0, 0.8, 0.4)
NAVY_BG = gradient("#1A2266", "#080B2A")
NAVY_BG_DARK = gradient("#0E1030", "#000000")

SHIFT_SEAM = "M676,-20 C590,250 790,410 530,560 C300,692 452,860 392,1044"
TO_LEFT = "H-60 V-60 Z"  # the seam runs top to bottom; fill everything left of it
TO_TOP = "V-60 H-60 Z"   # the seam runs left to right; fill everything above it

GLYPH_BOX = (2.25, 3.25, 13.5, 11.5)


def cubic_points(curve, steps=40):
    """Samples an absolute 'M x,y C ... C ...' path into points."""
    import re
    nums = [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", curve)]
    start = (nums[0], nums[1])
    pts = [start]
    rest = nums[2:]
    for i in range(0, len(rest), 6):
        p1, p2, p3 = (rest[i], rest[i + 1]), (rest[i + 2], rest[i + 3]), (rest[i + 4], rest[i + 5])
        for k in range(1, steps + 1):
            pts.append(bezier(start, p1, p2, p3, k / steps))
        start = p3
    return pts


def band_along(curve, width):
    """A filled band of constant width centred on a multi-segment cubic path."""
    pts = cubic_points(curve)
    left, right = [], []
    for i, (x, y) in enumerate(pts):
        x1, y1 = pts[max(0, i - 1)]
        x2, y2 = pts[min(len(pts) - 1, i + 1)]
        n = math.hypot(x2 - x1, y2 - y1) or 1
        nx, ny = -(y2 - y1) / n, (x2 - x1) / n
        left.append((x + nx * width / 2, y + ny * width / 2))
        right.append((x - nx * width / 2, y - ny * width / 2))
    return "M" + " L".join(f"{f(x)},{f(y)}" for x, y in left + right[::-1]) + " Z"


def region(curve, close=TO_LEFT):
    return f"{curve} {close}"


def warm_svg(d, stops=WARM):
    return svg(f'<path d="{d}" fill="url(#w)"/>', defs=linear("w", stops, x1=0.1, y1=0, x2=0.6, y2=0.9))


def boxed_glyph(fills, box=GLYPH_BOX, outline=True, radius=2.75):
    """Glyph inside a rounded rectangle. fills is a list of (path in 1024 space, opacity)."""
    x, y, w, h = box
    frame = rounded_rect(x, y, w, h, radius)
    shapes = "".join(
        f'<path transform="translate({x},{y}) scale({f(w / 1024)},{f(h / 1024)})" d="{d}" fill="#000" fill-opacity="{o}"/>'
        for d, o in fills
    )
    body = f'<clipPath id="c"><path d="{frame}"/></clipPath><g clip-path="url(#c)">{shapes}</g>'
    if outline:
        body += f'<path d="{frame}" {STROKE}/>'
    return body


def two_tone(curve, close=TO_LEFT):
    assets = {"1-warm.svg": warm_svg(region(curve, close))}
    icon = {
        "fill-specializations": specialized(BLUE_BG, dark=BLUE_BG_DARK),
        "groups": [group("Day", [layer("Warm wallpaper", "1-warm.svg")], specular=True, shadow=0.45)],
    }
    return assets, icon, {"": boxed_glyph([(region(curve, close), 1)])}


# Shift variants

def concept_shift_horizon():
    # The seam lies down and becomes a horizon: day above, evening below.
    return two_tone("M-60,600 C180,560 330,420 520,480 C720,544 840,500 1084,420", TO_TOP)


def concept_shift_diagonal():
    # The seam runs corner to corner, the way light moves across a room.
    return two_tone("M-60,900 C220,880 300,650 480,560 C660,470 740,250 1084,140", TO_TOP)


def concept_shift_wavy():
    # A longer, more melodic seam.
    return two_tone("M600,-60 C520,110 700,230 610,380 C520,530 690,640 560,790 C470,900 520,990 470,1084")


def concept_shift_bands():
    # Three times of day instead of two: dawn, sunset, night.
    front = "M500,-60 C430,240 600,400 380,560 C200,690 320,860 270,1084"
    middle = "M800,-60 C720,250 920,410 680,580 C470,720 610,880 560,1084"
    assets = {
        "1-dawn.svg": warm_svg(region(front), [(0, "#FFD23F"), (1, "#FF9A1A")]),
        "2-sunset.svg": warm_svg(region(middle), [(0, "#FF6A3D"), (1, "#E8175D")]),
    }
    icon = {
        "fill-specializations": specialized(BLUE_BG, dark=BLUE_BG_DARK),
        "groups": [
            group("Dawn", [layer("Dawn", "1-dawn.svg")], specular=True, shadow=0.45),
            group("Sunset", [layer("Sunset", "2-sunset.svg")], specular=True, shadow=0.45),
        ],
    }
    return assets, icon, {"": boxed_glyph([(region(middle), 0.45), (region(front), 1)])}


def concept_shift_glass():
    # Shift with a ribbon of Liquid Glass along the seam: the moment of change, made of light.
    ribbon = svg(f'<path d="{band_along(SHIFT_SEAM, 64)}" fill="#fff"/>')
    assets = {"1-ribbon.svg": ribbon, "2-warm.svg": warm_svg(region(SHIFT_SEAM))}
    icon = {
        "fill-specializations": specialized(BLUE_BG, dark=BLUE_BG_DARK),
        "groups": [
            group("Seam", [layer("Glass ribbon", "1-ribbon.svg", solid("#FFFFFF"), dark=solid("#E5E5EA"))], translucency=0.55, shadow=0.35),
            group("Day", [layer("Warm wallpaper", "2-warm.svg")], specular=True, shadow=0.3),
        ],
    }
    glyph = boxed_glyph([(region(SHIFT_SEAM), 1)])
    return assets, icon, {"": glyph}


def concept_shift_echo():
    # The change in motion: a translucent after-image of the seam trails into the evening.
    echo = "M776,-20 C690,250 890,410 630,560 C400,692 552,860 492,1044"
    assets = {"1-warm.svg": warm_svg(region(SHIFT_SEAM)), "2-echo.svg": warm_svg(region(echo))}
    icon = {
        "fill-specializations": specialized(BLUE_BG, dark=BLUE_BG_DARK),
        "groups": [
            group("Day", [layer("Warm wallpaper", "1-warm.svg")], specular=True, shadow=0.45),
            group("Echo", [layer("After-image", "2-echo.svg", opacity=0.45)], specular=True, translucency=0.4, shadow=0.0),
        ],
    }
    return assets, icon, {"": boxed_glyph([(region(echo), 0.4), (region(SHIFT_SEAM), 1)])}


# Fresh ideas

STRATA_WAVES = [
    "M-60,330 C200,250 400,380 620,300 C800,236 920,280 1084,240",
    "M-60,520 C180,440 420,560 640,480 C820,416 930,470 1084,430",
    "M-60,700 C220,620 420,740 620,670 C800,608 930,650 1084,610",
    "M-60,860 C200,800 440,900 650,840 C830,790 940,820 1084,800",
]
DAY_LAYERS = [
    [(0, "#FF9A1A"), (1, "#FF7A12")],
    [(0, "#FF5A3A"), (1, "#F03A50")],
    [(0, "#C2338A"), (1, "#8A2FB0")],
    [(0, "#4A6CFF"), (1, "#1E33C8")],
]
DAWN_SKY = gradient("#FFE07A", "#FFC21A")
NIGHT_SKY = gradient("#141A4A", "#232A6E")


def crest_top(crest):
    import re
    nums = [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", crest)]
    return min(nums[1::2])


def map_path(d, box):
    """Maps an absolute M/C path from 1024 space into a glyph box."""
    import re
    x, y, w, h = box
    nums = [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", d)]
    pts = [(x + px * w / 1024, y + py * h / 1024) for px, py in zip(nums[0::2], nums[1::2])]
    head, rest = pts[0], pts[1:]
    return f"M{f(head[0])},{f(head[1])} C" + " ".join(f"{f(px)},{f(py)}" for px, py in rest)


def strata_glyph(lines, filled, box=GLYPH_BOX):
    """Rounded frame with wave lines across it and the land below the last wave filled."""
    x, y, w, h = box
    frame = rounded_rect(x, y, w, h, 2.75)
    strokes = "".join(f'<path d="{map_path(c, box)}" {STROKE}/>' for c in lines)
    land = f'<path d="{map_path(filled, box)} V{y + h + 1} H{x - 1} Z" fill="#000"/>'
    return f'<clipPath id="c"><path d="{frame}"/></clipPath><g clip-path="url(#c)">{strokes}{land}</g><path d="{frame}" {STROKE}/>'


def strata(waves, layers, sky, sky_dark, translucency=None, band=None, title="Layer"):
    """Stacked hills, front to back. With band set, each layer is a band of that height instead of running to the bottom."""
    assets, groups = {}, []
    count = len(waves)
    for i, (crest, stops) in enumerate(reversed(list(zip(waves, layers)))):
        name = f"{i + 1}-layer.svg"
        top = crest_top(crest)
        if band:
            lower = band_lower(crest, band)
            shape = f"{crest} {lower} Z"
        else:
            shape = f"{crest} V1084 H-60 Z"
        assets[name] = svg(f'<path d="{shape}" fill="url(#s)"/>', defs=linear("s", stops, y1=top, y2=top + 260, user_space=True))
        groups.append(group(f"{title} {count - i}", [layer(f"{title} {count - i}", name)], specular=True, translucency=translucency, shadow=0.35))
    icon = {"fill-specializations": specialized(sky, dark=sky_dark), "groups": groups}
    return assets, icon


def band_lower(crest, height):
    """The same crest shifted down by height, walked back from right to left."""
    import re
    nums = [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", crest)]
    pts = list(zip(nums[0::2], nums[1::2]))
    # reverse a chain of cubic segments: M p0 C c1 c2 p1 C c3 c4 p2 -> p2 C c4 c3 p1 C c2 c1 p0
    segs = [pts[i:i + 3] for i in range(1, len(pts), 3)]
    anchors = [pts[0]] + [s[2] for s in segs]
    out = f"L{f(anchors[-1][0])},{f(anchors[-1][1] + height)}"
    for k in range(len(segs) - 1, -1, -1):
        c1, c2, _ = segs[k]
        p = anchors[k]
        out += f" C{f(c2[0])},{f(c2[1] + height)} {f(c1[0])},{f(c1[1] + height)} {f(p[0])},{f(p[1] + height)}"
    return out


def wave(base, amp, periods=1.0, phase=0.0, tilt=0.0, samples=9):
    """A smooth crest from left to right: base height plus a sine, optionally tilted.

    Sampled points are joined with Catmull-Rom curves, written as absolute cubics.
    """
    xs = [-60 + i * (1144 / (samples - 1)) for i in range(samples)]
    pts = [(x, base + amp * math.sin(2 * math.pi * periods * (x + 60) / 1144 + phase) - tilt * (x - 512) / 1024) for x in xs]
    d = f"M{f(pts[0][0])},{f(pts[0][1])}"
    for i in range(len(pts) - 1):
        p0 = pts[max(0, i - 1)]
        p1, p2 = pts[i], pts[i + 1]
        p3 = pts[min(len(pts) - 1, i + 2)]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d += f" C{f(c1[0])},{f(c1[1])} {f(c2[0])},{f(c2[1])} {f(p2[0])},{f(p2[1])}"
    return d


# Five equal bands: the sky on top is no bigger than any layer below it.
BASES = [205, 410, 615, 820]


def strata_waves(crests):
    assets, icon = strata(crests, DAY_LAYERS, DAWN_SKY, gradient("#2A2148", "#141030"))
    return assets, icon, {"": strata_glyph(crests[1:3], crests[3])}


def concept_waves_even():
    # The gentle Strata wave, with every band the same height.
    return strata_waves([wave(b, 34, 1.0, 0.6 + i * 0.25) for i, b in enumerate(BASES)])


def concept_waves_parallel():
    # Every crest the same shape, stacked in rhythm.
    return strata_waves([wave(b, 40, 1.0, 0.4) for b in BASES])


def concept_waves_rolling():
    # Long, deep swells.
    return strata_waves([wave(b, 62, 0.75, 1.2 + i * 0.35) for i, b in enumerate(BASES)])


def concept_waves_ripple():
    # Short, tight waves.
    return strata_waves([wave(b, 20, 2.0, i * 0.9, samples=13) for i, b in enumerate(BASES)])


def concept_waves_swell():
    # One broad rise toward the right, every layer lifting together.
    return strata_waves([wave(b, 46, 0.5, math.pi, tilt=70) for b in BASES])


def concept_waves_drift():
    # Each layer's wave a little further along than the one above it, so the stack seems to flow.
    return strata_waves([wave(b, 44, 1.0, i * 0.9) for i, b in enumerate(BASES)])


SWELL_CRESTS = [wave(b, 46, 0.5, math.pi, tilt=70) for b in BASES]

# Top to bottom: sky (the document background), then four layers of land.
# Each entry is (default, dark, tinted), as (top, bottom) colors for a vertical gradient.
SWELL_SKY = (("#FFD84D", "#FFC229"), ("#F2A922", "#E08A1C"), ("#FFFFFF", "#F2F2F2"))
SWELL_LAYERS = [
    (("#FFA526", "#FF8A1F"), ("#EE7A1E", "#DD611B"), ("#E6E6E6", "#DCDCDC")),
    (("#FF6B45", "#F2475A"), ("#E04A3C", "#C9354E"), ("#BEBEBE", "#B4B4B4")),
    (("#D2398F", "#9B33B5"), ("#A82C86", "#7A2A9C"), ("#949494", "#8A8A8A")),
    (("#4F6BFF", "#2438D0"), ("#3550E6", "#1C2AA6"), ("#6C6C6C", "#626262")),
]

# The front (lowest) layer is solid; the three behind it are frosted glass slabs, so the
# lower edge of each slab shows faintly through the one in front of it.
SWELL_SOLID = {
    "specular-highlight-placement": "inside",
    "shadow": {"kind": "layer-color", "opacity": 0.9},
}
SWELL_FROSTED = {
    "specular-highlight-placement": "inside",
    "shadow": {"kind": "layer-color", "opacity": 0.85},
    "translucency": {"enabled": True, "value": 0.45},
    "blur-material": 0.5,
}
SWELL_SLAB = 300  # each slab overlaps the next by its height minus the band spacing


def concept_swell(solid=None, frosted=None, slab=SWELL_SLAB):
    """The chosen icon: five equal bands of the day, the land swelling gently toward the right.

    Shapes are plain white SVGs; every color lives in the document as a per-appearance
    fill, so default, dark and tinted are each tuned by hand rather than derived.
    """
    solid, frosted = solid or SWELL_SOLID, frosted or SWELL_FROSTED
    assets, groups = {}, []
    count = len(SWELL_CRESTS)
    for i in range(count - 1, -1, -1):
        crest = SWELL_CRESTS[i]
        front = i == count - 1
        name = f"{count - i}-land-{i + 1}.svg"
        lower = "V1084 H-60" if front else band_lower(crest, slab)
        assets[name] = svg(f'<path d="{crest} {lower} Z" fill="#fff"/>')
        top = max(0.0, crest_top(crest) / 1024)
        bottom = min(1.0, top + 0.26)
        (d0, d1), (k0, k1), (t0, t1) = SWELL_LAYERS[i]
        fill = layer(f"Land {i + 1}", name, gradient(d0, d1, top, bottom), dark=gradient(k0, k1, top, bottom), tinted=gradient(t0, t1, top, bottom))
        data = group(f"Land {i + 1}", [fill])
        data.update(json.loads(json.dumps(solid if front else frosted)))
        groups.append(data)
    (s0, s1), (k0, k1), (t0, t1) = SWELL_SKY
    icon = {
        "fill-specializations": specialized(gradient(s0, s1, 0.0, 0.3), dark=gradient(k0, k1, 0.0, 0.3), tinted=gradient(t0, t1, 0.0, 0.3)),
        "groups": groups,
    }
    return assets, icon, {"": strata_glyph(SWELL_CRESTS[1:3], SWELL_CRESTS[3])}


def concept_strata():
    # One landscape in layers, dawn at the top to night at the bottom.
    assets, icon = strata(STRATA_WAVES, DAY_LAYERS, DAWN_SKY, gradient("#2A2148", "#141030"))
    return assets, icon, {"": strata_glyph(STRATA_WAVES[1:3], STRATA_WAVES[3])}


def concept_strata_dusk():
    # The same layers turned around: night above, the last warm light lying low along the land.
    layers = [
        [(0, "#5A4BE0"), (1, "#3D35B8")],
        [(0, "#B0359A"), (1, "#8A2A8E")],
        [(0, "#FF5A3A"), (1, "#F03A50")],
        [(0, "#FFC21A"), (1, "#FF9A1A")],
    ]
    assets, icon = strata(STRATA_WAVES, layers, NIGHT_SKY, gradient("#05061A", "#0E1030"))
    return assets, icon, {"": strata_glyph(STRATA_WAVES[1:3], STRATA_WAVES[3])}


def concept_strata_three():
    # Fewer, calmer layers: dawn, sunset, night. Bigger shapes that hold up at 16 px.
    waves = [
        "M-60,400 C220,300 440,460 660,370 C840,300 940,330 1084,290",
        "M-60,620 C200,530 440,670 660,590 C840,526 940,560 1084,520",
        "M-60,820 C220,750 460,860 680,800 C850,756 950,780 1084,760",
    ]
    layers = [DAY_LAYERS[0], DAY_LAYERS[1], DAY_LAYERS[3]]
    assets, icon = strata(waves, layers, DAWN_SKY, gradient("#2A2148", "#141030"))
    return assets, icon, {"": strata_glyph(waves[1:2], waves[2])}


def concept_strata_glass():
    # Each hour a sheet of tinted glass; where two overlap, the colors mix like light does.
    assets, icon = strata(STRATA_WAVES, DAY_LAYERS, gradient("#1A2266", "#0A0D33"), gradient("#0E1030", "#000000"), translucency=0.6, band=360, title="Glass")
    return assets, icon, {"": strata_glyph(STRATA_WAVES[1:3], STRATA_WAVES[3])}


def concept_strata_tilt():
    # Strata on a wallpaper tile tipped into motion.
    size, angle = 640, -9
    x = y = (1024 - size) / 2
    tile = rounded_rect(x, y, size, size, 150)
    clip = f'<clipPath id="t"><path d="{tile}"/></clipPath>'
    turn = f'transform="rotate({angle} 512 512)"'
    k = size / 1024

    def fit(crest):
        import re
        nums = [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", crest)]
        pts = [(x + px * k, y + py * k) for px, py in zip(nums[0::2], nums[1::2])]
        return f"M{f(pts[0][0])},{f(pts[0][1])} C" + " ".join(f"{f(a)},{f(b)}" for a, b in pts[1:])

    def piece(d, stops, top):
        return svg(f'{clip}<g {turn}><g clip-path="url(#t)"><path d="{d}" fill="url(#s)"/></g></g>',
                   defs=linear("s", stops, y1=top, y2=top + 200, user_space=True))

    waves = [fit(c) for c in STRATA_WAVES]
    assets = {"3-sky.svg": svg(f'<g {turn}><path d="{tile}" fill="url(#s)"/></g>', defs=linear("s", [(0, "#FFE07A"), (1, "#FFC21A")], y1=y, y2=y + size, user_space=True))}
    front, back = [], []
    for i, (crest, stops) in enumerate(zip(waves, DAY_LAYERS)):
        name = f"{'1' if i >= 2 else '2'}-layer-{i + 1}.svg"
        assets[name] = piece(f"{crest} V{y + size + 60} H{x - 60} Z", stops, crest_top(crest))
        (front if i >= 2 else back).append(layer(f"Layer {i + 1}", name))
    icon = {
        "fill-specializations": specialized(gradient("#F4F1EC", "#E1DBD2"), dark=gradient("#1E1E24", "#09090C")),
        "groups": [
            group("Evening layers", front[::-1], specular=True, shadow=0.35),
            group("Day layers", back[::-1], specular=True, shadow=0.3),
            group("Sky", [layer("Sky", "3-sky.svg")], specular=True, shadow=0.45),
        ],
    }
    g = 18 / 1024
    g_tile = rounded_rect(x * g + 0.6, y * g + 0.6, size * g - 1.2, size * g - 1.2, 150 * g)
    box = (x * g, y * g, size * g, size * g)
    lines = "".join(f'<path d="{map_path(c, box)}" {STROKE}/>' for c in STRATA_WAVES[1:3])
    land = f'<path d="{map_path(STRATA_WAVES[3], box)} V18 H0 Z" fill="#000"/>'
    glyph = (
        f'<g transform="rotate({angle} 9 9)"><clipPath id="c"><path d="{g_tile}"/></clipPath>'
        f'<g clip-path="url(#c)">{lines}{land}</g><path d="{g_tile}" {STROKE}/></g>'
    )
    return assets, icon, {"": glyph}


def concept_orbit():
    # First light along the curve of the planet: the day arriving, seen from very far away.
    cx, cy, r = 512, 1290, 740
    planet = svg(circle(cx, cy, r))
    rim = svg(
        f'<path fill-rule="evenodd" fill="url(#g)" d="M{cx - r},{cy} a{r},{r} 0 1 0 {2 * r},0 a{r},{r} 0 1 0 {-2 * r},0 Z '
        f'M{cx - r},{cy + 70} a{r},{r} 0 1 0 {2 * r},0 a{r},{r} 0 1 0 {-2 * r},0 Z"/>',
        defs=linear("g", [(0, "#FF4A1C"), (0.5, "#FFD23F"), (1, "#FF4A1C")], x1=0, y1=0, x2=1, y2=0),
    )
    assets = {"1-rim.svg": rim, "2-planet.svg": planet}
    icon = {
        "fill-specializations": specialized(NAVY_BG, dark=NAVY_BG_DARK),
        "groups": [
            group("First light", [layer("Rim", "1-rim.svg")], specular=True, shadow=0.0),
            group("Planet", [layer("Planet", "2-planet.svg", gradient("#3D63FF", "#14229A", 0.5, 0.9), dark=gradient("#2A44D0", "#0B1460", 0.5, 0.9))],
                  specular=True, shadow=0.3),
        ],
    }
    gx, gy, gr = 9, 21.75, 11.5
    glyph = (
        f'<path fill="#000" fill-opacity="0.35" d="M{gx - gr},{gy} a{gr},{gr} 0 1 0 {2 * gr},0 a{gr},{gr} 0 1 0 {-2 * gr},0 Z"/>'
        f'<path fill-rule="evenodd" fill="#000" d="M{gx - gr},{gy} a{gr},{gr} 0 1 0 {2 * gr},0 a{gr},{gr} 0 1 0 {-2 * gr},0 Z '
        f'M{gx - gr},{gy + 2} a{gr},{gr} 0 1 0 {2 * gr},0 a{gr},{gr} 0 1 0 {-2 * gr},0 Z"/>'
    )
    return assets, icon, {"": f'<clipPath id="c"><path d="{rounded_rect(1.5, 2.5, 15, 13, 3)}"/></clipPath><g clip-path="url(#c)">{glyph}</g><path d="{rounded_rect(1.5, 2.5, 15, 13, 3)}" {STROKE}/>'}


def concept_halftone():
    # The picture being remade, dot by dot: big warm dots of day thinning out into night.
    colors = ["#FFD23F", "#FFC21A", "#FFA21A", "#FF7A12", "#FF5A3A", "#F03A62", "#C2338A", "#7A4BE6", "#4A6CFF"]
    n, step = 5, 158
    start = 512 - step * (n - 1) / 2
    warm, cool = [], []
    for i in range(n):
        for j in range(n):
            d = i + j
            r = 70 - d * 6.2
            dot = circle(start + j * step, start + i * step, r, f'fill="{colors[d]}"')
            (warm if d <= 4 else cool).append(dot)
    assets = {"1-day.svg": svg("".join(warm)), "2-night.svg": svg("".join(cool))}
    icon = {
        "fill-specializations": specialized(NAVY_BG, dark=NAVY_BG_DARK),
        "groups": [
            group("Day dots", [layer("Day", "1-day.svg")], specular=True, shadow=0.3),
            group("Night dots", [layer("Night", "2-night.svg")], specular=True, shadow=0.3),
        ],
    }
    gn, gs = 4, 4.1
    go = 9 - gs * (gn - 1) / 2
    dots = "".join(circle(go + j * gs, go + i * gs, 1.75 - (i + j) * 0.19, 'fill="#000"') for i in range(gn) for j in range(gn))
    return assets, icon, {"": dots}


def concept_tilt():
    # One wallpaper tile tipped into motion, holding Shift's horizon: day above, evening below.
    size, angle = 620, -9
    x = y = (1024 - size) / 2
    tile = rounded_rect(x, y, size, size, 150)
    horizon = f"M{x - 40},{y + size * 0.56} C{x + size * 0.2},{y + size * 0.5} {x + size * 0.36},{y + size * 0.36} {x + size * 0.52},{y + size * 0.44} C{x + size * 0.7},{y + size * 0.53} {x + size * 0.82},{y + size * 0.48} {x + size + 40},{y + size * 0.4}"
    clip = f'<clipPath id="t"><path d="{tile}"/></clipPath>'
    turn = f'transform="rotate({angle} 512 512)"'
    day = svg(
        f'{clip}<g {turn}><g clip-path="url(#t)"><path d="{horizon} V{y - 40} H{x - 40} Z" fill="url(#w)"/></g></g>',
        defs=linear("w", WARM, x1=0.1, y1=0, x2=0.6, y2=0.9),
    )
    night = svg(
        f'{clip}<g {turn}><g clip-path="url(#t)"><path d="{horizon} V{y + size + 40} H{x - 40} Z" fill="url(#b)"/></g></g>',
        defs=linear("b", [(0, "#4A6CFF"), (1, "#1428B8")]),
    )
    assets = {"1-day.svg": day, "2-night.svg": night}
    icon = {
        "fill-specializations": specialized(gradient("#F4F1EC", "#E1DBD2"), dark=gradient("#1E1E24", "#09090C")),
        "groups": [
            group("Day", [layer("Day", "1-day.svg")], specular=True, shadow=0.35),
            group("Evening", [layer("Evening", "2-night.svg")], specular=True, shadow=0.45),
        ],
    }
    k = 18 / 1024
    g_tile = rounded_rect(x * k + 0.6, y * k + 0.6, size * k - 1.2, size * k - 1.2, 150 * k)
    g_turn = f'transform="rotate({angle} 9 9)"'
    g_horizon = horizon.replace(",", " ").split()
    scaled = []
    for token in g_horizon:
        head = token[0] if token[0].isalpha() else ""
        num = token[1:] if head else token
        scaled.append(head + f(float(num) * k))
    pairs = " ".join(scaled)
    glyph = (
        f'<g {g_turn}><clipPath id="c"><path d="{g_tile}"/></clipPath>'
        f'<path clip-path="url(#c)" d="{pairs} V0 H0 Z" fill="#000"/>'
        f'<path d="{g_tile}" {STROKE}/></g>'
    )
    return assets, icon, {"": glyph}


def concept_ripple():
    # The wallpaper inside the wallpaper: each layer a later hour, settling toward evening.
    rings = [(820, "#FFC21A", "#FF9A1A"), (620, "#FF8A1A", "#FF5A2A"), (430, "#F2456A", "#D81E64"), (250, "#4A6CFF", "#1E33C8")]
    bottom = 900
    assets, groups = {}, []
    for i, (size, top, low) in enumerate(reversed(rings)):
        x = (1024 - size) / 2
        y = bottom - size - (820 - size) * 0.18
        name = f"{i + 1}-ring.svg"
        assets[name] = svg(f'<rect x="{f(x)}" y="{f(y)}" width="{size}" height="{size}" rx="{f(size * 0.28)}" fill="#fff"/>')
        groups.append(group(f"Hour {4 - i}", [layer(f"Hour {4 - i}", name, gradient(top, low, y / 1024, (y + size) / 1024))], specular=True, shadow=0.35))
    icon = {"fill-specializations": specialized(NAVY_BG, dark=NAVY_BG_DARK), "groups": groups}
    glyph = (
        f'<path d="{rounded_rect(1.75, 1.75, 14.5, 14.5, 4)}" {STROKE}/>'
        f'<path d="{rounded_rect(4.75, 6.25, 8.5, 8.5, 2.5)}" {STROKE}/>'
        f'<rect x="7.25" y="10" width="3.5" height="3.5" rx="1" fill="#000"/>'
    )
    return assets, icon, {"": glyph}


def concept_halfdome():
    # Yosemite's Half Dome, the built-in picture, under a sky that is day on one side and evening on the other.
    rock_path = (
        "M-20,664 C96,660 190,646 262,618 C292,452 438,306 636,294 C700,290 740,304 756,330 "
        "C762,342 764,354 762,370 C758,490 760,620 768,744 L1044,744 V1044 H-20 Z"
    )
    rock = svg(f'<path d="{rock_path}" fill="#fff"/>')
    floor = svg('<path d="M-20,776 C300,758 700,758 1044,770 V1044 H-20 Z" fill="#fff"/>')
    daylight = svg(
        '<path d="M-20,-20 H860 L-20,880 Z" fill="url(#d)"/>',
        defs=linear("d", [(0, "#FFC21A"), (0.6, "#FF7A12"), (1, "#F23B2E")], x1=0, y1=0, x2=0.7, y2=0.9),
    )
    assets = {"1-floor.svg": floor, "2-rock.svg": rock, "3-daylight.svg": daylight}
    icon = {
        "fill-specializations": specialized(
            gradient("#4467FF", "#1A2490"),
            dark=gradient("#22339C", "#090E40"),
        ),
        "groups": [
            group("Valley floor", [layer("Floor", "1-floor.svg", gradient("#0E1030", "#05060F", 0.75, 1.0), dark=gradient("#07070D", "#000000", 0.75, 1.0))],
                  specular=True, shadow=0.25),
            group("Granite", [layer("Half Dome", "2-rock.svg", gradient("#2B3170", "#141842", 0.28, 0.75), dark=gradient("#1C1F48", "#0A0B20", 0.28, 0.75))],
                  specular=True, shadow=0.3),
            group("Daylight", [layer("Day side of the sky", "3-daylight.svg", glass=False)], specular=False, shadow=0.0),
        ],
    }
    profile = "M1.5,13.3 C2.8,13.2 3.8,12.95 4.6,12.6 C5,9.4 7.6,6.5 11.1,6.25 C12.2,6.2 13,6.45 13.4,6.95 C13.6,7.2 13.65,7.5 13.65,7.85 V15.25"
    horizon = '<path d="M1.5,15.25 H16.5" fill="none" stroke="#000" stroke-width="1.5" stroke-linecap="round"/>'
    outline = f'<path d="{profile}" {STROKE}/>' + horizon
    solid_rock = f'<path d="{profile} H1.5 Z" fill="#000" stroke="#000" stroke-width="1.5" stroke-linejoin="round"/>' + horizon
    glyphs = {
        "": outline,
        "-creating": solid_rock,
        "-rain": outline + drop(15.6, 10.6, 0.95),
        "-snow": outline + flake(15.55, 9.6, 1.45, 0.8),
    }
    return assets, icon, glyphs


def concept_sweep():
    # The day as one sweep of color, from first light to evening, with a glass marker for now.
    cx, cy, r = 512, 532, 300
    a0, a1 = math.radians(225), math.radians(-45)
    arc = svg(
        f'<path d="{arc_band(cx, cy, r, 128, 225, -45)}" fill="url(#a)"/>',
        defs=linear("a", [(0, "#FFC21A"), (0.35, "#FF6A12"), (0.65, "#F0245E"), (1, "#4D63FF")], x1=cx - r, y1=0, x2=cx + r, y2=0, user_space=True),
    )
    now = math.radians(38)
    marker = svg(circle(cx + r * math.cos(now), cy - r * math.sin(now), 90))
    assets = {"1-now.svg": marker, "2-day.svg": arc}
    icon = {
        "fill-specializations": specialized(
            gradient("#171C4A", "#070920"),
            dark=gradient("#0C0D1C", "#000000"),
        ),
        "groups": [
            group("Now", [layer("Now", "1-now.svg", solid("#FFFFFF"), dark=solid("#F2F2F7"))], translucency=0.25, shadow=0.45),
            group("Day", [layer("Sweep of the day", "2-day.svg")], specular=True, shadow=0.3),
        ],
    }
    gr = 6.25
    g0 = (9 + gr * math.cos(a0), 9.4 - gr * math.sin(a0))
    g1 = (9 + gr * math.cos(a1), 9.4 - gr * math.sin(a1))
    gn = (9 + gr * math.cos(now), 9.4 - gr * math.sin(now))
    glyphs = {
        "": (
            f'<clipPath id="k"><path clip-rule="evenodd" d="M0,0 H18 V18 H0 Z M{f(gn[0] - 3.1)},{f(gn[1])} a3.1,3.1 0 1 0 6.2,0 a3.1,3.1 0 1 0 -6.2,0 Z"/></clipPath>'
            f'<path d="M{f(g0[0])},{f(g0[1])} A{gr},{gr} 0 1 1 {f(g1[0])},{f(g1[1])}" {STROKE} clip-path="url(#k)"/>'
            + circle(*gn, 2.15, 'fill="#000"')
        ),
    }
    return assets, icon, glyphs


def concept_monogram():
    # A D that holds one whole day: dawn, midday, sunset and night, top to bottom.
    left, top, bottom = 258, 232, 792
    r = (bottom - top) / 2
    bx = left + 226
    outer = (
        f"M{left + 64},{top} H{bx} A{r},{r} 0 0 1 {bx},{bottom} H{left + 64} "
        f"A64,64 0 0 1 {left},{bottom - 64} V{top + 64} A64,64 0 0 1 {left + 64},{top} Z"
    )
    ir = r - 128
    inner = f"M{left + 128},{top + 128} H{bx} A{ir},{ir} 0 0 1 {bx},{bottom - 128} H{left + 128} Z"
    # dawn, midday, sunset, night, separated by thin clear gaps so they read as slices of time
    bands = ["#FFD23F", "#FF8A1A", "#F23F7A", "#5A5CFF"]
    gap = 14 / (bottom - top)
    stops = []
    for i, c in enumerate(bands):
        start, end = i / len(bands), (i + 1) / len(bands)
        if i:
            stops.append((f(start), "#000", 0))
            start += gap / 2
            stops.append((f(start), "#000", 0))
        stops += [(f(start), c, 1), (f(end - (gap / 2 if i < len(bands) - 1 else 0)), c, 1)]
    stop_tags = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
    letter = svg(
        f'<path fill-rule="evenodd" fill="url(#b)" d="{outer} {inner}"/>',
        defs=f'<linearGradient id="b" x1="0" y1="{top}" x2="0" y2="{bottom}" gradientUnits="userSpaceOnUse">{stop_tags}</linearGradient>',
    )
    assets = {"1-letter.svg": letter}
    icon = {
        "fill-specializations": specialized(
            gradient("#1D2366", "#0A0C2C"),
            dark=gradient("#101018", "#000000"),
        ),
        "groups": [
            group("Letter", [layer("A day in four bands", "1-letter.svg")], specular=True, shadow=0.4),
        ],
    }
    d_outer = "M4.25,3 H8.75 A6,6 0 0 1 8.75,15 H4.25 A1.25,1.25 0 0 1 3,13.75 V4.25 A1.25,1.25 0 0 1 4.25,3 Z"
    letter_g = f'<path d="{d_outer}" {STROKE}/>'
    horizon = '<path d="M3,10.5 H14.5" fill="none" stroke="#000" stroke-width="1.5"/>'
    glyphs = {
        "": letter_g + horizon,
        "-creating": f'<path d="{d_outer}" fill="#000" stroke="#000" stroke-width="1.5" stroke-linejoin="round"/>',
        "-rain": letter_g + horizon + drop(8.6, 7.7, 1.05),
        "-snow": letter_g + horizon + flake(8.6, 6.9, 1.65, 0.8),
    }
    return assets, icon, glyphs


def concept_repaint():
    # The wallpaper repainted: one confident brush stroke across the frame.
    fx, fy, fw, fh = 196, 262, 632, 500
    t = 44
    frame = svg(
        f'<path fill-rule="evenodd" fill="#fff" d="{rounded_rect(fx, fy, fw, fh, 86)} {rounded_rect(fx + t, fy + t, fw - 2 * t, fh - 2 * t, 86 - t)}"/>'
    )
    stroke = svg(
        f'<path d="{swoosh((104, 630), (380, 330), (600, 800), (920, 420), 36, 168)}" fill="url(#p)"/>',
        defs=linear("p", [(0, "#FFC21A"), (0.45, "#FF5A1F"), (1, "#E8175D")], x1=104, y1=0, x2=920, y2=0, user_space=True),
    )
    assets = {"1-stroke.svg": stroke, "2-frame.svg": frame}
    icon = {
        "fill-specializations": specialized(
            gradient("#1B2160", "#0A0D2E"),
            dark=gradient("#101018", "#000000"),
        ),
        "groups": [
            group("Brush stroke", [layer("Stroke", "1-stroke.svg")], specular=True, shadow=0.45),
            group("Wallpaper", [layer("Frame", "2-frame.svg", solid("#FFFFFF"), dark=solid("#E5E5EA"))], translucency=0.3, shadow=0.3),
        ],
    }
    g_frame = rounded_rect(2.25, 4, 13.5, 10, 2.5)
    g_stroke = swoosh((1.1, 10.4), (5.6, 5.6), (9.4, 14.2), (16.9, 7.9), 0.7, 3.3, steps=40)
    # the frame breaks around the paint so the stroke reads as on top of it
    g_halo = swoosh((1.1, 10.4), (5.6, 5.6), (9.4, 14.2), (16.9, 7.9), 2.9, 5.5, steps=40)
    glyphs = {
        "": (
            f'<clipPath id="k"><path clip-rule="evenodd" d="M0,0 H18 V18 H0 Z {g_halo}"/></clipPath>'
            f'<path d="{g_frame}" {STROKE} clip-path="url(#k)"/>'
            f'<path d="{g_stroke}" fill="#000"/>'
        ),
    }
    return assets, icon, glyphs


def concept_peel():
    # The wallpaper turning like a page: today's color peels back to show the next one underneath.
    ax, by = 556, 468
    flap = (
        f"M{ax},-8 C{ax + 40},{by * 0.32} {ax + 120},{by * 0.62} {ax + 10},{by - 30} "
        f"Q{ax + 4},{by + 6} {ax + 50},{by - 2} C{1024 - 90},{by - 90} {1024 - 300},{by - 60} 1032,{by} Z"
    )
    sheet = svg(
        f'<path d="M-8,-8 H{ax} L1032,{by} V1032 H-8 Z" fill="url(#day)"/>',
        defs=linear("day", [(0, "#FFC21A"), (0.5, "#FF6A12"), (1, "#EC2B4E")], x1=0.15, y1=0, x2=0.7, y2=1),
    )
    assets = {"1-flap.svg": svg(f'<path d="{flap}" fill="#fff"/>'), "2-sheet.svg": sheet}
    icon = {
        "fill-specializations": specialized(
            gradient("#4467FF", "#14229A", 0.0, 0.6, 0.9, 0.3),
            dark=gradient("#1E2E9A", "#070B3A", 0.0, 0.6, 0.9, 0.3),
        ),
        "groups": [
            group("Page turn", [layer("Flap", "1-flap.svg", gradient("#FFFFFF", "#E9E9EF", 0.1, 0.5, 0.6, 0.6), dark=gradient("#E5E5EA", "#B8B8C4", 0.1, 0.5, 0.6, 0.6))],
                  translucency=0.15, shadow=0.45),
            group("Wallpaper", [layer("Today", "2-sheet.svg")], specular=False, shadow=0.0),
        ],
    }
    outline = "M11.25,3.25 H4.25 A2.5,2.5 0 0 0 1.75,5.75 V12.25 A2.5,2.5 0 0 0 4.25,14.75 H13.75 A2.5,2.5 0 0 0 16.25,12.25 V8.25"
    flap_g = "M11.25,3.25 C11.65,5.4 11.35,7.1 10.6,8.75 C12.4,8.1 14.3,8.05 16.25,8.25 Z"
    glyphs = {"": f'<path d="{outline}" {STROKE}/><path d="{flap_g}" fill="#000" stroke="#000" stroke-width="1.5" stroke-linejoin="round"/>'}
    return assets, icon, glyphs


CONCEPTS = {
    "shift": concept_shift,
    "shift-horizon": concept_shift_horizon,
    "shift-diagonal": concept_shift_diagonal,
    "shift-wavy": concept_shift_wavy,
    "shift-bands": concept_shift_bands,
    "shift-glass": concept_shift_glass,
    "shift-echo": concept_shift_echo,
    "strata": concept_strata,
    "strata-dusk": concept_strata_dusk,
    "strata-three": concept_strata_three,
    "strata-glass": concept_strata_glass,
    "strata-tilt": concept_strata_tilt,
    "waves-even": concept_waves_even,
    "waves-parallel": concept_waves_parallel,
    "waves-rolling": concept_waves_rolling,
    "waves-ripple": concept_waves_ripple,
    "waves-swell": concept_waves_swell,
    "waves-drift": concept_waves_drift,
    "swell": concept_swell,
    "orbit": concept_orbit,
    "halftone": concept_halftone,
    "ripple": concept_ripple,
    "tilt": concept_tilt,
    "halfdome": concept_halfdome,
    "sweep": concept_sweep,
    "monogram": concept_monogram,
    "repaint": concept_repaint,
    "peel": concept_peel,
}


if __name__ == "__main__":
    for name in sys.argv[1:] or CONCEPTS:
        build(name, CONCEPTS[name])
