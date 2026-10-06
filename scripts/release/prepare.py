#!/usr/bin/env python3
"""Prepare signed, notarized Daydreaming release artifacts. Never publish or install."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from feed import FEED_URL, DOWNLOAD_PREFIX, require_next_build, validate
from sparkle_tools import ACCOUNT, VERSION, SHA256, fetch
from dmg import build as build_dmg

BUNDLE_ID = "be.spatie.daydreaming"
TEAM = "97KRXCRMAY"


def run(*args, cwd=None, capture=False):
    result = subprocess.run([str(arg) for arg in args], cwd=cwd, check=True,
                            stdout=subprocess.PIPE if capture else None, text=capture)
    return result.stdout.strip() if capture else None


def clean_revision(repo: Path) -> str:
    if run("git", "status", "--porcelain", "--untracked-files=all", cwd=repo, capture=True):
        raise ValueError("Release requires a clean committed tree, including untracked files")
    revision = run("git", "rev-parse", "--verify", "HEAD^{commit}", cwd=repo, capture=True)
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Expected an immutable Git commit")
    return revision


def verify_signature(path: Path):
    run("codesign", "--verify", "--deep", "--strict", path)
    result = subprocess.run(["codesign", "--display", "--verbose=4", str(path)], check=True,
                            capture_output=True, text=True)
    if f"TeamIdentifier={TEAM}" not in result.stderr or "runtime" not in result.stderr:
        raise ValueError(f"Incorrect Developer ID team or missing hardened runtime: {path.name}")


def validate_app(app: Path, version: str, build: int, revision: str) -> str:
    with (app / "Contents/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    expected = {"CFBundleIdentifier": BUNDLE_ID, "CFBundleShortVersionString": version,
                "CFBundleVersion": str(build), "DaydreamingBuildChannel": "release",
                "DaydreamingSourceRevision": revision, "SUFeedURL": FEED_URL,
                "SUEnableInstallerLauncherService": True, "SUVerifyUpdateBeforeExtraction": True,
                "SURequireSignedFeed": True, "LSMinimumSystemVersion": "26.0"}
    for key, value in expected.items():
        if info.get(key) != value:
            raise ValueError(f"Release app configuration mismatch: {key}")
    key = info.get("SUPublicEDKey", "")
    if len(base64.b64decode(key, validate=True)) != 32:
        raise ValueError("Release requires the committed Daydreaming public signing key")
    framework = app / "Contents/Frameworks/Sparkle.framework"
    with (framework / "Resources/Info.plist").open("rb") as file:
        if plistlib.load(file).get("CFBundleShortVersionString") != VERSION:
            raise ValueError("Embedded Sparkle version mismatch")
    for child in ("Versions/B/XPCServices/Installer.xpc", "Versions/B/XPCServices/Downloader.xpc",
                  "Versions/B/Autoupdate", "Versions/B/Updater.app", "",):
        verify_signature(framework / child)
    verify_signature(app)
    architectures = run("lipo", "-archs", app / "Contents/MacOS/Daydreaming", capture=True).split()
    if set(architectures) != {"arm64", "x86_64"}:
        raise ValueError("Release app must contain both Apple silicon and Intel architectures")
    result = subprocess.run(["codesign", "--display", "--entitlements", ":-", str(app)],
                            check=True, capture_output=True)
    entitlements = plistlib.loads(result.stdout)
    expected_names = [BUNDLE_ID + "-spks", BUNDLE_ID + "-spki"]
    if entitlements.get("com.apple.security.temporary-exception.mach-lookup.global-name") != expected_names:
        raise ValueError("Sparkle Mach service exceptions were not expanded for production")
    if entitlements.get("com.apple.security.app-sandbox") is not True:
        raise ValueError("App sandbox must remain enabled")
    if entitlements.get("com.apple.security.get-task-allow"):
        raise ValueError("Distribution app may not allow debugger access")
    return key


def notarize(path: Path, profile: str, log: Path):
    output = run("xcrun", "notarytool", "submit", path, "--keychain-profile", profile,
                 "--wait", "--output-format", "json", capture=True)
    log.write_text(output + "\n")
    if json.loads(output).get("status") != "Accepted":
        raise ValueError(f"Notarization was not accepted. See {log.name}")


def prepare(args):
    repo = Path(__file__).resolve().parents[2]
    revision = clean_revision(repo)
    require_next_build(repo / "appcast.xml", args.build)
    output = args.output.resolve()
    if output.exists():
        raise ValueError("Output directory already exists. Existing releases are immutable")
    if output == repo or repo in output.parents:
        raise ValueError("Output must be outside the source tree")
    notes = args.notes.resolve()
    relative_notes = notes.relative_to(repo)
    if not notes.is_file():
        raise ValueError("Release notes must be a committed file")
    run("git", "ls-files", "--error-unmatch", str(relative_notes), cwd=repo, capture=True)
    output.mkdir(parents=True)
    marker = output / "RELEASE_INCOMPLETE"
    marker.write_text("Do not distribute this directory until preparation succeeds.\n")
    with tempfile.TemporaryDirectory(prefix="daydreaming-release-") as work_name:
        work = Path(work_name)
        source = work / "source"
        source.mkdir()
        archive_source = work / "source.tar"
        with archive_source.open("wb") as target:
            subprocess.run(["git", "archive", "--format=tar", revision], cwd=repo, stdout=target, check=True)
        source_hash = hashlib.sha256(archive_source.read_bytes()).hexdigest()
        run("tar", "-xf", archive_source, "-C", source)
        resolved = source / "Daydreaming.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        if not resolved.is_file():
            raise ValueError("Commit the resolved Swift package lockfile before preparing a release")
        require_next_build(source / "appcast.xml", args.build)
        run("xcodegen", "generate", cwd=source)
        archive = work / "Daydreaming.xcarchive"
        run("xcodebuild", "-project", "Daydreaming.xcodeproj", "-scheme", "Daydreaming", "-configuration", "Release",
            "-archivePath", archive, "-derivedDataPath", work / "DerivedData",
            "-destination", "generic/platform=macOS", "ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO", "-disableAutomaticPackageResolution",
            "-onlyUsePackageVersionsFromResolvedFile", "archive", "DAYDREAMING_BUILD_CHANNEL=release",
            f"DAYDREAMING_SOURCE_REVISION={revision}", f"MARKETING_VERSION={args.version}",
            f"CURRENT_PROJECT_VERSION={args.build}", f"CODE_SIGN_IDENTITY={args.identity}", cwd=source)
        export_options = work / "ExportOptions.plist"
        export_options.write_bytes(plistlib.dumps({"method": "developer-id", "teamID": TEAM,
                                                  "signingStyle": "manual", "signingCertificate": args.identity}))
        exported = work / "export"
        run("xcodebuild", "-exportArchive", "-archivePath", archive, "-exportPath", exported,
            "-exportOptionsPlist", export_options)
        app = exported / "Daydreaming.app"
        public_key = validate_app(app, args.version, args.build, revision)
        tools = fetch(work / "Sparkle")
        if run(tools / "generate_keys", "--account", ACCOUNT, "-p", capture=True) != public_key:
            raise ValueError("Daydreaming Keychain signing account does not match the committed public key")
        submission = work / "notarization.zip"
        run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, submission)
        notarize(submission, args.notary_profile, output / "app-notarization.json")
        run("xcrun", "stapler", "staple", app)
        run("xcrun", "stapler", "validate", app)
        run("spctl", "--assess", "--type", "execute", "--verbose=2", app)
        validate_app(app, args.version, args.build, revision)
        zip_file = output / f"Daydreaming-{args.version}-{args.build}.zip"
        run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, zip_file)
        dmg_file = output / f"Daydreaming-{args.version}-{args.build}.dmg"
        build_dmg(app, dmg_file, source, work)
        run("codesign", "--force", "--sign", args.identity, "--timestamp", dmg_file)
        run("codesign", "--verify", dmg_file)
        notarize(dmg_file, args.notary_profile, output / "dmg-notarization.json")
        run("xcrun", "stapler", "staple", dmg_file)
        run("xcrun", "stapler", "validate", dmg_file)
        run("spctl", "--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=2", dmg_file)
        feed_dir = work / "feed"
        feed_dir.mkdir()
        shutil.copy2(dmg_file, feed_dir / dmg_file.name)
        shutil.copy2(source / "appcast.xml", feed_dir / "appcast.xml")
        shutil.copy2(source / relative_notes, feed_dir / (dmg_file.stem + notes.suffix))
        run(tools / "generate_appcast", "--account", ACCOUNT, "--download-url-prefix", DOWNLOAD_PREFIX,
            "--embed-release-notes", "--maximum-versions", "0", "--maximum-deltas", "0", "--versions", str(args.build), feed_dir)
        feed = feed_dir / "appcast.xml"
        signature = validate(feed, dmg_file, args.version, args.build)
        run(tools / "sign_update", "--verify", "--account", ACCOUNT, dmg_file, signature)
        run(tools / "sign_update", "--verify", "--account", ACCOUNT, feed)
        zip_signature_output = run(tools / "sign_update", "--account", ACCOUNT, zip_file, capture=True)
        match = re.search(r'sparkle:edSignature="([A-Za-z0-9+/=]+)" length="([0-9]+)"', zip_signature_output)
        if not match or int(match.group(2)) != zip_file.stat().st_size:
            raise ValueError("Official tool did not return a valid ZIP signature and length")
        zip_signature = match.group(1)
        run(tools / "sign_update", "--verify", "--account", ACCOUNT, zip_file, zip_signature)
        # Copy the signed bytes verbatim. Modifying the feed after signing invalidates it.
        shutil.copy2(feed, output / "appcast.xml")
        for file in feed_dir.iterdir():
            if file.suffix in (".md", ".html", ".txt"):
                shutil.copy2(file, output / file.name)
        checksums = {file.name: hashlib.sha256(file.read_bytes()).hexdigest()
                     for file in output.iterdir() if file.is_file() and file != marker}
        manifest = {"gitRevision": revision, "sourceArchiveSHA256": source_hash, "version": args.version,
                    "build": args.build, "bundleIdentifier": BUNDLE_ID, "teamIdentifier": TEAM,
                    "sparkleVersion": VERSION, "sparkleDistributionSHA256": SHA256, "feedURL": FEED_URL,
                    "publicKey": public_key, "archiveSignatures": {dmg_file.name: signature, zip_file.name: zip_signature},
                    "artifacts": checksums,
                    "xcode": run("xcodebuild", "-version", capture=True), "published": False}
        (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        marker.unlink()
    print(f"Verified release prepared at {output}. Nothing was published or installed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True, type=int)
    parser.add_argument("--identity", required=True, help="Explicit Daydreaming Developer ID Application identity")
    parser.add_argument("--notary-profile", required=True, help="Explicit existing notarytool Keychain profile")
    parser.add_argument("--notes", required=True, type=Path, help="Committed .md, .html or .txt release notes")
    parser.add_argument("--output", required=True, type=Path, help="New staging directory outside this repository")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version) or args.build < 1:
        parser.error("Use a numeric major.minor.patch version and positive integer build")
    if not args.identity.startswith("Developer ID Application:") or args.notes.suffix not in (".md", ".html", ".txt"):
        parser.error("Developer ID Application identity and supported release note extension required")
    try:
        prepare(args)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Release preparation stopped: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
