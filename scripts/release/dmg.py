"""Build the branded installer using an isolated, checksum-pinned packaging tool."""
from pathlib import Path
import os
import subprocess
import venv


def build(app: Path, output: Path, source: Path, work: Path):
    if output.exists():
        raise ValueError("Installer output already exists")
    packaging = source / "scripts/release"
    environment = work / "dmg-tools"
    venv.EnvBuilder(with_pip=True).create(environment)
    python = environment / "bin/python3"
    subprocess.run([str(python), "-m", "pip", "install", "--disable-pip-version-check",
                    "--require-hashes", "--only-binary=:all:", "-r",
                    str(packaging / "dmg-requirements.txt")], check=True)
    subprocess.run([str(python), "-m", "dmgbuild", "-s", str(packaging / "dmg-settings.py"),
                    "-D", f"app={app.resolve()}", "-D", f"design={source / 'Design/DMG'}",
                    "Daydreaming", str(output)], check=True)
    verify(app, output, work)


def verify(app: Path, output: Path, work: Path):
    """Verify the copied app, not just the separately signed disk image."""
    mount = work / "dmg-verification"
    mount.mkdir()
    subprocess.run(["hdiutil", "attach", "-nobrowse", "-readonly", "-mountpoint",
                    str(mount), str(output)], check=True, stdout=subprocess.DEVNULL)
    try:
        copied = mount / "Daydreaming.app"
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(copied)], check=True)
        if (app / "Contents/Info.plist").read_bytes() != (copied / "Contents/Info.plist").read_bytes():
            raise ValueError("Installer changed the app's build identity")
        if os.readlink(mount / "Applications") != "/Applications":
            raise ValueError("Incorrect Applications shortcut")
        for name in (".DS_Store", ".background.tiff"):
            if not (mount / name).is_file():
                raise ValueError(f"Installer is missing {name}")
    finally:
        subprocess.run(["hdiutil", "detach", str(mount)], check=True, stdout=subprocess.DEVNULL)
