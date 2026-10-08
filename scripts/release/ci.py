"""CI-only signing setup, cleanup and release input checks. Never export local keys."""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import subprocess
import sys
from sparkle_tools import public_key

IDENTITY = "Developer ID Application: Spatie (97KRXCRMAY)"
REQUIRED = ("APPLE_CERTIFICATE_P12", "APPLE_CERTIFICATE_PASSWORD", "APPLE_API_KEY_P8",
            "APPLE_API_KEY_ID", "APPLE_API_ISSUER_ID", "DAYDREAMING_SPARKLE_PRIVATE_KEY",
            "DAYDREAMING_WEATHERKIT_PROFILE",
            "DAYDREAMING_S3_ACCESS_KEY_ID", "DAYDREAMING_S3_SECRET_ACCESS_KEY",
            "DAYDREAMING_S3_ENDPOINT", "DAYDREAMING_S3_REGION", "DAYDREAMING_S3_BUCKET",
            "DAYDREAMING_S3_PREFIX", "DAYDREAMING_OBJECT_BASE_URL", "DAYDREAMING_RELEASE_TOKEN")


def preflight(environment):
    missing = [name for name in REQUIRED if not environment.get(name)]
    if missing:
        raise ValueError("Not configured: " + ", ".join(missing))
    for name in ("DAYDREAMING_S3_ENDPOINT", "DAYDREAMING_OBJECT_BASE_URL"):
        from urllib.parse import urlsplit
        url = urlsplit(environment[name])
        if url.scheme != "https" or not url.hostname or url.username or url.password or url.query or url.fragment:
            raise ValueError(f"{name} must be a plain HTTPS URL")


def run(*arguments):
    # No command echo or raw exceptions: security command arguments contain passwords.
    result = subprocess.run([str(item) for item in arguments], capture_output=True, text=True)
    if result.returncode:
        raise ValueError(f"Credential operation failed ({Path(str(arguments[0])).name})")
    return result.stdout.strip()


def directory():
    if os.environ.get("GITHUB_ACTIONS") != "true" or not os.environ.get("RUNNER_TEMP"):
        raise ValueError("Credential setup and cleanup only run in GitHub Actions")
    return Path(os.environ["RUNNER_TEMP"]).resolve()


def cleanup():
    root = directory()
    state = root / "daydreaming-keychain-state.json"
    keychain = root / "daydreaming-signing.keychain-db"
    errors = []
    if state.is_file():
        saved = json.loads(state.read_text())
        for command in (("security", "default-keychain", "-d", "user", "-s", saved["default"]),
                        ("security", "list-keychains", "-d", "user", "-s", *saved["search"])):
            try:
                run(*command)
            except ValueError:
                errors.append("Unable to restore original keychain configuration")
        result = subprocess.run(["security", "delete-keychain", str(keychain)], capture_output=True)
        if result.returncode and keychain.exists():
            errors.append("Unable to delete temporary signing keychain")
        state.unlink()
    for name in ("daydreaming-cert.p12", "daydreaming-notary.p8", "daydreaming-sparkle.key",
                 "daydreaming-weatherkit.provisionprofile"):
        (root / name).unlink(missing_ok=True)
    if errors:
        raise ValueError("; ".join(errors))


def setup():
    root = directory()
    os.umask(0o077)
    state = root / "daydreaming-keychain-state.json"
    if state.exists():
        raise ValueError("Existing CI credential state, refusing to overwrite")
    saved = {"default": shlex.split(run("security", "default-keychain", "-d", "user"))[0],
             "search": shlex.split(run("security", "list-keychains", "-d", "user"))}
    state.write_text(json.dumps(saved))
    keychain = root / "daydreaming-signing.keychain-db"
    password = secrets.token_urlsafe(32)
    certificate = root / "daydreaming-cert.p12"
    certificate.write_bytes(base64.b64decode(os.environ["APPLE_CERTIFICATE_P12"], validate=True))
    run("security", "create-keychain", "-p", password, keychain)
    run("security", "set-keychain-settings", keychain)
    run("security", "unlock-keychain", "-p", password, keychain)
    run("security", "import", certificate, "-k", keychain, "-P", os.environ["APPLE_CERTIFICATE_PASSWORD"],
        "-T", "/usr/bin/codesign", "-T", "/usr/bin/security", "-f", "pkcs12")
    certificate.unlink()
    run("security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, keychain)
    run("security", "list-keychains", "-d", "user", "-s", *saved["search"], keychain)
    run("security", "default-keychain", "-d", "user", "-s", keychain)
    if IDENTITY not in run("security", "find-identity", "-v", "-p", "codesigning", keychain):
        raise ValueError("Expected the Spatie Developer ID Application identity")
    notary = root / "daydreaming-notary.p8"
    notary.write_bytes(base64.b64decode(os.environ["APPLE_API_KEY_P8"], validate=True))
    run("xcrun", "notarytool", "store-credentials", "daydreaming-ci", "--key", notary,
        "--key-id", os.environ["APPLE_API_KEY_ID"], "--issuer", os.environ["APPLE_API_ISSUER_ID"],
        "--keychain", keychain)
    notary.unlink()
    key = root / "daydreaming-sparkle.key"
    key.write_text(os.environ["DAYDREAMING_SPARKLE_PRIVATE_KEY"].strip())
    profile = root / "daydreaming-weatherkit.provisionprofile"
    profile.write_bytes(base64.b64decode(os.environ["DAYDREAMING_WEATHERKIT_PROFILE"], validate=True))
    project = (Path(__file__).resolve().parents[2] / "project.yml").read_text()
    expected_key = re.search(r'DAYDREAMING_SPARKLE_PUBLIC_KEY:\s*"([A-Za-z0-9+/=]+)"', project).group(1)
    if public_key(key) != expected_key:
        raise ValueError("CI Sparkle key does not match the app's committed public key")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("preflight", "setup", "cleanup"))
    args = parser.parse_args()
    try:
        {"preflight": lambda: preflight(os.environ), "setup": setup, "cleanup": cleanup}[args.action]()
    except Exception as error:
        # Do not print raw OS/subprocess errors containing credential arguments.
        print(str(error) if isinstance(error, ValueError) else "CI credential operation failed", file=sys.stderr)
        sys.exit(1)
