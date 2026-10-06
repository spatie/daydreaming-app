"""Fetch only the pinned official Sparkle distribution. Never access signing keys."""
import hashlib
import base64
import os
import shutil
from pathlib import Path
import subprocess
import urllib.request

VERSION = "2.10.0"
SHA256 = "c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
URL = f"https://github.com/sparkle-project/Sparkle/releases/download/{VERSION}/Sparkle-{VERSION}.tar.xz"
ACCOUNT = "be.spatie.daydreaming.sparkle"


def signing_arguments(key_file: Path | None):
    if key_file is None:
        return ["--account", ACCOUNT]
    if not key_file.is_file() or key_file.stat().st_mode & 0o077:
        raise ValueError("Sparkle key file must exist with owner-only permissions")
    return ["--ed-key-file", str(key_file.resolve())]


def public_key(key_file: Path):
    """Derive the public half of a Sparkle 2.10 seed without a Keychain prompt."""
    signing_arguments(key_file)
    seed = base64.b64decode(key_file.read_text().strip(), validate=True)
    if len(seed) != 32:
        raise ValueError("Expected a Sparkle 2.10 private seed (32 bytes)")
    # RFC 8410 PKCS#8 prefix for an Ed25519 private seed. Input stays in memory.
    encoded = bytes.fromhex("302e020100300506032b657004220420") + seed
    openssl = os.environ.get("DAYDREAMING_OPENSSL") or shutil.which("openssl") or "/usr/bin/openssl"
    result = subprocess.run([openssl, "pkey", "-inform", "DER", "-pubout", "-outform", "DER"],
                            input=encoded, capture_output=True)
    if result.returncode or len(result.stdout) != 44:
        raise ValueError("Unable to derive the Sparkle public key")
    return base64.b64encode(result.stdout[-32:]).decode()


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
