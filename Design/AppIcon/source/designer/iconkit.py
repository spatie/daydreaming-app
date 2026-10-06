"""Shared helpers for writing Icon Composer documents and template menu bar glyphs."""

import json
import math
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ICTOOL = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
DESIGN_GENERATION = "26"

RENDITIONS = {
    "default": "Default",
    "dark": "Dark",
    "tinted-light": "TintedLight",
    "tinted-dark": "TintedDark",
    "clear-light": "ClearLight",
    "clear-dark": "ClearDark",
}

# Sizes shown on the board. macOS draws the rounded-rect body at roughly
# 824/1024 of the nominal icon size, so the small renders are padded the same way.
SMALL_SIZES = [128, 32, 16]
BODY_RATIO = 824 / 1024


# Geometry helpers

def f(value):
    return f"{value:.2f}".rstrip("0").rstrip(".")


def circle(cx, cy, r, attrs='fill="#fff"'):
    return f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(r)}" {attrs}/>'


def svg(body, size=1024, defs=""):
    defs = f"<defs>{defs}</defs>" if defs else ""
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
        f'viewBox="0 0 {size} {size}">{defs}{body}</svg>\n'
    )


def linear(id_, stops, x1=0, y1=0, x2=0, y2=1, user_space=False):
    s = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
    units = ' gradientUnits="userSpaceOnUse"' if user_space else ""
    return f'<linearGradient id="{id_}" x1="{f(x1)}" y1="{f(y1)}" x2="{f(x2)}" y2="{f(y2)}"{units}>{s}</linearGradient>'


def rgb(hex_, alpha=1.0):
    hex_ = hex_.lstrip("#")
    r, g, b = (int(hex_[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},{alpha:.5f}"


def gradient(top, bottom, y0=0.0, y1=1.0, x0=0.5, x1=0.5):
    return {
        "linear-gradient": [rgb(top), rgb(bottom)],
        "orientation": {"start": {"x": x0, "y": y0}, "stop": {"x": x1, "y": y1}},
    }


def solid(hex_, alpha=1.0):
    return {"solid": rgb(hex_, alpha)}


def specialized(default, dark=None, tinted=None):
    """fill-specializations list. Icon Composer ignores these if a plain fill exists."""
    items = [{"value": default}]
    if dark is not None:
        items.append({"appearance": "dark", "value": dark})
    if tinted is not None:
        items.append({"appearance": "tinted", "value": tinted})
    return items


def layer(name, image, fill=None, dark=None, tinted=None, glass=True, opacity=None, hidden_in=None):
    data = {"image-name": image, "name": name}
    if fill is not None:
        data["fill-specializations"] = specialized(fill, dark, tinted)
    if not glass:
        data["glass"] = False
    if opacity is not None:
        data["opacity"] = opacity
    if hidden_in:
        data["hidden-specializations"] = [{"appearance": a, "value": True} for a in hidden_in]
    return data


def group(name, layers, specular=True, translucency=None, shadow=0.2, shadow_kind="neutral", blur=None, lighting=None):
    data = {
        "name": name,
        "layers": layers,
        "specular": specular,
        "shadow": {"kind": shadow_kind, "opacity": shadow},
        "translucency": {"enabled": translucency is not None, "value": translucency or 0.0},
    }
    if blur is not None:
        data["blur-material"] = blur
    if lighting is not None:
        data["lighting"] = lighting
    return data


def drop(cx, cy, r):
    """A small raindrop, round at the bottom and pointed at the top."""
    tip = cy - r * 2.1
    return (
        f'<path fill="#000" d="M{f(cx)},{f(tip)} C{f(cx + r * 0.55)},{f(cy - r * 1.2)} {f(cx + r)},{f(cy - r * 0.6)} {f(cx + r)},{f(cy)} '
        f'A{f(r)},{f(r)} 0 0 1 {f(cx - r)},{f(cy)} C{f(cx - r)},{f(cy - r * 0.6)} {f(cx - r * 0.55)},{f(cy - r * 1.2)} {f(cx)},{f(tip)} Z"/>'
    )


def flake(cx, cy, r, w):
    arms = "".join(
        f'<path d="M{f(cx - r * math.cos(a))},{f(cy - r * math.sin(a))} L{f(cx + r * math.cos(a))},{f(cy + r * math.sin(a))}" stroke="#000" stroke-width="{w}" stroke-linecap="round"/>'
        for a in (math.pi / 2, math.pi / 6, -math.pi / 6)
    )
    return arms


def run(*cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)


def render_icon(doc, rendition, out, px):
    run(ICTOOL, str(doc), "--export-image", "--output-file", str(out), "--platform", "macOS",
        "--rendition", rendition, "--width", str(px), "--height", str(px), "--scale", "1",
        "--design-generation", DESIGN_GENERATION)


def to_8bit(path):
    run("magick", str(path), "-depth", "8", str(path))


def build(name, concept):
    assets, icon, glyphs = concept()
    folder = ROOT / name
    doc = folder / f"Daydreaming-{name}.icon"
    if doc.exists():
        shutil.rmtree(doc)
    (doc / "Assets").mkdir(parents=True)
    for file, content in assets.items():
        (doc / "Assets" / file).write_text(content)
    icon["supported-platforms"] = {"squares": ["macOS"]}
    (doc / "icon.json").write_text(json.dumps(icon, indent=2) + "\n")

    renders = folder / "renders"
    renders.mkdir(exist_ok=True)
    for key, rendition in RENDITIONS.items():
        out = renders / f"{key}-1024.png"
        render_icon(doc, rendition, out, 1024)
        to_8bit(out)
    for size in SMALL_SIZES:
        for key in ("default", "dark"):
            for scale, suffix in ((1, ""), (2, "@2x")):
                px = size * scale
                tmp = renders / f"_{key}-{size}{suffix}.png"
                render_icon(doc, RENDITIONS[key], tmp, round(px * BODY_RATIO))
                out = renders / f"{key}-{size}{suffix}.png"
                run("magick", str(tmp), "-depth", "8", "-background", "none", "-gravity", "center", "-extent", f"{px}x{px}", str(out))
                tmp.unlink()

    menubar = folder / "menubar"
    if menubar.exists():
        shutil.rmtree(menubar)
    menubar.mkdir()
    for suffix, body in glyphs.items():
        base = menubar / f"daydreaming-{name}{suffix}"
        base.with_suffix(".svg").write_text(svg(body, size=18))
        run("rsvg-convert", "-f", "pdf", "--dpi-x", "72", "--dpi-y", "72", "-o", f"{base}.pdf", f"{base}.svg")
        run("rsvg-convert", "-w", "18", "-h", "18", "-o", f"{base}.png", f"{base}.svg")
        run("rsvg-convert", "-w", "36", "-h", "36", "-o", f"{base}@2x.png", f"{base}.svg")
    print(f"built {name}")
