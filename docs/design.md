# Daydreaming design

Daydreaming turns a chosen picture and a short set of instructions into an automatically changing wallpaper. The workspace decision is **Start Daydreaming**. Browsing an hour, editing instructions, and picking a different original are preparation for that decision, not alternative ways to apply a low-resolution image.

The workspace uses a normal Mac title bar and unified toolbar, a picture-and-idea sidebar, a screen-shaped preview, and a fixed bottom decision bar. Window size is independent of the source picture, defaulting to 1000 by 720 with screen-bounded minimums. The system owns window dragging. Native tabbing is disabled. The canvas previews the centered desktop fill for the window's display; a soft backdrop fills the outside area. Other displays use the same explicit fill behavior at their own aspect ratios.

## Workspace

The owner approved the HTML prototype in Design/Prototype/simple-workspace. Native layout follows it: a picture-and-idea sidebar, a preview and time slider, and one fixed bottom decision bar. The toolbar contains Previous pictures only. App-level settings, Customize, Pause/Resume, Update Now and Quit remain in the app menus and menu bar extra.

Your idea is a short, scrolling multiline field with a help affordance. Its default is “Update my picture according to the current time and weather conditions.” Custom text is preserved. Empty workspaces offer one chooser/drop hint and a quiet Yosemite option. There are no empty Crop, timeline or Start controls.

A picture choice appears immediately and automatically prepares one counted preview. It does not apply to the desktop. Existing automatic updates pause when the candidate replaces the workspace recipe; the previous wallpaper can be resumed from the menus. Changing the idea or settling the slider automatically previews under the active-window and shared-budget gates. Start Daydreaming creates a full-size current-hour image and begins automatic updating. Running is quiet, with its next change and Pause; edits show Use These Changes. There is no More menu, Compare, Save button or separate quality-upgrade action.

Crop keeps the sidebar and preview workspace intact. The original moves under a fixed display-shaped mask, with pan, pinch, wheel and zoom buttons/slider. The sidebar dims, and the bottom decision becomes Reset, Cancel and Done. Changed Done makes one preview; unchanged Done and Cancel make none. Both preview and gallery use the desktop's proportional-fill geometry at every window size. Ready pictures render without a waiting veil.

Vertical scrolling over the artwork browses the selected original's saved variations, newest first, without generating, applying, changing settings or cancelling queued work. Momentum is ignored and trackpad steps are rate-limited. A Saved caption identifies the hour, day and position, and Back to Live or Escape exits. The slider and idea editor also exit saved browsing. VoiceOver adjustable actions and focused-picture arrow keys browse the same saved set.

The weather row says Now for the local MET Norway forecast, independently of the previewed hour. Display refreshes use the existing cache at most once per 15 minutes while active, without paid work. Missing weather offers an explicit location-access action.

## Setup and preferences

Setup has four screens: welcome, picture, image creation, and ready. Welcome shows locally drawn variations of the bundled photograph. Yosemite Valley is preselected and credited to NPS Photo / C. Jacoby, with provenance in [yosemite-picture.md](yosemite-picture.md).

Saving a key does not validate it through a network request. Ready explains approximate-location sharing with MET Norway and requests native location permission when needed. Denied access offers System Settings. Weather is always local. Not Now finishes setup with updates paused and makes no image, including when location access is unavailable.

Run Setup Again… preserves the source, instructions, API key, and saved pictures. It pauses updates, withdraws unpaid waiting work, and returns to Welcome. Reopening setup creates nothing. It is unavailable during creation.

Customize contains style. Weather always uses the local forecast, and the schedule stays in step 3. Cancel preserves existing settings. Done saves them and requests one guarded quick preview. Its visible privacy footnote explains that links and files in instructions are read and sent to OpenAI. Settings contains only app-level preferences: launch at login, menu bar visibility, API key, quality, daily limit, and storage. Selling, license, activation, and feature-tier code is removed. The repository remains private; third-party notices remain, and no open-source license or publication is authorized.

## Queue, payment, and application

The app calls the OpenAI Images API directly. There is no bundled agent or account-login provider. Each job captures its source, crop, instructions, style, hour, weather, model, and render quality. The queue is serial, coalesces duplicates, and gives scheduled current-hour wallpapers priority over waiting previews without interrupting a paid job.

Requests count once when sent, against their starting local day. Timeouts and unreadable results remain counted; an HTTP 4xx rejection releases the reservation. Cached reuse spends no credit. Preview and full-quality identities are separate, and previews are never applied to the desktop. Matching full-quality images take precedence in the workspace. Start Daydreaming requests the full-size current-hour render at the quality selected in Settings and starts automatic updates for the chosen source and idea.

The daily safety limit defaults to 24 and ranges from 1 to 288. Quick previews share the limit while preserving its final two slots for full wallpapers. There is no separate preview cap. A limit of two or less leaves no automatic preview allowance. Settings shows today's usage, and exhausted states link to the limit setting. There is no creation confirmation alert.

Changes to source, crop, instructions, style, weather, or quality invalidate waiting work. An old paid request can finish and be saved, but its result cannot replace a newly chosen desktop or changed recipe. Only matching current-hour full-quality work can update the desktop.

Cancellation does not pause the schedule. Before payment it stops preparation or the active request. After payment it removes waiting work and lets the already-submitted image finish. Cancelling an unpaid automatic job skips that slot. Pause Automatic Updates is a separate decision. A failed desktop application retries the saved file without re-creating it.

Persisted waiting work returns through the same stale-job and dedupe rules. Old desktop jobs are dropped, quick previews do not carry into a new day, and already-submitted interrupted requests are never replayed automatically. Automatic updates run while the app is open and the Mac is awake. Morning and evening uses 7 am and 7 pm local time; once daily uses 7 am. Resuming can create a wallpaper immediately.

## Sources and privacy

Instructions can contain HTTPS links or supported file paths. Dropping a file adds its path and a security-scoped bookmark. Typed paths without grants may request permission during active manual work. Automatic jobs skip ungranted files without showing a panel. Links and files share a maximum of three references per creation, with links taking available slots first. Each download is bounded to 256 KB and extracted text to 2400 characters.

HTML extraction strips scripts and navigation and prefers main or article content. Scripts are not executed. Source failures warn without blocking the remaining instructions. Local paths are redacted to file names before submission. Daily source-backed cache identities avoid indefinitely reusing old linked content. Legacy selectors are discarded; unresolved grants remain reconnectable.

HTTPS destinations and redirects are checked for public addresses. URLSession does not pin the checked DNS result, so this is not a complete DNS-rebinding guarantee. API credentials remain in Keychain. Production installs preserve the Spatie Developer ID identity and bundle identifier. Preview and hosted test builds must not query the person's key, change desktop wallpaper, register login items, or start paid generation.

Discontinued isolated account-provider state has a one-time cleanup path. It addresses only the two exact old container-namespace keychain entries and that container's old provider folder, without reading credentials, calling a network service, or opening authentication UI. It does not touch a personal CLI home, the API key, originals, or saved variations.

## Review and verification

The owner requests repeated independent usability and payment review. The Bloom reviewer is **Review daydreaming app**, ID `0e03f7ca-1ec4-4d81-913c-22a5cb3e4e4b`. Send the live source path, concrete changes, verification logs, and honest screenshot provenance. Ask for actionable findings, implement them, and request another review. Keep the reviewer read-only until the coordinated install handoff.

The website workspace is **Understand Daydreaming website**, ID `334101e3-e85d-4b5d-8249-7bfba4cec27c`. Share verified behavior and clearly distinguish native captures, design fixtures, and generated examples. Do not claim that a cached drawing proves native glass appearance or that installing proves successful generation.

Build and test with the commands in README. Fixtures use a preview bundle identifier and `-design-preview`; no argument-less Finder or LaunchServices launch is allowed. Optional local fixture artwork never becomes a real desktop or paid request. Unregister scratch bundles after checks. Installation permission, immutable snapshot requirements, force-quit policy, and source-stamp verification are recorded in [AGENTS.md](../AGENTS.md). One installer operates at a time.

### Pending installed-app checks

These checks require an owner-authorized signed build. Source review and fake services do not establish their runtime or visual results. No current test count, successful install, live generation, or native visual approval is claimed here.

- Drop a portrait picture and verify that it appears immediately. Exactly one guarded preview may be requested, and the desktop must stay unchanged. Edit the idea and crop the original inline. Cancelled or unchanged framing creates no preview; changed Done creates one.
- Press Start Daydreaming. Verify the resulting desktop image is full size for the current hour and that subsequent scheduled updates use the chosen source and idea. Inspect multiple displays and confirm the framed area matches each display's fill behavior.
- Previous pictures shows only originals with their most recent recorded idea. Cached variations stay available by scrolling the selected picture in the main preview. Choose This Picture must prepare its original, idea, and framing in the workspace without applying a small variation. Confirm that recorded instructions are understandable, unavailable originals are reported, and switching back reuses matching previews without another charge.
- Use the minimum window size with a portrait source. The instructions, slider, help, and primary action must fit, and the artwork must remain useful. Check bright and dark pictures with Reduce Transparency and Increase Contrast.
- In Crop, drag the original picture beneath the fixed frame, use pinch and zoom, and test Reset, Cancel, Done, arrow keys, and VoiceOver. Confirm the ratio stays screen-shaped and Cancel creates nothing.
- Edit instructions, pause to request a preview, then Escape. Automatic instructions must remain unchanged. Move another app in front before the preview sends; no background preview should be charged.
- Exercise keyboard navigation and Full Keyboard Access. Arrow keys must not be stolen from text fields or sliders. Verify one main window after closing and reopening from Applications or Spotlight, including with the menu bar icon hidden.
- Grant, cancel, and deny a typed-file permission panel. The Powerbox panel must survive focus changes. Automatic work must skip ungranted files. Check location denial and recovery from System Settings.
- Save, replace, remove, relaunch, and update the API key with the stable production signature. No password prompt should appear. Verify launch at login and Run Setup Again without losing picture history or the key.
- Compare the app's submitted-request count with OpenAI usage after the first day. A small trial limit reduces exposure but also leaves fewer preview slots because two slots are reserved for full wallpapers.

Network cancellation mapping, cancellation during a real permission panel, and macOS refusing to apply a desktop image need practical signed-build checks. Fixtures and injected services establish deterministic app behavior, not service eligibility or a paid result.
