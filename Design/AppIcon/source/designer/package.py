#!/usr/bin/env python3
"""Assembles design/icons/final/: the chosen Swell icon, ready to hand over.

    python3 design/icons/tools/package.py

It rebuilds Swell from source, then writes:

    final/Daydreaming.icon        the Icon Composer document (the source of truth)
    final/renders/                every appearance at 1024 px, plus 512/256/128/64/32/16
    final/xcode/                  what Xcode's actool compiles from the document
    final/web/                    flat SVG and PNG versions for the website and favicons
    final/source/                 the scripts that generate all of the above
"""

import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build  # noqa: E402
from iconkit import ICTOOL, RENDITIONS, f  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
FINAL = ROOT / "final"


def run(*cmd, **kwargs):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, **kwargs)


def squircle(inset=0.0, n=5.0, steps=720):
    """A superellipse close to the macOS icon shape, for flat web versions only."""
    a = 512 - inset
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        pts.append((512 + a * math.copysign(abs(c) ** (2 / n), c), 512 + a * math.copysign(abs(s) ** (2 / n), s)))
    return "M" + " L".join(f"{f(x)},{f(y)}" for x, y in pts) + " Z"


def flat_svg(appearance, rounded):
    """Swell drawn flat: the same bands and colors, without the system's glass."""
    index = 1 if appearance == "dark" else 0
    (s0, s1) = build.SWELL_SKY[index]
    defs = [f'<linearGradient id="sky" x1="0" y1="0" x2="0" y2="307" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="{s0}"/><stop offset="1" stop-color="{s1}"/></linearGradient>']
    shapes = ['<rect width="1024" height="1024" fill="url(#sky)"/>']
    for i, crest in enumerate(build.SWELL_CRESTS):
        top = max(0.0, build.crest_top(crest))
        c0, c1 = build.SWELL_LAYERS[i][index]
        defs.append(f'<linearGradient id="l{i}" x1="0" y1="{f(top)}" x2="0" y2="{f(top + 266)}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="{c0}"/><stop offset="1" stop-color="{c1}"/></linearGradient>')
        shapes.append(f'<path d="{crest} V1084 H-60 Z" fill="url(#l{i})"/>')
    body = "".join(shapes)
    if rounded:
        defs.append(f'<clipPath id="shape"><path d="{squircle()}"/></clipPath>')
        body = f'<g clip-path="url(#shape)">{body}</g>'
    else:
        body = f'<g clip-path="url(#square)">{body}</g>'
        defs.append('<clipPath id="square"><rect width="1024" height="1024"/></clipPath>')
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><defs>{"".join(defs)}</defs>{body}</svg>\n'


def main():
    build.build("swell", build.CONCEPTS["swell"])
    if FINAL.exists():
        shutil.rmtree(FINAL)
    for sub in ("renders", "xcode", "web", "source"):
        (FINAL / sub).mkdir(parents=True)

    doc = FINAL / "Daydreaming.icon"
    shutil.copytree(ROOT / "swell" / "Daydreaming-swell.icon", doc)

    for key, rendition in RENDITIONS.items():
        out = FINAL / "renders" / f"daydreaming-{key}-1024.png"
        run(ICTOOL, str(doc), "--export-image", "--output-file", str(out), "--platform", "macOS", "--rendition", rendition,
            "--width", "1024", "--height", "1024", "--scale", "1", "--design-generation", "26")
        run("magick", str(out), "-depth", "8", str(out))
    for size in (512, 256, 128, 64, 32, 16):
        for key in ("default", "dark"):
            out = FINAL / "renders" / f"daydreaming-{key}-{size}.png"
            run(ICTOOL, str(doc), "--export-image", "--output-file", str(out), "--platform", "macOS", "--rendition", RENDITIONS[key],
                "--width", str(size), "--height", str(size), "--scale", "1", "--design-generation", "26")
            run("magick", str(out), "-depth", "8", str(out))

    with tempfile.TemporaryDirectory() as tmp:
        compiled = Path(tmp) / "out"
        compiled.mkdir()
        result = subprocess.run(
            ["xcrun", "actool", str(doc), "--compile", str(compiled), "--platform", "macosx", "--minimum-deployment-target", "26.0",
             "--app-icon", "Daydreaming", "--output-partial-info-plist", str(compiled / "partial.plist"),
             "--output-format", "human-readable-text", "--warnings", "--errors", "--notices"],
            capture_output=True, text=True, check=True,
        )
        problems = [line for line in result.stdout.splitlines() if "warning" in line or "error" in line]
        if problems:
            raise SystemExit("actool reported problems:\n" + "\n".join(problems))
        shutil.copy(compiled / "Daydreaming.icns", FINAL / "xcode" / "Daydreaming.icns")
        run("iconutil", "-c", "iconset", str(compiled / "Daydreaming.icns"), "-o", str(FINAL / "xcode" / "Daydreaming.iconset"))

    web = FINAL / "web"
    for appearance in ("default", "dark"):
        for rounded, name in ((True, "rounded"), (False, "square")):
            path = web / f"daydreaming-flat-{name}{'-dark' if appearance == 'dark' else ''}.svg"
            path.write_text(flat_svg(appearance, rounded))
            run("rsvg-convert", "-w", "1024", "-h", "1024", "-o", str(path.with_suffix(".png")), str(path))
    shutil.copy(FINAL / "renders" / "daydreaming-default-1024.png", web / "daydreaming-glass-1024.png")
    shutil.copy(FINAL / "renders" / "daydreaming-dark-1024.png", web / "daydreaming-glass-dark-1024.png")

    for script in ("build.py", "iconkit.py", "package.py", "final-README.md"):
        shutil.copy(ROOT / "tools" / script, FINAL / "source" / script)
    shutil.copy(ROOT / "tools" / "final-README.md", FINAL / "README.md")
    print("wrote", FINAL)


if __name__ == "__main__":
    main()
