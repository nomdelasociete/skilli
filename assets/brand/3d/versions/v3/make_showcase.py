"""Build the showcase page (live three.js view of v3, v2 and v1, flat exports, renders).

    python3 assets/brand/3d/showcase/make_showcase.py OUT_DIR

Embeds the HDR and the three GLBs into OUT_DIR/index.html (artifact hosts do not
serve .glb/.hdr) and copies the images next to it. Comparison images
(versions.png, compare.png) are made by hand from the renders and a capture of
the site; drop them into OUT_DIR before publishing.
"""
import base64
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)


def b64(path):
    return base64.b64encode(path.read_bytes()).decode()


page = (HERE / "template.html").read_text()
page = (page.replace("__HDR_B64__", b64(ROOT / "studio-env.hdr"))
            .replace("__GLB_V3__", b64(ROOT / "skilli-logo.glb"))
            .replace("__GLB_V2__", b64(ROOT / "versions/v2/skilli-logo.glb"))
            .replace("__GLB_V1__", b64(ROOT / "versions/v1/skilli-logo.glb")))
(out / "index.html").write_text(page)
for name in ("skilli-mark@2x.png", "skilli-logo-3d.png", "skilli-logo-3d-angle.png"):
    shutil.copy(ROOT / name, out / name)
print(out / "index.html")
