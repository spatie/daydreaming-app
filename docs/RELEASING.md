# Preparing a Daydreaming release

Sparkle is pinned to [2.10.0](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0). The feed is `https://getdaydreaming.com/appcast.xml`. Production Release builds use the feed when their committed public key is valid. Debug, preview identifiers, hosted tests and local channels never start an updater. Automatic checks remain separate from wallpaper refreshes.

The unique signing account is `be.spatie.daydreaming.sparkle`. Its key was created specifically for Daydreaming. Never use Sparkle's default `ed25519` account or Bloom's signing key. The public key belongs in `DAYDREAMING_SPARKLE_PUBLIC_KEY` in `project.yml`. The private key stays in Keychain. Coordinate with the owner before creating, replacing or exporting a signing key.

## Prepare locally

First review and test the changes, commit the intended sources, package lockfile, release notes and current appcast, and ensure the tree is clean. Commits require their own authorization. Each release needs a strictly increasing integer build number. Commit the version and build settings as well so ordinary production builds retain that version.

Use an existing explicitly named `notarytool` Keychain profile. The release tool does not create profiles or accept passwords on command lines. An example invocation is:

```sh
python3 scripts/release/prepare.py \
  --version 0.1.0 --build 3 \
  --identity 'Developer ID Application: Spatie (97KRXCRMAY)' \
  --notary-profile daydreaming-notary \
  --notes docs/releases/0.1.0.md \
  --output /tmp/daydreaming-release-0.1.0-3
```

This command builds and submits the archives to Apple's notarization service. It does not publish, upload website files, create tags, push, commit, install or launch the app. It refuses dirty trees and existing output directories, and builds an isolated archive of the exact Git commit. XcodeGen and Xcode command line tools must already be installed. Dependency resolution uses the committed package lockfile.

The pipeline archives and exports a universal Developer ID app, verifies the production identity, sandbox, expanded Sparkle Mach exceptions and nested signatures, notarizes and staples the app, and creates a ZIP and APFS DMG from that same stapled app. It signs, notarizes and staples the DMG. Sparkle tools come only from the exact official distribution, checked against its published SHA256 `c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c`.

The generated appcast advertises the signed DMG at `https://getdaydreaming.com/releases/`. DMG preserves Developer ID key rotation support when verification before extraction is enabled. Both DMG and ZIP EdDSA signatures are recorded and cryptographically verified. The tool preserves prior feed entries, disables delta generation, validates version, macOS minimum, archive URL and byte count, and verifies the signed XML. `manifest.json` records the source commit, source archive hash, Xcode version, tool checksum, archive signatures and artifact hashes.

A failed preparation retains `RELEASE_INCOMPLETE`. Never distribute such a directory. A completed staging directory contains the DMG, ZIP, signed appcast, notes, notarization results and manifest. Treat it as immutable. Publishing these artifacts requires separate owner authorization.

## Website handoff

The empty root `appcast.xml` is signed with Daydreaming's own key and contains no releases. The website must serve it byte for byte as XML. `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction` are enabled, so an unsigned empty feed also fails verification.

Sparkle 2.10's `sign_update --account be.spatie.daydreaming.sparkle appcast.xml` embeds a `sparkle-signatures` XML comment at the end of the file. `generate_appcast` signs feeds automatically when the app requires it. Never pretty print, minify or parse and reserialize a signed feed. Any change needs re-signing. Validate locally with the official `sign_update --verify --account be.spatie.daydreaming.sparkle appcast.xml` tool. This only verifies the staged feed and never publishes it.

After separate publication authorization, hand the staged signed feed and archive bytes to the website workspace. Confirm the live HTTPS URLs return the identical hashes from the manifest. Do not replace or edit a previously published archive.

## Plain builds and checks

The postbuild script `scripts/sign-sparkle.sh` signs Sparkle's Installer and Downloader XPC services, Autoupdate executable, Updater app and framework inside out. Downloader entitlements are preserved. Xcode signs the outer app afterward. No signing step uses `--deep`. The normal archive and export workflow also signs nested code. The application already has network client permission, so the Downloader XPC service is not enabled.

Update installation waits for paid image work and freezes queue admission before handing installation to Sparkle. Root's AppModel and termination policy own that admission boundary. Verify this behavior with a fake image request, including installation without relaunch. Agent verification must not create a paid image.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/release/tests -v
bash -n scripts/sign-sparkle.sh
```

Run the Swift suite through the project's usual isolated test workflow. `UpdaterPolicyTests` cover the production configuration guard and prove that hosted tests never create or start an updater. Release tool tests cover feed mismatches, monotonically increasing builds, dirty source refusal, rejected notarization results and checksum failure before downloaded tools execute. No release pipeline or live update was executed as part of agent preparation.

Sources: [Sparkle sandbox integration](https://sparkle-project.org/documentation/sandboxing/), [publishing updates](https://sparkle-project.org/documentation/publishing/), [configuration](https://sparkle-project.org/documentation/customization/), [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
