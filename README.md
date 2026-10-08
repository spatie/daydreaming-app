<img src="Design/AppIcon/renders/daydreaming-default-128.png" alt="Daydreaming icon" width="96" height="96">

# Daydreaming

See your old wallpaper in a new light.

Daydreaming is a native macOS app that reimagines your picture for the current time and local weather, then updates your wallpaper on your chosen schedule. Built with Swift 6, SwiftUI and AppKit. Free, open source and postcardware.

[Download for macOS](https://getdaydreaming.com/download) · [Website](https://getdaydreaming.com) · [Changelog](https://getdaydreaming.com/changelog) · [Support](https://getdaydreaming.com/support)

## Get started

Requires **macOS 26 or later**. The signed, notarized download supports Apple silicon and Intel Macs.

1. Choose a picture or drop one onto the window. You can also try the built-in Yosemite Valley photo.
2. Describe your idea in a few sentences. Daydreaming includes the time and local weather automatically.
3. Explore the preview and crop your original inside the same window.
4. Choose **Use This Picture & Idea as Wallpaper** to start automatic updates.

Updates default to every hour. You can choose anything from every minute to once a month, pause updates, or update now from the menu bar. Previous Pictures restores your original and idea; saved variations are reused when their settings match.

## Image creation and privacy

Connect your own **OpenAI API key** in Settings. Daydreaming is free; OpenAI bills your account for new images. Typing an idea, choosing a picture or settling the time slider can automatically create a paid preview. The app shows this beside those controls.

Small previews stay in the window. Desktop wallpapers use the full-size rendering profile and your selected quality. A daily image limit bounds requests, and duplicate work is coalesced. Reusing a matching cached image makes no new API request.

Originals and generated variations stay on your Mac. Creation sends a prepared picture, your idea, time, weather and any explicitly included text context to the selected API. Your key stays in macOS Keychain. Local weather comes from [Apple Weather](https://developer.apple.com/weatherkit/), with [MET Norway](https://api.met.no/) as a fallback. Daydreaming needs no weather API key from you. Installation reports include your Mac’s computer name and app and system versions, but exclude pictures, ideas, location and keys. You can disable reports in Settings.

OpenAI is the supported image provider. The code uses a driver interface for future integrations. A Codex handoff is available for manual work, but it is not a connected image provider or an automatic wallpaper backend. See [image drivers](docs/IMAGE_DRIVERS.md) and the [privacy policy](https://getdaydreaming.com/privacy).

## Build and test

Install Xcode with the macOS 26 SDK or newer and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The checked-in project comes from `project.yml`.

```sh
git clone https://github.com/spatie/daydreaming-app.git
cd daydreaming-app
brew install xcodegen
xcodegen generate
xcodebuild test -project Daydreaming.xcodeproj -scheme Daydreaming \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .build/tests \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  PRODUCT_BUNDLE_IDENTIFIER=be.spatie.daydreaming.preview.tests CODE_SIGNING_ALLOWED=NO
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/release/tests -v
```

Tests use isolated identifiers and fake services. They do not read your production API key, create paid images or change your wallpaper. You do not need Spatie's signing credentials to run them.

See [CONTRIBUTING.md](CONTRIBUTING.md) for UI previews, development setup and pull requests.

## Contribute

Bug reports, focused pull requests and thoughtful interface improvements are welcome. Please open an issue before starting a large feature. Use English for issues, documentation and pull requests.

- [Report a bug](https://github.com/spatie/daydreaming-app/issues/new?template=bug_report.yml)
- [Suggest a feature](https://github.com/spatie/daydreaming-app/issues/new?template=feature_request.yml)
- [Report a security issue privately](https://github.com/spatie/daydreaming-app/security/advisories/new)

You can also ask for a feature from the app's Help menu or menu bar. Read [SECURITY.md](SECURITY.md) before sharing security-sensitive information.

## Architecture and releases

The app separates image drivers, request scheduling and budgeting, the local cache, and desktop application. UI changes must preserve cancellation, cache identity and the distinction between a preview and a desktop wallpaper.

- [Image driver contract](docs/IMAGE_DRIVERS.md)
- [Interaction and design notes](docs/design.md)
- [Release procedure](docs/RELEASING.md)
- [Third-party notices](WeatherCanvas/Resources/THIRD_PARTY_NOTICES.txt)

Releases are signed with Developer ID, notarized and stapled. Sparkle checks a signed feed. Signing keys, API credentials and storage secrets belong in Keychain, 1Password or GitHub Actions secrets, never in this repository.

## Postcardware

Made by [Spatie](https://spatie.be) in Antwerp. If you enjoy Daydreaming, we'd love a postcard. Open **Help > Send Us a Postcard…** for the address. It's optional; the app stays free.

## License

[MIT](LICENSE.md), like Bloom. Third-party code and the bundled National Park Service photograph retain their own notices.
