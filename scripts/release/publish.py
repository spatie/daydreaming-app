"""Publish verified immutable files first, then promote the exact signed feed."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from dmg import verify as verify_dmg
from feed import DOWNLOAD_PREFIX, FEED_URL, validate
from prepare import TEAM, validate_app
from sparkle_tools import fetch, signing_arguments

SITE = "https://getdaydreaming.com"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, file, code, message, headers, target):
        raise ValueError("Unexpected redirect. Refusing to forward release credentials or fetch another host")


def opener():
    return urllib.request.build_opener(NoRedirect())


def checked_base(value):
    url = urllib.parse.urlsplit(value)
    if url.scheme != "https" or not url.hostname or url.username or url.password or url.query or url.fragment:
        raise ValueError("Expected a plain HTTPS object URL")
    return value.rstrip("/")


def check_manifest(directory):
    if (directory / "RELEASE_INCOMPLETE").exists():
        raise ValueError("Incomplete release cannot be published")
    manifest = json.loads((directory / "manifest.json").read_text())
    version, build = manifest["version"], manifest["build"]
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) or type(build) is not int or build < 1:
        raise ValueError("Invalid release identity")
    if manifest["teamIdentifier"] != TEAM or manifest["bundleIdentifier"] != "be.spatie.daydreaming":
        raise ValueError("Incorrect release signing identity")
    if not re.fullmatch(r"[a-f0-9]{40}", manifest["gitRevision"]):
        raise ValueError("Invalid release revision")
    for name, digest in manifest["artifacts"].items():
        if Path(name).name != name or not re.fullmatch(r"[a-f0-9]{64}", digest):
            raise ValueError("Invalid artifact entry")
        if hashlib.sha256((directory / name).read_bytes()).hexdigest() != digest:
            raise ValueError(f"Changed release artifact: {name}")
    stem = f"Daydreaming-{version}-{build}"
    for name in (f"{stem}.dmg", f"{stem}.zip", "appcast.xml", "app-notarization.json", "dmg-notarization.json"):
        if name not in manifest["artifacts"]:
            raise ValueError(f"Missing verified artifact: {name}")
    for name in ("app-notarization.json", "dmg-notarization.json"):
        if json.loads((directory / name).read_text()).get("status") != "Accepted":
            raise ValueError("Apple has not accepted this release")
    validate(directory / "appcast.xml", directory / f"{stem}.dmg", version, build)
    return manifest


def verify_signatures(directory, manifest, work, key_file):
    tools = fetch(work / "Sparkle")
    signing = signing_arguments(key_file)
    app = work / "Daydreaming.app"
    stem = f'Daydreaming-{manifest["version"]}-{manifest["build"]}'
    subprocess.run(["ditto", "-x", "-k", str(directory / f"{stem}.zip"), str(work)], check=True)
    validate_app(app, manifest["version"], manifest["build"], manifest["gitRevision"])
    for suffix in ("dmg", "zip"):
        name = f"{stem}.{suffix}"
        subprocess.run([str(tools / "sign_update"), "--verify", *signing,
                        str(directory / name), manifest["archiveSignatures"][name]], check=True)
    subprocess.run([str(tools / "sign_update"), "--verify", *signing,
                    str(directory / "appcast.xml")], check=True)
    subprocess.run(["xcrun", "stapler", "validate", str(app)], check=True)
    subprocess.run(["spctl", "--assess", "--type", "execute", str(app)], check=True)
    dmg = directory / f"{stem}.dmg"
    subprocess.run(["codesign", "--verify", str(dmg)], check=True)
    signature = subprocess.run(["codesign", "--display", "--verbose=4", str(dmg)], check=True,
                               capture_output=True, text=True)
    if f"TeamIdentifier={TEAM}" not in signature.stderr:
        raise ValueError("Disk image is signed by the wrong team")
    subprocess.run(["xcrun", "stapler", "validate", str(dmg)], check=True)
    subprocess.run(["spctl", "--assess", "--type", "open", "--context", "context:primary-signature", str(dmg)], check=True)
    verify_dmg(app, dmg, work)


def remote_digest(url):
    request = urllib.request.Request(url, headers={"User-Agent": "DaydreamingRelease/1", "Cache-Control": "no-cache"})
    with opener().open(request, timeout=60) as response:
        size, digest = 0, hashlib.sha256()
        while chunk := response.read(1024 * 1024):
            size += len(chunk)
            if size > 1024 * 1024 * 1024:
                raise ValueError("Remote artifact is larger than 1 GiB")
            digest.update(chunk)
    return digest.hexdigest(), size


def api(path, content, content_type):
    request = urllib.request.Request(SITE + path, data=content, method="POST", headers={
        "Authorization": "Bearer " + os.environ["DAYDREAMING_RELEASE_TOKEN"],
        "Content-Type": content_type, "Accept": "application/json", "User-Agent": "DaydreamingRelease/1"})
    with opener().open(request, timeout=60) as response:
        if response.status not in (200, 201, 202, 204):
            raise ValueError("Website did not persist the release")
        response.read(64 * 1024)


def verify_canonical_redirect(filename, expected_url):
    class CanonicalRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, request, file, code, message, headers, target):
            if target != expected_url or request.get_method() != "HEAD":
                raise ValueError("Canonical download redirects to an unexpected object")
            return super().redirect_request(request, file, code, message, headers, target)
    request = urllib.request.Request(DOWNLOAD_PREFIX + filename, method="HEAD",
                                     headers={"User-Agent": "DaydreamingRelease/1"})
    with urllib.request.build_opener(CanonicalRedirect()).open(request, timeout=60) as response:
        if response.status != 200 or response.url != expected_url:
            raise ValueError("Canonical download is not available")


def upload(path, sha256, environment):
    filename = path.name
    prefix = environment["DAYDREAMING_S3_PREFIX"].strip("/")
    if not re.fullmatch(r"[A-Za-z0-9/_-]+", prefix) or ".." in prefix:
        raise ValueError("Invalid storage prefix")
    key = f"{prefix}/{filename}"
    base = checked_base(environment["DAYDREAMING_OBJECT_BASE_URL"])
    url = f"{base}/{filename}"
    common = ["--bucket", environment["DAYDREAMING_S3_BUCKET"], "--key", key,
              "--endpoint-url", checked_base(environment["DAYDREAMING_S3_ENDPOINT"]),
              "--region", environment["DAYDREAMING_S3_REGION"]]
    head = subprocess.run(["aws", "s3api", "head-object", *common], capture_output=True, text=True)
    if head.returncode:
        if not any(code in head.stderr for code in ("(404)", "(NoSuchKey)", "(NotFound)")):
            raise ValueError("Storage availability check failed. Not treating access errors as missing files")
        content_type = "application/x-apple-diskimage" if path.suffix == ".dmg" else "application/zip"
        subprocess.run(["aws", "s3api", "put-object", *common, "--body", str(path),
                        "--if-none-match", "*", "--content-type", content_type,
                        "--cache-control", "public, max-age=31536000, immutable"], check=True,
                       stdout=subprocess.DEVNULL)
    # An existing object is reusable only if its full bytes match, never overwritten.
    if remote_digest(url) != (sha256, path.stat().st_size):
        raise ValueError("Public object does not match the verified archive. Refusing to overwrite")
    return url


def publish(directory, key_file=None):
    manifest = check_manifest(directory)
    environment = os.environ.copy()
    environment["AWS_REQUEST_CHECKSUM_CALCULATION"] = "when_required"
    environment["AWS_RESPONSE_CHECKSUM_VALIDATION"] = "when_required"
    os.environ.update({name: environment[name] for name in ("AWS_REQUEST_CHECKSUM_CALCULATION", "AWS_RESPONSE_CHECKSUM_VALIDATION")})
    if remote_digest(FEED_URL)[0] != manifest["previousFeedSHA256"]:
        raise ValueError("Live feed changed since preparation. Refusing to replace another release")
    with tempfile.TemporaryDirectory(prefix="daydreaming-publish-") as folder:
        verify_signatures(directory, manifest, Path(folder), key_file)
    stem = f'Daydreaming-{manifest["version"]}-{manifest["build"]}'
    for suffix in ("dmg", "zip"):
        path = directory / f"{stem}.{suffix}"
        digest = manifest["artifacts"][path.name]
        url = upload(path, digest, environment)
        metadata = {"filename": path.name, "url": url, "sha256": digest, "size": path.stat().st_size,
                    "version": manifest["version"], "build": manifest["build"]}
        api("/api/releases/artifacts", json.dumps(metadata).encode(), "application/json")
        verify_canonical_redirect(path.name, url)
    api("/api/releases/appcast", (directory / "appcast.xml").read_bytes(), "application/xml")
    feed_sha = manifest["artifacts"]["appcast.xml"]
    if remote_digest(FEED_URL + "?verify=" + feed_sha)[0] != feed_sha:
        raise ValueError("Published feed bytes do not match the signed feed")
    print(f"Published {DOWNLOAD_PREFIX}{stem}.dmg and verified the signed live feed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--sparkle-key-file", type=Path)
    args = parser.parse_args()
    try:
        publish(args.directory.resolve(), args.sparkle_key_file)
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Release publication stopped: {error}", file=__import__("sys").stderr)
        raise SystemExit(1)
