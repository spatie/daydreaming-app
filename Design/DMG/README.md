# Daydreaming installer

The Finder window uses the Swell icon's dawn, coral, plum and blue, with quiet overlapping hills and a curved drag arrow. The app and Applications icons are real draggable Finder items. The window's background has 1x and 2x artwork for Retina displays.

`background.svg` is the editable source. Regenerate the committed backgrounds with:

```sh
rsvg-convert background.svg -o background.png
rsvg-convert -z 2 background.svg -o background@2x.png
```

The release pipeline uses `scripts/release/dmg-settings.py` to set the icon positions, window size and background. It installs checksum-pinned dmgbuild and its dependencies in a temporary virtual environment. It writes Finder metadata directly, without controlling Finder or changing global preferences. Hidden support files are positioned outside the initial viewport for users who show hidden files.

Do not set `hide_extensions` on the app. That adds FinderInfo to the signed bundle and breaks strict signature validation. Packaging mounts the finished image read-only and checks the enclosed app signature, build identity, shortcut and artwork before notarization.

Notarization, stapling and signing remain part of the release pipeline. A locally generated design preview is not a public release.
