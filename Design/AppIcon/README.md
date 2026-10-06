# Daydreaming app icon: Swell

Five equal bands of the day (dawn sky, orange, coral, plum, blue), the land swelling gently to the right. Chosen by the owner on 2026-10-06.

## The source of truth

[`WeatherCanvas/Resources/Daydreaming.icon`](../../WeatherCanvas/Resources/Daydreaming.icon) is the target's sole Icon Composer document for macOS 26 and later. Everything else here is generated from it.

- Shapes are plain white SVGs in `Assets/`. All color lives in `icon.json` as per-appearance fills (default, dark, tinted), so each appearance is tuned by hand.
- The four groups are the four land layers, listed front to back. The front (blue) layer is solid. The three behind it are frosted glass slabs (translucency 0.45, blur 0.5) that overlap the layer below, so each slab's lower edge shows through the one in front.
- Every group uses `specular-highlight-placement: inside`, because macOS 26 only draws specular highlights when this is set to inside or outside. Shadows are `layer-color`.
- The sky is the document background, so in tinted and clear modes the top band takes the system tint, as with Apple's own icons.
- Following Apple's guidance, nothing is baked in: no bevels, rims, shadows or highlights in the artwork. The outer edge treatment is left to the system.

## Using it in the app

`project.yml` already includes `WeatherCanvas/Resources/Daydreaming.icon` and sets `ASSETCATALOG_COMPILER_APPICON_NAME = Daydreaming`. Xcode compiles it into `Assets.car` and an `.icns` fallback. No PNG appiconset is used. `archive/cloud-draft.icon` preserves the previous concept outside the app target.

`xcode/` holds what `actool` produced from this exact document (`Daydreaming.icns` and its iconset). They're for reference and verification, not for adding to the project. It compiled with no warnings or errors:

    xcrun actool WeatherCanvas/Resources/Daydreaming.icon --compile out --platform macosx --minimum-deployment-target 26.0 --app-icon Daydreaming --output-partial-info-plist out/partial.plist

## Renders

`renders/` has every appearance (default, dark, tinted light and dark, clear light and dark) at 1024, 512, 256, 128, 64, 32 and 16 px. They were rendered with Icon Composer's `ictool` using the macOS 26 design generation. They're full bleed with the system's rounded mask applied and transparent corners.

## Web

Browsers can't render Liquid Glass, so `web/` has flat versions drawn from the same shapes and colors:

- `daydreaming-flat-square.svg` and `.png` are full bleed and square. Use them where the platform applies its own mask, such as apple-touch-icon and PWA maskable icons.
- `daydreaming-flat-rounded.svg` and `.png` are clipped to a superellipse close to the macOS icon shape. Use them for favicon.svg and anywhere the icon is shown on its own. The shape is an approximation of Apple's mask, not the exact curve.
- The `-dark` versions are the dark appearance, for `prefers-color-scheme: dark`.
- `daydreaming-glass-1024.png` and `daydreaming-glass-dark-1024.png` are the real Liquid Glass renders, for showing the app icon on the website, for example in a hero or download section.

## Not final yet

The menu bar glyph for this icon hasn't been designed yet. It will follow separately.

## Regenerating

From this repository root, run:

    python3 Design/AppIcon/source/package.py

The local runner rebuilds the selected Swell document, all 42 native renders, the compiled fallback and web exports. It needs Xcode with Icon Composer's `ictool`, `rsvg-convert` and ImageMagick (`magick`). It does not launch Icon Composer or accept a GUI license.

To verify generator reproducibility without replacing the approved app document, use:

    python3 Design/AppIcon/source/package.py --verify-only

Both modes render from the app document and compile it with `actool`. `validation/actool.txt` records compiler output and `validation/document-sha256.json` records the document's source hashes. Compiled fallback files and web exports are reference assets outside the app target.

`source/designer/` preserves the complete original handoff scripts and README, including the original workspace paths. The local runner imports their Swell formulas and flat web renderer. Run the local `source/package.py`, rather than the archived designer commands. The original handoff was chosen on 2026-10-06. The previous cloud draft is archived only for provenance.
