#!/usr/bin/env python3
"""Regenerate the approved Swell document, native renders and web exports locally."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

DESIGN = Path(__file__).resolve().parent.parent
REPO = DESIGN.parent.parent
DOC = REPO / "WeatherCanvas" / "Resources" / "Daydreaming.icon"
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent / "designer"))
import build as source_build
import package as source_package
from iconkit import ICTOOL, RENDITIONS


def run(*command):
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL)


def contents(directory):
    return {str(path.relative_to(directory)): path.read_bytes() for path in sorted(directory.rglob("*")) if path.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-only", action="store_true", help="Check source reproducibility without replacing the app document.")
    args = parser.parse_args()
    for folder in ("renders", "web", "xcode", "validation"):
        (DESIGN / folder).mkdir(exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="daydreaming-icon-") as temporary:
        temporary = Path(temporary)
        generated = temporary / "Daydreaming.icon"
        (generated / "Assets").mkdir(parents=True)
        assets, icon, _ = source_build.concept_swell()
        for filename, svg in assets.items():
            (generated / "Assets" / filename).write_text(svg)
        icon["supported-platforms"] = {"squares": ["macOS"]}
        (generated / "icon.json").write_text(json.dumps(icon, indent=2) + "\n")
        if args.verify_only:
            if contents(generated) != contents(DOC):
                raise SystemExit("The approved app document differs from the preserved Swell generator.")
        else:
            shutil.rmtree(DOC)
            shutil.copytree(generated, DOC)
        print("Source reproducibility verified.", flush=True)

        for size in (1024, 512, 256, 128, 64, 32, 16):
            for key, rendition in RENDITIONS.items():
                output = DESIGN / "renders" / f"daydreaming-{key}-{size}.png"
                run(ICTOOL, str(DOC), "--export-image", "--output-file", str(output), "--platform", "macOS",
                    "--rendition", rendition, "--width", str(size), "--height", str(size), "--scale", "1", "--design-generation", "26")
                run("magick", str(output), "-depth", "8", str(output))
            print(f"Native six-appearance render: {size}px", flush=True)

        compiled = temporary / "compiled"
        compiled.mkdir()
        result = subprocess.run(["xcrun", "actool", str(DOC), "--compile", str(compiled), "--platform", "macosx",
                                 "--minimum-deployment-target", "26.0", "--app-icon", "Daydreaming",
                                 "--output-partial-info-plist", str(compiled / "partial.plist"), "--output-format", "human-readable-text",
                                 "--warnings", "--errors", "--notices"], capture_output=True, text=True)
        report = result.stdout + result.stderr
        (DESIGN / "validation" / "actool.txt").write_text(report)
        if result.returncode or any("warning" in line.lower() or "error" in line.lower() for line in report.splitlines()):
            raise SystemExit("actool reported an error or warning. See Design/AppIcon/validation/actool.txt.")
        shutil.copyfile(compiled / "Daydreaming.icns", DESIGN / "xcode" / "Daydreaming.icns")
        iconset = DESIGN / "xcode" / "Daydreaming.iconset"
        if iconset.exists():
            shutil.rmtree(iconset)
        run("iconutil", "-c", "iconset", str(compiled / "Daydreaming.icns"), "-o", str(iconset))
        print("actool compiled without warnings or errors.", flush=True)

        for appearance in ("default", "dark"):
            for rounded, name in ((True, "rounded"), (False, "square")):
                suffix = "-dark" if appearance == "dark" else ""
                output = DESIGN / "web" / f"daydreaming-flat-{name}{suffix}.svg"
                output.write_text(source_package.flat_svg(appearance, rounded))
                run("rsvg-convert", "-w", "1024", "-h", "1024", "-o", str(output.with_suffix(".png")), str(output))
        for appearance, name in (("default", "daydreaming-glass-1024.png"), ("dark", "daydreaming-glass-dark-1024.png")):
            shutil.copyfile(DESIGN / "renders" / f"daydreaming-{appearance}-1024.png", DESIGN / "web" / name)
        manifest = {path: hashlib.sha256(data).hexdigest() for path, data in contents(DOC).items()}
        (DESIGN / "validation" / "document-sha256.json").write_text(json.dumps(manifest, indent=2) + "\n")
        print("Web exports and document digest manifest written.", flush=True)


if __name__ == "__main__":
    main()
