# Preparing a Daydreaming release

## GitHub workflow

Run **Release Daydreaming** from the Actions tab on `main`, or use:

```sh
gh workflow run release.yml --repo spatie/daydreaming-app --ref main -f version=0.1.0
```

The workflow tests the app under an isolated preview identifier on macOS 26, validates the workflow, then preflights every release credential before building the production archive. Actions are pinned by commit. It uses the selected immutable workflow commit, stamps the requested version and Git commit count as the build number, and refuses existing version tags or non-increasing feed builds. Release concurrency is serialized. It creates the private GitHub release and `vVERSION` tag after successful website publication. The native repository remains private.

Release notes come automatically from `docs/releases/VERSION.md` when that entry exists. Otherwise they list real non-merge commit subjects since the previous successful release. Empty changes fail instead of producing invented notes. The HTML renderer escapes source text, and generated notes remove private commit/PR URLs. The same notes appear in the GitHub release and signed feed. Edit a maintained version entry before dispatch for editorial control.

Configure these GitHub Actions secrets for this repository:

| Secret | Purpose |
| --- | --- |
| `APPLE_CERTIFICATE_P12` | Base64 Spatie Developer ID Application certificate with its private key |
| `APPLE_CERTIFICATE_PASSWORD` | Password for that certificate export |
| `APPLE_API_KEY_P8` | Base64 Apple App Store Connect Team API key for notarization |
| `APPLE_API_KEY_ID` | Apple API key ID |
| `APPLE_API_ISSUER_ID` | Apple team issuer ID |
| `DAYDREAMING_SPARKLE_PRIVATE_KEY` | Daydreaming's existing Sparkle 2.10 base64 private seed |
| `DAYDREAMING_S3_ACCESS_KEY_ID` | Access key scoped to the Daydreaming artifact bucket/prefix |
| `DAYDREAMING_S3_SECRET_ACCESS_KEY` | Secret for that object-storage key |
| `DAYDREAMING_RELEASE_TOKEN` | Website token scoped to the artifact/appcast publication API |

Configure repository variables `DAYDREAMING_S3_ENDPOINT` (HTTPS), `DAYDREAMING_S3_REGION`, `DAYDREAMING_S3_BUCKET`, `DAYDREAMING_S3_PREFIX` and `DAYDREAMING_OBJECT_BASE_URL`. The public object base URL includes the prefix and ends just before the filename. The bucket policy must allow public reads for release objects. Conditional `PutObject` with `If-None-Match: *` must be supported. An upload never replaces an existing object; an identical existing object is reused after full HTTP hash verification. Storage authorization failures are fatal, not treated as missing files.

Provision credentials through the owner's approved secret-management process. The workflow never exports keys from the owner's Mac or substitutes Bloom's signing key. CI creates a temporary keychain for the Developer ID certificate and notarization profile. The Sparkle seed is an owner-only temporary file to avoid interactive Keychain prompts from the official CLI tools. Its public half is checked against the committed app key before building. Certificate, key files and keychain are cleaned up on success, failure and cancellation. The setup script refuses to run outside GitHub Actions.

The current live feed is downloaded and cryptographically verified before building. The existing preparation pipeline notarizes and staples both app and DMG, and retains verified archives and the manifest as private workflow artifacts. Publication repeats signature, Gatekeeper and staple checks. It uploads versioned DMG/ZIP files to external object storage, verifies public bytes, registers metadata through `POST /api/releases/artifacts`, and verifies canonical site redirects. Only then does it POST exact signed XML to `/api/releases/appcast`. Live feed hashes must match. If the live feed changed since preparation, publication stops instead of overwriting another release.

Public URLs remain `https://getdaydreaming.com/releases/Daydreaming-VERSION-BUILD.dmg` and `.zip`. The site redirects these to approved immutable external objects. `/download` and `/changelog` become active through the signed feed. There is no source-code publication in this workflow.

For interrupted publication, download the verified workflow artifact and resume `scripts/release/publish.py` with that unchanged directory and configured credentials. Never rebuild and overwrite the same published filename. If the feed was already promoted, verify live hashes first and finish the private GitHub release using the manifest's source revision and the generated notes. A published version gets a new version and build for any correction.

The first public release remains blocked until these credentials and external object storage are actually configured. A signed local design-preview DMG is not a notarized public release.

Sparkle is pinned to [2.10.0](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0). The feed is `https://getdaydreaming.com/appcast.xml`. Production Release builds use the feed when their committed public key is valid. Debug, preview identifiers, hosted tests and local channels never start an updater. Automatic checks run once a day by default, without a first-run permission question, like Bloom. Sparkle owns the saved Settings preference, so opting out remains respected. Automatic checks remain separate from wallpaper refreshes.

The unique signing account is `be.spatie.daydreaming.sparkle`. Its key was created specifically for Daydreaming. Never use Sparkle's default `ed25519` account or Bloom's signing key. The public key belongs in `DAYDREAMING_SPARKLE_PUBLIC_KEY` in `project.yml`. The private key stays in Keychain. Coordinate with the owner before creating, replacing or exporting a signing key.

## Prepare locally

First review and test the changes, commit the intended sources, package lockfile, release notes and current appcast, and ensure the tree is clean. Commits require their own authorization. Each release needs a strictly increasing integer build number. Commit the version and build settings as well so ordinary production builds retain that version.

Use an existing explicitly named `notarytool` Keychain profile. The release tool does not create profiles or accept passwords on command lines. An example invocation is:

```sh
python3 scripts/release/prepare.py \
  --version 0.1.0 --build 5 \
  --identity 'Developer ID Application: Spatie (97KRXCRMAY)' \
  --notary-profile daydreaming-notary \
  --notes docs/releases/0.1.0.md \
  --output /tmp/daydreaming-release-0.1.0-5
```

This command builds and submits the archives to Apple's notarization service. It does not publish, upload website files, create tags, push, commit, install or launch the app. It refuses dirty trees and existing output directories, and builds an isolated archive of the exact Git commit. XcodeGen and Xcode command line tools must already be installed. Dependency resolution uses the committed package lockfile.

The pipeline archives and exports a universal Developer ID app, verifies the production identity, sandbox, expanded Sparkle Mach exceptions and nested signatures, notarizes and staples the app, and creates a ZIP and APFS DMG from that same stapled app. It signs, notarizes and staples the DMG. Sparkle tools come only from the exact official distribution, checked against its published SHA256 `c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c`.

The DMG uses the branded Retina artwork in `design/DMG`, a curved drag arrow, the real Daydreaming app and an Applications shortcut. Finder layout is written directly by checksum-pinned dmgbuild, installed in an isolated temporary Python environment. No Finder automation or global Finder preference changes are needed. Edit the SVG and regenerate both PNG resolutions when changing the installer design.

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
