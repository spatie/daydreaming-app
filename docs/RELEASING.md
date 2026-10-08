# Preparing a Daydreaming release

## Next release in a few commands

1. Finish review and the isolated Swift tests. Commit and push the intended sources to `main`.
2. Add `docs/releases/VERSION.md` with the real changes. Commit the new marketing version and a higher build number in `project.yml` and the generated project.
3. Run `gh workflow run release.yml --repo spatie/daydreaming-app --ref main -f version=VERSION`.
4. Follow the run with `gh run watch --repo spatie/daydreaming-app RUN_ID --exit-status`.
5. Verify `/download`, `/changelog`, and `/appcast.xml` on `https://getdaydreaming.com`. The download must match the release manifest's SHA256. Check a mounted DMG's stapled ticket before announcing the release.

The workflow creates notes, tags and release artifacts. Do not create the tag first. It publishes the signed feed last, after notarization and immutable download verification. An incomplete run must leave the existing feed intact.

### One-time credential setup

Store Apple signing and notarization credentials in 1Password and GitHub Actions secrets, never in Git, release notes or chat. The existing Spatie Team API key used for notarizing Bloom can also notarize Daydreaming. Its key ID and issuer ID must come from the same 1Password item as its `.p8` attachment. Do not substitute an unidentified `.p8` download. Developer ID signing uses team `97KRXCRMAY`.

For local releases, authenticate the CLI with `op signin` before looking up the approved item. An unlocked 1Password window alone does not authenticate the CLI. Complete the actual “Allow Bloom to get CLI access” Touch ID request. Download the attachment to an owner-only temporary directory, validate it with Apple, and save a named local `notarytool` Keychain profile. Delete the temporary key afterward. The first release uses the validated profile `daydreaming-release-20261007`; profile names are not credentials.

Daydreaming's Sparkle key is separate from Bloom's. Keep its private half in Keychain or the `DAYDREAMING_SPARKLE_PRIVATE_KEY` Actions secret. Only the public half belongs in the repository. A local release can sign through Keychain without exporting that private key.

Apple Weather requires the WeatherKit capability and app service on the `be.spatie.daydreaming` App ID in Certificates, Identifiers & Profiles. Create a Developer ID provisioning profile for that App ID after enabling both. The profile must authorize `com.apple.developer.weatherkit`. Download it for local builds and base64 encode the same profile in the `DAYDREAMING_WEATHERKIT_PROFILE` Actions secret. Regenerate the profile after changing the App ID's capabilities. No WeatherKit web API key is needed for this native app.

Download storage is the dedicated Laravel Cloud R2 release bucket, with a `releases` prefix, an EU endpoint and S3 region `auto`. Its tested conditional `PutObject` returns 412 when a filename already exists. Bucket credentials stay in Actions secrets. The website and workflow must use the identical `DAYDREAMING_OBJECT_BASE_URL`.

Before making source public, scan the entire Git history with `gitleaks git . --redact=100 --no-banner`. Also check tracked files for keys, exports, `.env` files and personal captures. Ignore rules protect new files; they do not remove secrets from history. If a real credential is found, rotate it and clean the history before publication. A clean scan is a check, not a substitute for reviewing what will become public.

## GitHub workflow

Run **Release Daydreaming** from the Actions tab on `main`, or use:

```sh
gh workflow run release.yml --repo spatie/daydreaming-app --ref main -f version=0.0.1
```

The workflow tests the app under an isolated preview identifier on macOS 26, validates the workflow, then preflights every release credential before building the production archive. Actions are pinned by commit. It uses the selected immutable workflow commit, stamps the requested version and Git commit count as the build number, and refuses existing version tags or non-increasing feed builds. Release concurrency is serialized. It creates the GitHub release and `vVERSION` tag after successful website publication.

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
| `DAYDREAMING_WEATHERKIT_PROFILE` | Base64 Developer ID provisioning profile for `be.spatie.daydreaming` with WeatherKit |
| `DAYDREAMING_S3_ACCESS_KEY_ID` | Access key scoped to the Daydreaming artifact bucket/prefix |
| `DAYDREAMING_S3_SECRET_ACCESS_KEY` | Secret for that object-storage key |
| `DAYDREAMING_RELEASE_TOKEN` | Website token scoped to the artifact/appcast publication API |

Configure repository variables `DAYDREAMING_S3_ENDPOINT` (HTTPS), `DAYDREAMING_S3_REGION`, `DAYDREAMING_S3_BUCKET`, `DAYDREAMING_S3_PREFIX` and `DAYDREAMING_OBJECT_BASE_URL`. The public object base URL includes the prefix and ends just before the filename. The bucket policy must allow public reads for release objects. Conditional `PutObject` with `If-None-Match: *` must be supported. An upload never replaces an existing object; an identical existing object is reused after full HTTP hash verification. Storage authorization failures are fatal, not treated as missing files.

Provision credentials through the owner's approved secret-management process. The workflow never exports keys from the owner's Mac or substitutes Bloom's signing key. CI creates a temporary keychain for the Developer ID certificate and notarization profile. The Sparkle seed is an owner-only temporary file to avoid interactive Keychain prompts from the official CLI tools. Its public half is checked against the committed app key before building. Certificate, key files and keychain are cleaned up on success, failure and cancellation. The setup script refuses to run outside GitHub Actions.

The current live feed is downloaded and cryptographically verified before building. The existing preparation pipeline notarizes and staples both app and DMG, and retains verified archives and the manifest as workflow artifacts. Publication repeats signature, Gatekeeper and staple checks. It uploads versioned DMG/ZIP files to external object storage, verifies public bytes, registers metadata through `POST /api/releases/artifacts`, and verifies canonical site redirects. Only then does it POST exact signed XML to `/api/releases/appcast`. Live feed hashes must match. If the live feed changed since preparation, publication stops instead of overwriting another release.

Public URLs remain `https://getdaydreaming.com/releases/Daydreaming-VERSION-BUILD.dmg` and `.zip`. The site redirects these to approved immutable external objects. `/download` and `/changelog` become active through the signed feed. There is no source-code publication in this workflow.

For interrupted publication, download the verified workflow artifact and resume `scripts/release/publish.py` with that unchanged directory and configured credentials. Never rebuild and overwrite the same published filename. If the feed was already promoted, verify live hashes first and finish the GitHub release using the manifest's source revision and the generated notes. A published version gets a new version and build for any correction.

Publication is blocked whenever these credentials or download storage are missing. A signed local design-preview DMG is not a notarized public release.

Sparkle is pinned to [2.10.0](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0). The feed is `https://getdaydreaming.com/appcast.xml`. Production Release builds use the feed when their committed public key is valid. Debug, preview identifiers, hosted tests and local channels never start an updater. Automatic checks run once a day by default, without a first-run permission question, like Bloom. Sparkle owns the saved Settings preference, so opting out remains respected. Automatic checks remain separate from wallpaper refreshes. When Sparkle finds a valid update, “App update available…” appears near the bottom of the menu bar menu, above the disabled status rows. It stays available after the update window closes. Clicking it opens Sparkle; downloading and installing still require the user's choice.

The unique signing account is `be.spatie.daydreaming.sparkle`. Its key was created specifically for Daydreaming. Never use Sparkle's default `ed25519` account or Bloom's signing key. The public key belongs in `DAYDREAMING_SPARKLE_PUBLIC_KEY` in `project.yml`. The private key stays in Keychain. Coordinate with the owner before creating, replacing or exporting a signing key.

## Prepare locally

First review and test the changes, commit the intended sources, package lockfile, release notes and current appcast, and ensure the tree is clean. Commits require their own authorization. Each release needs a strictly increasing integer build number. Commit the version and build settings as well so ordinary production builds retain that version.

Use an existing explicitly named `notarytool` Keychain profile. The release tool does not create profiles or accept passwords on command lines. An example invocation is:

```sh
python3 scripts/release/prepare.py \
  --version 0.0.1 --build 11 \
  --identity 'Developer ID Application: Spatie (97KRXCRMAY)' \
  --notary-profile daydreaming-release-20261007 \
  --weatherkit-profile /path/to/Daydreaming-WeatherKit.provisionprofile \
  --notes docs/releases/0.0.1.md \
  --output /tmp/daydreaming-release-0.0.1-11
```

This command builds and submits the archives to Apple's notarization service. It does not publish, upload website files, create tags, push, commit, install or launch the app. It refuses dirty trees and existing output directories, and builds an isolated archive of the exact Git commit. XcodeGen and Xcode command line tools must already be installed. Dependency resolution uses the committed package lockfile.

The pipeline archives and exports a universal Developer ID app, verifies the production identity, sandbox, expanded Sparkle Mach exceptions and nested signatures, notarizes and staples the app, and creates a ZIP and APFS DMG from that same stapled app. It signs, notarizes and staples the DMG. Sparkle tools come only from the exact official distribution, checked against its published SHA256 `c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c`.

The DMG uses the branded Retina artwork in `Design/DMG`, a curved drag arrow, the real Daydreaming app and an Applications shortcut. Finder layout is written directly by checksum-pinned dmgbuild, installed in an isolated temporary Python environment. No Finder automation or global Finder preference changes are needed. Edit the SVG and regenerate both PNG resolutions when changing the installer design.

The generated appcast advertises the signed DMG at `https://getdaydreaming.com/releases/`. DMG preserves Developer ID key rotation support when verification before extraction is enabled. Both DMG and ZIP EdDSA signatures are recorded and cryptographically verified. The tool preserves prior feed entries, disables delta generation, validates version, macOS minimum, archive URL and byte count, and verifies the signed XML. `manifest.json` records the source commit, source archive hash, Xcode version, tool checksum, archive signatures and artifact hashes.

A failed preparation retains `RELEASE_INCOMPLETE`. Never distribute such a directory. A completed staging directory contains the DMG, ZIP, signed appcast, notes, notarization results and manifest. Treat it as immutable. Publishing these artifacts requires separate owner authorization.

## Website handoff

The root `appcast.xml` records the published releases and is signed with Daydreaming's own key. The website must serve the published feed byte for byte as XML. `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction` are enabled, so an unsigned empty feed also fails verification.

Sparkle 2.10's `sign_update --account be.spatie.daydreaming.sparkle appcast.xml` embeds a `sparkle-signatures` XML comment at the end of the file. `generate_appcast` signs feeds automatically when the app requires it. Never pretty print, minify or parse and reserialize a signed feed. Any change needs re-signing. Validate locally with the official `sign_update --verify --account be.spatie.daydreaming.sparkle appcast.xml` tool. This only verifies the staged feed and never publishes it.

After separate publication authorization, hand the staged signed feed and archive bytes to the website workspace. Confirm the live HTTPS URLs return the identical hashes from the manifest. Do not replace or edit a previously published archive.

## Plain builds and checks

The postbuild script `scripts/sign-sparkle.sh` signs Sparkle's Installer and Downloader XPC services, Autoupdate executable, Updater app and framework inside out. Downloader entitlements are preserved. Xcode signs the outer app afterward. No signing step uses `--deep`. The normal archive and export workflow also signs nested code. The application already has network client permission, so the Downloader XPC service is not enabled.

Update installation waits for paid image work and freezes queue admission before handing installation to Sparkle. Root's AppModel and termination policy own that admission boundary. Verify this behavior with a fake image request, including installation without relaunch. Agent verification must not create a paid image.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/release/tests -v
bash -n scripts/sign-sparkle.sh
```

Run the Swift suite through the project's usual isolated test workflow. `UpdaterPolicyTests` cover the production configuration guard and prove that hosted tests never create or start an updater. Release tool tests cover feed mismatches, monotonically increasing builds, dirty source refusal, rejected notarization results and checksum failure before downloaded tools execute. Release safety tests use fixtures and never publish artifacts or trigger paid image generation.

Sources: [Sparkle sandbox integration](https://sparkle-project.org/documentation/sandboxing/), [publishing updates](https://sparkle-project.org/documentation/publishing/), [configuration](https://sparkle-project.org/documentation/customization/), [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## First published release

Version 0.0.1, build 11 was published on October 7, 2026 from source `66a008e4f912c39a49e1de0c00cb850ce87db954`. Both the app and DMG were notarized and stapled. The published DMG SHA256 is `6da52951737c6cba49fccc492df4ac6e00607bce238ae643168d03021d19251f`; the ZIP SHA256 is `0f9cc0fc19d9491d1911c824881602aa02f65449a43f01f86783c7354ff4acb7`. The signed feed SHA256 is `10f453bf2562bb416211f6c4d66c78b0b1d671acf9a466fb7a78723ca3a863b5`.

Storage and website publication credentials are configured in Actions. Apple signing/notarization and the dedicated Sparkle private seed must also be configured before dispatching the full CI workflow. The first release was prepared locally with the validated Keychain profile above. Never commit or upload a Keychain database or a 1Password export.

## Published release 0.0.2

Version 0.0.2, build 16 was published on October 7, 2026 from source `b27ad554a46b51f63a8c0d848187afed5367bb66`. Verification passed 389 app tests and 20 release tests. Both the universal app and DMG were notarized and stapled. The manifest SHA256 is `f040167564115d3e855c7956a5f98402042707a26b27172b1711c07f689316ad`.

- DMG SHA256: `3c121fce215a497e924b639ebf7ae1806baf6e46b9a23406b33d19d677496747`
- ZIP SHA256: `4acebdd91957d2fa34ddf5ef446cceb1280e2463460fa027b8f219d77cfeb33c`
- Signed feed SHA256: `9aaed9c387e488e00722da2f3ef8681ac66785e78fb1afd9077cdc7b773b4730`

The release used the existing local notarization profile and dedicated Sparkle Keychain account. Website publication ran the same checked-in publisher with a temporary bucket writer, revoked after publication. Public downloads matched the manifest and `/download` selected the new DMG. For a local release, publish the immutable prepared directory first, create the GitHub release against its recorded source revision, then copy the published signed feed verbatim into this repository. Keep the release tag on the built source, rather than the later feed bookkeeping commit.

## Published release 0.0.3

Version 0.0.3, build 17 was published on October 7, 2026 from source `7dffb629aad1d35c646da4dccb42170e6c3c18c9`. Verification passed 389 app tests and 20 release tests. Native fixture checks covered the fixed-location row, place search, picture location and dismissal without changing the selected place. The app and DMG were notarized and stapled.

- Manifest SHA256: `0fd1c276040a02d98960eee7d45e93962c07b242a7d8f7819e6c1923989ed029`
- DMG SHA256: `d14b3fe9314e4f6e3628f5e2eaeb2e46b43a1e173c021c236ae34b6b7292ba1a`
- ZIP SHA256: `23f3d23bf2cc58d04ab25d686a0c3d914d8059ce6968bfe8260af5c1410b0f36`
- Signed feed SHA256: `6783d271854ac12e180c8f9dc82f3f75fb61ee533ccabdd10cedf6ca9a57c19c`

Publication used the same local preparation and website publisher path as 0.0.2, with a newly created temporary bucket writer revoked afterward. Public archive hashes matched the immutable manifest.

## Published release 0.0.4

Version 0.0.4, build 18 was published on October 7, 2026 from source `5e9dfa987fa278d5529db08cb0b8e8f72c5147d7`. Verification passed 389 app tests and 20 release tests. The feature request form was verified in both an isolated native fixture and the installed production app. The app and DMG were notarized and stapled.

- Manifest SHA256: `b44e71d725409b37253b441ac37a68ce30a292ea644c0272bc3bd5146be7b49c`
- DMG SHA256: `a50ce2763f6c61330b64bc53c3947222c470ac32589801a7a3b19d8ca7670dc8`
- ZIP SHA256: `b9e1bb69be58a1ee7d085d325941e9563d02e6f958b8e2c94b80dffe20f8ff8a`
- Signed feed SHA256: `48c20c84f0d8fb92527d484ebd7c98e51fbc70fb2d944e55b69f6153c2c566b7`

Publication used the reviewed website publisher with a temporary bucket writer, revoked afterward. Public downloads matched the immutable manifest. The GitHub release tag points to the built source.

## Published release 0.0.5

Version 0.0.5, build 19 was published on October 7, 2026 from source `b927a7980718d6dd85faa42df565e1f74d976aa5`. Verification passed 389 app tests. The release tooling is unchanged from the 20 passing tests for 0.0.4. The app and DMG were notarized and stapled.

- Manifest SHA256: `c9c5b3608d0d514bbd5d71b854f0d43b308000f93f388ccec467bd1555f39a56`
- DMG SHA256: `4f429f66973ea8ecd01a72336b4e12e81369e23b2b64f9c835e16b68311e90cc`
- ZIP SHA256: `82c3d2a77d4abf8b5f8303a5d455fc3b1f23443d0f58e1f4efe59d50030031b7`
- Signed feed SHA256: `9b1de4edebbc2acb63350b9a5b1938bfd2d2f78dcde532dc8cf10954b25cd524`

Public downloads matched the immutable manifest. The temporary publication key was revoked. The installed app reports the expected source revision and preserves its designated requirement.

## Published release 0.0.6

Version 0.0.6, build 20 was published on October 7, 2026 from source `057108ab647f0932aa5395e6b2873c575dc4c160`. Verification passed 395 app tests and 20 release tests. Tests cover update availability after dismissal, clearing it when no valid update exists, and local picture-description caching. Native checks confirmed that mouse clicks open Crop in both an isolated fixture and the installed app. Automatic descriptions and the short idea examples were inspected natively. The universal app and DMG were notarized and stapled.

- Manifest SHA256: `f70540d72c768c4c94a685e7bf9c0ca3cdf4f4049477f1608c3195fa0adb8c28`
- DMG SHA256: `0951186e1c4f48408c45700cf67e976a8b5d1e62da8b1b7d615fc6625835d6d5`
- ZIP SHA256: `7ee974697ff2417d3da3d4fc8f307594b099d7bee4c01d24670c0b23407e2df3`
- Signed feed SHA256: `c9ace5527479dd82f07eb41f7cfddcb7078c979bfae5710d711dea24bdfeca83`

Public downloads matched the immutable manifest. The temporary publication key was revoked. The installed app reports the built source revision and preserves its designated requirement. Automatic downloading remains disabled.

## Published release 0.0.7

Version 0.0.7, build 21 was published on October 7, 2026 from source `15a9508871e5921971c143c5e030b750cf4201dc`. Verification passed 396 app tests locally and on the GitHub macOS 26 runner ([Checks run](https://github.com/spatie/daydreaming-app/actions/runs/37635302984)), plus 20 release-tool tests. The real local picture classifier is tested against the bundled image and a missing file. Release validation rejects the specific Swift Vision import reported missing on macOS 26.6.2. Both universal slices passed that guard. The compatible Objective-C request keeps this optional image analysis on the CPU.

Native isolated fixtures confirmed the website welcome title, removed credit captions, aligned navigation and shorter final-step text at minimum window size. A clean first launch of the previous binary worked on the owner's macOS 27, but did not reproduce the reported macOS 26 launch failure. The supplied crash report identified a DYLD missing-symbol failure before application startup. The corrected distributed binary has not been tested directly on Marceli's Mac.

- Manifest SHA256: `a57a71b0c5352cdd51c439ddabb35f240defb5e2ef5d4497cec4c93c5a2c0e36`
- DMG SHA256: `dbbff876e3f74aea4a5ecd87b31f951b79dbde46c9758505c4f03156a1c05034`
- ZIP SHA256: `842dfc0d2c6d456668cb696ab977d41cf3db7f15d5dc599acabcbbb1a78b3d35`
- Signed feed SHA256: `9cafd4257d7113210052a750e28f2e7a2393407af4bfacf2fc10b4a6a72a6c6e`

The universal app and DMG were notarized and stapled. Public downloads matched the immutable manifest. The temporary publication key was revoked. The installed app reports the built source revision and preserves its designated requirement. The GitHub tag points to the built source.
