# v4 logo: local Three.js studies

Preview from the repository root:

```sh
python3 -m http.server 8770 --bind 127.0.0.1
```

Open `http://127.0.0.1:8770/website/experiments/logo/`.

Three treatments share the same animated mint halo and framing:

1. Transparent v4 PNG, with its baked lighting.
2. v4 GLB facing forward, with live transmission of the halo.
3. The same GLB with eased pointer tilt, limited to about 10° horizontally
   and 6° vertically. No automatic spin.

The optional text backdrop reveals refraction. Frost adjusts the body
roughness from 0.02 to 0.30; the polished rim stays at 0.02. Reset restores
0.1. Changing controls reloads the scene, restarting the halo at the same
phase. Freeze starts that scene paused.

## Sources and implementation

- Assets: `assets/brand/3d/skilli-logo.glb`, `studio-env.hdr`,
  `skilli-mark@2x.png`. Do not duplicate or overwrite the approved assets.
- Material and halo start from `assets/brand/3d/viewer.html`. Orthographic
  projection preserves the silhouette. The halo is geometry in the same
  scene, so Three.js transmission can sample it.
- The glint is fixed to the ribbon's UVs, not animated across the surface.
  Its Gaussian uses multiplication rather than GLSL `pow` with a negative
  base, which can produce undefined pixels on some GPUs.
- Three.js 0.170.0 is vendored from the official npm package, with its MIT
  license in `vendor/LICENSE.txt`. No CDN or analytics requests.
- One scene at a time. Pixel ratio capped at 2. Animation pauses when hidden,
  outside the viewport, or when reduced motion is requested. Resources are
  released on page exit. Loading/context failures show the PNG fallback.

## Status

Exploration only. `website/build.py` excludes `experiments` from production.
The live hero and approved website direction are unchanged. See
`docs/website-design.md` for those decisions. These studies are not a new
approved treatment until the user selects one.

Browser checks: all three modes render; text backdrop, roughness maximum,
reset and pause controls work. Mobile performance and Safari fidelity still
need evaluation before any production integration. No native app tests are
needed for this experiment.

## Scroll study

Open `scroll.html` from the comparator. The baseline uses the site's self-hosted
Geist Pixel Line, loaded before drawing the text texture. It starts beneath the
logo, rises behind its glass, then the logo rises with a small yaw and roll.
All movement is tied to scroll position and reverses when scrolling back.
Reduced motion removes rotation and the animated halo. Frost defaults to 0.1.
This is an isolated exploration, not a change to the published hero.

The responsive scroll treatment is now integrated into the real local landing
page at `/website/`. Shared rendering code and Three.js live in
`website/brand-glass/`; the comparator uses that same renderer. The user approved publishing the integrated hero on October 12.

In the landing hero, the original DOM headline retains its entry and hover
animations. At the glass crossing it hands off to the matching text texture.
The following navigation overlaps the end of the pinned sequence instead of
waiting for a tall empty hero to leave. Both title lines cross before logo exit.
