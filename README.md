# Daydreaming

Daydreaming is a native macOS 26+ app that turns an image you choose into a changing desktop wallpaper. It uses your own OpenAI API key to make new versions for the local time and weather. The first-run wizard asks for an image, an API key, and an update schedule. The default prompt is `Update my base image for the current time and weather`; you can replace it with any image-editing instruction.

Daydreaming runs as a menu bar app without a Dock icon. You can hide its menu bar icon in Settings and reopen its window by opening the app again. Automatic updates require the app to be running. Launch at login is optional. The window and menu show when Daydreaming is checking weather, reading connected sources, generating, applying a saved image, or waiting after an error.

## Use

1. Open Daydreaming and complete the three-step wizard.
2. Allow location access for automatic weather, or choose a fixed weather condition in Settings.
3. Adjust the prompt and schedule in the main window. The optional `{{time}}`, `{{date}}`, and `{{weather}}` tokens are replaced when an image is generated. Local time and weather are included even if you use no tokens.
4. Use Settings to change image quality, manage the local cache, activate a Pro license, or connect text sources. A selected text, HTML, or JSON file, or an element from an HTTPS page selected with a CSS selector, is previewed before it is added. Sources are read again before each new image. Website scripts are not run.

The free tier allows at most two new images per local day, with schedules of once or twice daily. An offline Pro license unlocks the other intervals, including custom intervals from 5 minutes to 24 hours. Cached images can be reused without another OpenAI call or using the daily generation allowance. **Generate now** requests a fresh image and counts toward that allowance. Pro licenses are currently issued manually; there is no checkout or license server. See [licensing.md](docs/licensing.md).

## Build and test

Requires macOS 26 or newer and Xcode with the macOS 26 SDK. Open `Daydreaming.xcodeproj` and run the `Daydreaming` scheme, or build from the repository root:

```sh
xcodebuild -project Daydreaming.xcodeproj -scheme Daydreaming -destination 'platform=macOS' build
xcodebuild -project Daydreaming.xcodeproj -scheme Daydreaming -destination 'platform=macOS' test
```

The checked-in Xcode project is generated from `project.yml`. If you change that file, run `xcodegen generate` before building. Configure signing for your own Mac when testing the installed, sandboxed app.

## Data and privacy

- Daydreaming copies the chosen original into `~/Library/Application Support/Daydreaming`. Generated wallpapers and matching-image cache entries stay there too. It sends a JPEG copy, reduced to at most 2560 pixels on its longest edge, directly to [OpenAI's image edit API](https://developers.openai.com/api/reference/resources/images/methods/edit) when it needs a new image.
- The rendered prompt sent to OpenAI includes the local time and weather. If you connect a file or web page, its extracted text is included in that prompt. Files are accessed only after you select them; the app stores a security-scoped bookmark for later reads. HTTPS pages are fetched directly from their host. Each source is limited to 256 KB and 2400 characters of prompt text, with at most five sources.
- Automatic weather sends coordinates rounded to two decimal places to [MET Norway](https://api.met.no/doc/TermsOfService). The forecast is cached according to the response expiry. MET Norway forecast data is used under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
- The OpenAI API key and any activated license are stored in macOS Keychain. Daydreaming has no account, analytics service, or license validation request.

The app builds and has automated tests. A live OpenAI image edit using a user's key remains unverified. Installed-app behavior for sandboxed file bookmarks and launch at login also remains unverified, so test those flows in a signed installed build before distribution.
