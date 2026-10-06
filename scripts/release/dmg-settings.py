"""Finder layout. Build with the pinned dmgbuild environment, without Finder scripting."""
from pathlib import Path

app = Path(defines["app"]).resolve()
design = Path(defines["design"]).resolve()
if not app.is_dir() or app.name != "Daydreaming.app":
    raise ValueError("Expected an exported Daydreaming.app")

format = "ULMO"
filesystem = "APFS"
files = [str(app)]
symlinks = {"Applications": "/Applications"}
background = str(design / "background.png")
icon = str(app / "Contents/Resources/Daydreaming.icns")
icon_locations = {"Daydreaming.app": (200, 218), "Applications": (520, 218),
                  ".background.tiff": (1000, 218), ".VolumeIcon.icns": (1200, 218)}
window_rect = ((240, 180), (720, 512))
default_view = "icon-view"
show_toolbar = False
show_sidebar = False
show_status_bar = False
show_tab_view = False
show_pathbar = False
arrange_by = None
grid_spacing = 90
icon_size = 128
text_size = 13
label_pos = "bottom"
