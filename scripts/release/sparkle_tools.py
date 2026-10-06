"""Fetch only the pinned official Sparkle distribution. Never access signing keys."""
import hashlib
from pathlib import Path
import subprocess
import urllib.request

VERSION = "2.10.0"
SHA256 = "c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
URL = f"https://github.com/sparkle-project/Sparkle/releases/download/{VERSION}/Sparkle-{VERSION}.tar.xz"
ACCOUNT = "be.spatie.daydreaming.sparkle"


def fetch(destination: Path) -> Path:
    destination.mkdir(parents=True, exist_ok=False)
    archive = destination / "Sparkle.tar.xz"
    with urllib.request.urlopen(URL, timeout=60) as response, archive.open("wb") as output:
        while chunk := response.read(1024 * 1024):
            output.write(chunk)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        raise ValueError("Official Sparkle archive checksum mismatch")
    # The checksum pins the complete official archive, including its extraction layout.
    subprocess.run(["/usr/bin/tar", "-xJf", str(archive), "-C", str(destination)], check=True)
    for name in ("generate_keys", "generate_appcast", "sign_update"):
        if not (destination / "bin" / name).is_file():
            raise ValueError(f"Missing official Sparkle tool: {name}")
    return destination / "bin"


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    print(fetch(parser.parse_args().destination))
