# Daydreaming

Daydreaming is a native SwiftUI and Swift 6 wallpaper app for macOS 26 or newer. Choose a picture, describe how it should change, and use your own OpenAI API key to reimagine it for the time and weather. Your original and its variations stay on this Mac. The repository remains private and unpublished.

## Start with a picture

Setup introduces the app, chooses a picture, saves an API key, and offers to start the first wallpaper. Local weather is used automatically, with location permission requested on the final Ready screen. The built-in Yosemite Valley photograph is credited to **NPS Photo / C. Jacoby**. See [its attribution](docs/yosemite-picture.md). The welcome illustrations are drawn locally.

The workspace follows the approved sidebar-and-preview prototype. Choose or drop a picture anywhere, write a short multiline **Your idea**, and explore the time slider. A newly chosen original appears immediately, then makes one small preview while the window is active. Your current desktop stays in place. New pictures pause automatic updates until you start them; **Resume Previous Wallpaper** restores the previously running picture and idea.

**Use This Picture & Idea as Wallpaper** is the decision to put this picture and idea to work. It creates or reuses a matching full-size result for the current hour, applies it, and enables automatic updates. It does not apply the small preview. A newly created wallpaper can differ from its preview. Reusing a matching saved result creates no API request. The confirmation remains available while a preview or wallpaper is being created. Reconfirming an already running picture and idea returns to the current time without creating another image. Pause and Resume stay in the app and menu bar menus.

The five-screen wizard also offers Not Now, which keeps automatic updates paused. Start Daydreaming enables launch at login, disclosed in setup and changeable in Settings. **Run Setup Again…** preserves your picture, instructions, API key, and saved variations while pausing updates and cancelling unpaid waiting work. Reopening setup does not create an image.

## The workspace

Previous pictures shows originals and their most recent recorded ideas. Generated variations stay cached, and choosing a previous picture reuses matching previews.

The main window has a standard titlebar, a single Previous pictures toolbar action, a sidebar with picture, idea, and wallpaper updates as steps 1 through 3, and a screen-shaped preview as step 4 with its time slider. The confirmation sits below the preview, outside the artwork. There is no More menu or separate time/weather heading. Crop is beside Preview, and Change is beside the original's name.

Without a picture, the sidebar offers a single chooser and drop hint, and the empty preview offers Yosemite Valley. The idea stays editable; Crop, the timeline, and Start appear after selection. An unchanged idea defaults to “Update my picture according to the current time and weather conditions.” Exact old defaults migrate, and custom ideas stay intact.

Pausing during an idea edit can create one small preview after about three seconds without committing the draft to automatic wallpapers. Clicking away commits the idea, and Escape restores the text from before editing. The compact multiline field scrolls. The first edit discloses preview cost. A missing hour requests a preview after about 0.8 seconds at rest in the active window; hours passed during a drag create nothing. A small hour bubble appears while dragging or focusing the slider. Browsing hours leaves the desktop unchanged. Scroll vertically over the artwork to browse saved variations of the selected original, newest first. Saved browsing is free, leaves queued work and your idea alone, and offers Back to Live. Changing the idea or time slider returns to live preview.

While the selected preview is being made, the artwork has a prismatic animated blur. The instructions, timeline, and status stay sharp. Ready images stay clear while unrelated work runs. Reduce Motion, Low Power Mode, inactivity, occlusion, or minimization switches the effect to a static state. There is no Compare control, desktop subtitle, or separate quality-upgrade action in the editor.

**Customize** contains style. Its styles are Natural, Subtle, Watercolor, and Cinematic. Weather always follows your location. Cancel keeps existing preferences; Done saves changes and requests one guarded preview. **Settings** contains launch at login, menu bar visibility, the API key, wallpaper quality, daily safety limit, and storage. **Wallpaper updates** is step 3 in the left sidebar and shows the last successful desktop update. Preview creation and failed applies do not advance that time. Its native picker offers every minute through once a month, plus a custom amount in minutes, hours, days, or weeks. New settings default to every hour; existing saved intervals are preserved. Monthly and weekly updates follow the local calendar. Relaunching preserves the saved next update, including overdue updates. Changing frequency creates no images and does not invalidate the cache. Matching paid images may be reused, and the daily safety limit still applies.

The preview header shows current local conditions from MET Norway, labelled Now independently of the previewed hour. Setup has no weather-selection step. The final Ready screen requests location access when needed; Not Now finishes without creating an image. The weather row uses the existing forecast cache and never creates an image or asks for location permission on its own. Its permission button is explicit.

## Pictures and framing

**Previous Pictures…** shows original pictures and their most recent recorded ideas. Choose This Picture restores the original, idea, and crop, reusing matching cached previews. Use This Picture & Idea as Wallpaper remains the separate desktop decision. Generated variations stay cached and can be browsed by scrolling over the selected picture's main preview. Choosing or browsing history does not apply a small variation to the desktop.

**Crop Picture** edits framing inside the same window. The crop stays at your display's aspect ratio, with no aspect choices or numeric fields. Drag the original picture beneath the fixed frame, use pinch or the zoom slider, and choose Reset, Cancel, or Done. The excluded area is dimmed, and guides appear while editing. Keyboard and VoiceOver actions move and resize the frame. The uncropped original is kept. Changed framing affects the image sent to OpenAI and its cache identity; cancelled framing changes nothing. Done with changed framing makes one guarded preview; unchanged Done and Cancel make none.

## Creation and cost

Creation runs one request at a time. Duplicate work is coalesced, and scheduled current-hour wallpapers take priority over waiting previews. Changed picture, framing, instructions, style, weather, or quality invalidates unpaid waiting work. A paid request can finish and be saved under its old settings, but cannot replace the desktop after those settings change.

The daily safety limit starts at 24 images and can be changed from 1 to 288 in Settings. Requests count when sent and belong to the local day they started. Timeouts or unreadable responses still count because they may be billed; an HTTP 4xx rejection returns the request to the allowance. Preview requests share this limit while preserving its final two requests for full wallpapers. With only two requests remaining, previews stop and a full wallpaper can still be created. Settings shows today's usage. There is no separate preview cap and no creation confirmation alert.

Previews use Flare, low quality, a 512-pixel source copy, and the smallest supported output near 0.66 megapixels. They have separate cache identities. The original and full-size upload are unchanged. A matching full-quality image takes precedence in the workspace. Low-resolution previews never reach the desktop. Use This Picture & Idea as Wallpaper requests the full-size render profile for the current hour and respects the image quality selected in Settings.

Cancel Creation stops preparation or an unpaid request. Once sent, cancellation removes waiting work while that request finishes. Cancellation does not pause automatic updates. Pause Automatic Updates is a separate action. A failed desktop application retries the already-created image without buying it again. Unsent waiting work can be restored after relaunch, but an interrupted request already sent to OpenAI is not replayed. Old desktop jobs and next-day quick previews are discarded.

Automatic updates run while Daydreaming is open and the Mac is awake. Resuming can create a wallpaper immediately. Daydreaming appears in the Dock while its main window or Settings is open, including when minimized. Closing those windows returns it to the menu bar. If you hide its menu bar icon, open it from Applications or Spotlight to return.

## Instructions and context

Mention an HTTPS link or drop a supported file into your instructions to include its text as context. Typed absolute or home-relative paths can require a file-selection permission panel during an active manual creation. Automatic updates skip files without a grant and show a warning. Quote paths containing spaces, such as `"~/Documents/Wallpaper ideas.md"`. Text, Markdown, HTML, and JSON files are supported.

Each new image reads up to three links or files in total, with HTTPS links taking available slots first. Downloads are bounded to 256 KB and extracted text to 2400 characters per source. HTML prefers main or article content and removes scripts and navigation; scripts are never run. Unreadable sources produce a warning while creation continues with the remaining instructions. Full local paths are replaced with file names before the instructions are sent to OpenAI. Referenced content refreshes cache recipes each local day.

Old time, date, and weather tokens remain compatible, but time and weather are included without typing tokens. Existing connected sources migrate to instruction references, without CSS selectors. Unresolved old file grants can be reconnected.

## Build and test

Requires macOS 26 or newer and Xcode with the macOS 26 SDK. Open `Daydreaming.xcodeproj` and use the `Daydreaming` scheme, or run:

```sh
xcodebuild -project Daydreaming.xcodeproj -scheme Daydreaming -destination 'platform=macOS' build
xcodebuild -project Daydreaming.xcodeproj -scheme Daydreaming -destination 'platform=macOS' test
```

The checked-in Xcode project is generated from `project.yml`. Run `xcodegen generate` after changing that file. Production installs use the Spatie Developer ID Application identity, Team `97KRXCRMAY`, and stable `be.spatie.daydreaming` bundle identifier. Agent builds use isolated preview identifiers, do not access production services, and must not be opened through Finder or LaunchServices. Unregister scratch bundles after verification. Installation policy is recorded in [AGENTS.md](AGENTS.md).

The default configuration keeps the existing file keychain with interactive password dialogs disabled. Data-protection keychain support is opt-in through `Configuration/DataProtection.xcconfig` and requires an authorized provisioning profile. Its migration tests use fake storage.

## Data and privacy

- Originals, variations, and the hourly cache stay in Daydreaming's sandbox container. Creation sends a prepared copy directly to [OpenAI's image edit API](https://developers.openai.com/api/reference/resources/images/methods/edit), using the person's API key. There is no bundled agent or account-login image backend.
- Requests include instructions, time, weather, and extracted text from referenced links or files. File access uses security-scoped bookmarks. HTTPS destinations and redirects are checked for public addresses, although URLSession does not pin DNS results and therefore cannot guarantee protection from every DNS-rebinding attack.
- Local weather sends coordinates rounded to two decimal places to [MET Norway](https://api.met.no/doc/TermsOfService). Its forecast data is used under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
- The API key stays in macOS Keychain. Daydreaming has no selling or activation service. Optional anonymous installation reports contain a random installation token, app version/build, macOS version, architecture and report time. They never include pictures, ideas, location or keys. Turn them off in Settings. Third-party attribution notices remain.

## Updates and release preparation

Sparkle checks the signed feed at `https://getdaydreaming.com/appcast.xml`. Check for Updates is available in the app menu and Settings. Preview and test builds disable updates and installation reports. Installing an update waits for image creation to finish, preserves waiting jobs and prevents another paid request before relaunch. Automatic installation is disabled.

See [RELEASING.md](docs/RELEASING.md) for the Developer ID signing, notarization, DMG/ZIP packaging and signed appcast command. It prepares verified artifacts without publishing them. The initial feed contains no releases.

See [design.md](docs/design.md) for interaction rules, review workflow, and the pending installed-app checklist. Source review and fixtures do not establish native appearance or successful live generation. No publication or open-source license change is authorized.

The main workspace uses small numbered accents in the app icon's orange, coral, magenta, and blue palette. Translucent landscape panes drift gently behind the controls, with a bounded damped response to moving the window. Motion pauses when the window is hidden, minimized, or inactive, under Reduce Motion or Low Power Mode. Reduce Transparency and Increase Contrast use a solid background. The foreground picture is never tinted by these effects. Previous Pictures uses an icon-only toolbar button with a text accessibility label and help.
