# Simple workspace prototype

Open `index.html` in a browser, or serve this folder over localhost. This is an isolated HTML interaction prototype. It does not modify the native app, call an API, apply a desktop wallpaper, or publish anything.

Add `?empty` to the URL to try the workspace without a selected picture. The idea stays editable; crop, the timeline and Start appear after a picture is chosen or dropped.

The layout has four clear parts: choose or drop a picture, write a short multiline idea, preview different hours, and start an automatically changing wallpaper. There is no More menu. Picture selection, typing and moving the time slider refresh the preview automatically. Cropping pans and zooms the original within the same preview area, using drag, scroll, touch pinch, a slider or the zoom buttons. Done refreshes the preview once; Cancel restores the previous framing. Previous pictures includes the original and its explored variations.

Preview behavior and hourly weather are simulated. The Yosemite examples are pre-existing website-only AI edits copied from the website workspace. Uploaded pictures use local CSS color treatments instead of AI edits. Arbitrary written ideas do not produce actual generative transformations. The prototype says so above the simulated app window.

The original Yosemite photo is the same documented public-domain NPS Photo / C. Jacoby already bundled by the app. See `docs/yosemite-picture.md` in the repository for provenance. The app icon comes from `Design/AppIcon`.

The final confirmation simulates starting a full-quality, current-hour desktop wallpaper and its automatic updates. It does not promise that the exact smaller preview becomes the desktop. Browsing hours changes the preview only. Picture and idea changes need confirmation to replace the running wallpaper recipe.
