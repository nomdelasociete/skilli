# dmgbuild settings for the skil.li DMG: the app on the left, Applications on
# the right, on assets/brand/dmg/background.png (and its @2x). Run by
# package.sh: dmgbuild -s dmg_settings.py -D app=<Skilli.app> -D background=<png> "skil.li" <out.dmg>
import os.path

app = defines['app']  # noqa: F821 (provided by dmgbuild)
background = defines['background']  # noqa: F821

files = [app]
symlinks = {'Applications': '/Applications'}
icon = os.path.join(app, 'Contents', 'Resources', 'AppIcon.icns')

format = 'UDZO'
compression_level = 9
filesystem = 'HFS+'

window_rect = ((200, 160), (640, 360))
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
icon_locations = {
    os.path.basename(app): (160, 180),
    'Applications': (480, 180),
}
