# Contributing to Daydreaming

Thanks for helping improve Daydreaming. Small, focused changes are easiest to review. Please use English in code, documentation, issues and pull requests.

## Before you start

Check existing issues and open a proposal before a large feature or architecture change. For bugs, describe the app version, macOS version, reproduction steps and expected behavior. Screenshots help, but remove API keys, personal pictures and other private information first.

Do not post security vulnerabilities in a public issue. Follow [SECURITY.md](SECURITY.md).

## Local setup

You need macOS 26 or newer, Xcode with the macOS 26 SDK or newer, Xcode command line tools and XcodeGen. Clone the repository and run `xcodegen generate`. Edit `project.yml` before regenerating project settings; keep `Package.resolved` committed.

Run the isolated Swift and Python test commands in [README.md](README.md). Tests use fake providers and do not need image API or release credentials.

## Preview the interface without paid requests

Build an isolated Debug app:

```sh
xcodebuild build -project Daydreaming.xcodeproj -scheme Daydreaming \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .build/preview \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  PRODUCT_BUNDLE_IDENTIFIER=be.spatie.daydreaming.preview.dev CODE_SIGNING_ALLOWED=NO

./.build/preview/Build/Products/Debug/Daydreaming.app/Contents/MacOS/Daydreaming \
  -design-preview paused \
  -preview-image "$PWD/WeatherCanvas/Resources/YosemiteValley.jpg"
```

Use `welcome`, `paused`, `ready` or `busy` after `-design-preview` to inspect those states. Add `-preview-presentation crop` for cropping or `-preview-minimum` for the smallest window. Launch the executable directly with its arguments. Do not install this preview over your normal app or open it through Finder.

Preview identifiers disable production Keychain access, updates and installation reports. These fixtures do not generate real images. If you intentionally test a live provider, use your own key and a separately signed development bundle identifier. Never use Spatie's production identifier, credentials or someone's installed app as a test fixture.

## Changes we can review

- Prefer Swift 6 concurrency and native SwiftUI/AppKit controls. Keep blocking file and image work off the main actor.
- Keep provider-specific behavior in image drivers. Scheduling and views should not need to know how a provider submits an edit.
- Preserve one counted request per job, cancellation before submission, and the shared daily budget. Never add silent retries that can charge twice.
- Keep previews distinct from desktop wallpapers. A stale or old-recipe result must not replace the desktop.
- Treat dropping, framing, typing, browsing saved images and enabling wallpaper updates as separate user intentions.
- Check keyboard navigation, VoiceOver, minimum window size, light/dark appearance and reduced-motion/transparency settings when changing UI.
- Avoid unrelated rewrites and duplicate implementations. Add a meaningful regression test when changing behavior, especially paid-request or cache behavior.

## Pull requests

Explain the problem, resulting behavior and relevant validation in a few sentences. Attach screenshots for visible changes. Tell us which checks ran and whether live image creation was involved. Do not include keys, personal images, private machine logs or generated credentials.

Run `git diff --check` and the tests relevant to your change. The pull-request workflow runs isolated tests and a redacted secrets scan; it has no release credentials. Maintainers handle production signing, installation and publishing through the [release process](docs/RELEASING.md).

Be kind and specific in review. Discuss the change, give people room to learn and keep the conversation useful. Maintainers may close abusive or off-topic discussions.
