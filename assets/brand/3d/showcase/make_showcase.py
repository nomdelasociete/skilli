"""Build the showcase page (live three.js view of v4 down to v1, flat exports, renders).

    python3 assets/brand/3d/showcase/make_showcase.py            # → showcase/page/
    python3 assets/brand/3d/showcase/make_showcase.py OUT_DIR

Embeds the HDR and the GLBs into index.html (artifact hosts do not serve
.glb/.hdr) and copies the images next to it. versions.png and compare.png
(made by hand from the renders and a capture of the site) live in this
folder and are copied too. The page is a full HTML document: open
page/index.html through any static server (three.js loads from jsDelivr).
"""
import base64
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
out = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "page"
out.mkdir(parents=True, exist_ok=True)


def b64(path):
    return base64.b64encode(path.read_bytes()).decode()


page = (HERE / "template.html").read_text()
page = (page.replace("__HDR_B64__", b64(ROOT / "studio-env.hdr"))
            .replace("__GLB_V4__", b64(ROOT / "skilli-logo.glb"))
            .replace("__GLB_V3__", b64(ROOT / "versions/v3/skilli-logo.glb"))
            .replace("__GLB_V2__", b64(ROOT / "versions/v2/skilli-logo.glb"))
            .replace("__GLB_V1__", b64(ROOT / "versions/v1/skilli-logo.glb")))
# The artifact host wraps the page in a document skeleton; standalone, it needs its own.
page = ('<!doctype html>\n<html lang="fr">\n<head>\n<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
        '</head>\n<body>\n' + page + '\n</body>\n</html>\n')
(out / "index.html").write_text(page, encoding="utf-8")
for name in ("skilli-mark@2x.png", "skilli-logo-3d.png", "skilli-logo-3d-angle.png", "skilli-logo-3d-text.png"):
    shutil.copy(ROOT / name, out / name)
for name in ("versions.png", "compare.png"):
    shutil.copy(HERE / name, out / name)
print(out / "index.html")
