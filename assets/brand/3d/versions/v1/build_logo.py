"""skil.li — the glass ribbon S, built as one continuous folded strip.

Run inside Blender (Text editor › Run Script, or `blender -P build_logo.py`).
It (re)builds the collection "skilli_logo": the ribbon, the dot (a glass sphere), their glass
material, and nothing else. Lighting and camera live in `build_scene.py`.

Geometry
--------
The S is a single flat strip (unrolled length ≈ 631, width ≈ 54, in the SVG's
units), Z-folded. At each fold the strip rolls away from the viewer around a
half-ellipse ("D") cross-section: semi-axis a = 14.7 across, b = 55.3 deep.
Seen from the front, the face starts curving gently, the rim is tight and
bright, and the corners of the loop come out rounded, as in the approved
still. Every fold is an isometry (a generalised cylinder), so the surface is
exactly what a real ribbon can do: no stretching, no seams.

  top band (front) ─ fold ─ diagonal (2b behind) ─ fold ─ bottom band (front)

As in the approved render, the outer bands own the rims and pass in front of
the diagonal; the object is point-symmetric about its depth axis.

Seen from the front (orthographic), it reproduces `../ribbon-mask.svg`
(IoU 0.958, fitted by `fit_ribbon.py`). The remaining 4 % is physics: a real
fold forces the curl slant to be the bisector of the two bands (15.4° from
vertical); the 2D drawing slants it 21°. The fold depth is what lets the
diagonal sit where the drawing puts it: a flat crease would push it ~60 units
to the right.

Coordinates: SVG x right / y down / depth d away from the viewer, mapped to
Blender X = x, Y = d, Z = −y, then scaled by SCALE and centred on the origin.
UV: u runs along the unrolled ribbon (0 = top-right free end, 1 = bottom-left
free end), v across it. Handy for reveal animations in three.js.
"""
import bisect
import math

import bmesh
import bpy

# Fitted against ribbon-mask.svg (see fit_ribbon.py). SVG units.
P = dict(
    theta=105.4221,   # crease direction, degrees (SVG frame, y down)
    x1=88.7148,       # where the first fold starts on the top edge
    D=244.3337,       # unrolled distance between the two folds
    a=14.7201,        # fold cross-section: half-ellipse semi-axis across (rim reach)
    b=55.3287,        # … and in depth (the diagonal sits 2b behind)
    w=54.1768,        # ribbon width
    yt=39.7334,       # top edge of the top band
    xmin=-418.0278,   # bottom-left free end (unrolled)
    xmax=212.9216,    # top-right free end
)
R_OUTER, R_INNER = 6.5, 22.0          # free-end corner radii, from the SVG
DOT = (215.0, 209.0, 17.5)            # cx, cy, r — from the SVG
THICKNESS = 2.0                       # glass sheet thickness (SVG units)
OPAL = 0.28                           # share of diffuse transmission in the glass
GLASS_TINT = (0.86, 0.98, 1.0, 1.0)   # glass body: near clear, cool
OPAL_TINT = (0.62, 0.95, 0.97, 1.0)   # milky share: the site's cyan face
SCALE = 0.01                          # 1 SVG unit = 1 cm → S ≈ 1.9 m tall
COLLECTION = "skilli_logo"

# ---------------------------------------------------------------- fold maths

th = math.radians(P["theta"])
C = (math.cos(th), math.sin(th))                  # crease (ruling) direction
N = (-math.sin(th), math.cos(th))                 # travel direction (leftwards)
if N[0] > 0:
    N = (-N[0], -N[1])
A, B = P["a"], P["b"]
D_END = 2 * B                                     # depth of the diagonal


def _ellipse_table(n=6000):
    ph = [math.pi * i / n for i in range(n + 1)]
    s, acc = [0.0], 0.0
    for p0, p1 in zip(ph, ph[1:]):
        acc += math.hypot(A * (math.sin(p1) - math.sin(p0)), B * (math.cos(p0) - math.cos(p1)))
        s.append(acc)
    return ph, s


PHI, ARC = _ellipse_table()
L = ARC[-1]                                       # arc length of one fold
Q1 = (P["x1"], P["yt"])
FOLDS = [Q1, (Q1[0] + P["D"] * N[0], Q1[1] + P["D"] * N[1])]


def phi_of_s(s):
    i = min(max(bisect.bisect_left(ARC, s), 1), len(ARC) - 1)
    f = (s - ARC[i - 1]) / (ARC[i] - ARC[i - 1])
    return PHI[i - 1] + f * (PHI[i] - PHI[i - 1])


def s_of_phi(phi):
    i = min(max(bisect.bisect_left(PHI, phi), 1), len(PHI) - 1)
    f = (phi - PHI[i - 1]) / (PHI[i] - PHI[i - 1])
    return ARC[i - 1] + f * (ARC[i] - ARC[i - 1])


def profile(s):
    """Cross-section of one fold: arc length s → (p along N, depth)."""
    phi = phi_of_s(s)
    return A * math.sin(phi), B * (1 - math.cos(phi))


def fold(x, y, k=0):
    """Unrolled point → (x, y, depth) after folds k.. ."""
    if k == len(FOLDS):
        return x, y, 0.0
    qx, qy = FOLDS[k]
    s = (x - qx) * N[0] + (y - qy) * N[1]
    t = (x - qx) * C[0] + (y - qy) * C[1]
    if s <= 0:
        return x, y, 0.0
    if s <= L:
        p, d = profile(s)
        return qx + p * N[0] + t * C[0], qy + p * N[1] + t * C[1], d
    # Beyond the fold: fold the rest first, then rotate it 180° about the fold.
    bx, by, bd = fold(x, y, k + 1)
    sb = (bx - qx) * N[0] + (by - qy) * N[1]
    tb = (bx - qx) * C[0] + (by - qy) * C[1]
    p = -(sb - L)
    return qx + p * N[0] + tb * C[0], qy + p * N[1] + tb * C[1], D_END - bd


# ------------------------------------------------------------- strip layout

YT, W = P["yt"], P["w"]
YC = YT + W / 2
SLANT = C[0] / C[1]                               # dx per dy along a ruling


def xc_of_s(s):
    """Centre-line x of the ruling at fold-1 arc length s."""
    return Q1[0] + (s - N[1] * (YC - Q1[1])) / N[0]


def corner_cut(x, x_end, side, r):
    """How much a rounded corner of radius r eats into a column at x."""
    cx = x_end - side * r
    dx = (x - cx) * side
    if dx <= 0:
        return 0.0
    return r - math.sqrt(max(r * r - dx * dx, 0.0))


def columns():
    """(centre x, slant factor λ, y-min, y-max) for every column, right → left."""
    cols = []

    def cap(x_end, side, r_top, r_bot):
        xs = set()
        for r in (r_top, r_bot):
            for i in range(13):
                xs.add(round(x_end - side * r * (1 - math.cos(math.radians(90 * i / 12))), 6))
        for i in range(1, 4):
            xs.add(x_end - side * (r_bot + 2.0 * i))
        return sorted(xs, key=lambda v: -side * v)

    def flat_cols(x_end, side, r_top, r_bot):
        out = []
        for x in cap(x_end, side, r_top, r_bot):
            top = corner_cut(x, x_end, side, r_top)
            bot = corner_cut(x, x_end, side, r_bot)
            out.append((x, 0.0, YT + top, YT + W - bot))
        return out

    def blend(xa, xb, n, rising):
        out = []
        for i in range(1, n):
            f = i / n
            lam = 0.5 - 0.5 * math.cos(math.pi * f)
            lam = lam if rising else 1 - lam
            out.append((xa + (xb - xa) * f, lam, YT, YT + W))
        return out

    def fold_cols(s0):
        # Evenly spaced in surface-normal angle, so the tight rim gets as many
        # columns as it needs and the gentle start of the roll is not wasted.
        ss = [s0 - 12 + 4 * i for i in range(3)]
        n = 72
        for i in range(n + 1):
            psi = math.pi * i / n                   # tangent angle along the D
            phi = math.atan2(A * math.sin(psi), B * math.cos(psi)) % math.pi if i < n else math.pi
            ss.append(s0 + s_of_phi(phi))
        ss += [s0 + L + 4 * i for i in range(1, 4)]
        return ss

    # top-right free end → blend → fold 1 → diagonal → fold 2 → blend → free end
    right = flat_cols(P["xmax"], +1, R_OUTER, R_INNER)
    cols += right
    s_list = fold_cols(0.0)
    mid_a, mid_b = L + 12, P["D"] - 12
    n_mid = max(2, round((mid_b - mid_a) / 7))
    s_list += [mid_a + (mid_b - mid_a) * i / n_mid for i in range(1, n_mid)]
    s_list += fold_cols(P["D"])
    xs_fold = [xc_of_s(s) for s in s_list]
    cols += blend(right[-1][0], xs_fold[0], 12, True)
    cols += [(x, 1.0, YT, YT + W) for x in xs_fold]
    left = flat_cols(P["xmin"], -1, R_INNER, R_OUTER)
    cols += blend(xs_fold[-1], left[-1][0], 14, False)
    cols += left[::-1]
    return cols


# --------------------------------------------------------------- build mesh

def centre():
    """Front-view centre of S + dot, and middle depth."""
    return (53.0 + DOT[0] + DOT[2]) / 2, (37.0 + DOT[1] + DOT[2]) / 2, D_END / 2


def to_blender(x, y, d, ctr):
    return ((x - ctr[0]) * SCALE, (d - ctr[2]) * SCALE, -(y - ctr[1]) * SCALE)


def _smooth(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def fold_shade(x, y):
    """The SVG's "fold" gradient, carried by the ribbon itself (vertex colour).

    The diagonal shows the other side of the ribbon: dark where it leaves a
    fold, light through the middle (stops from ribbon-glass.svg: dark → light
    at 35–65 % → dark). The outer bands, and the front of each roll, stay 1.
    """
    s = (x - Q1[0]) * N[0] + (y - Q1[1]) * N[1]
    end_a, end_b = 0.45, 0.52                     # #001d29 / #234654 ends
    if s <= L / 2 or s >= P["D"] + L / 2:
        return 1.0
    if s < L:                                     # back of fold 1 → diagonal
        return 1.0 + (end_a - 1.0) * _smooth(L / 2, L, s)
    if s > P["D"]:                                # diagonal → back of fold 2
        return end_b + (1.0 - end_b) * _smooth(P["D"], P["D"] + L / 2, s)
    f = (s - L) / (P["D"] - L)
    if f < 0.35:
        return end_a + (0.92 - end_a) * _smooth(0.0, 0.35, f)
    if f < 0.65:
        return 0.92 + 0.08 * math.sin(math.pi * (f - 0.35) / 0.3)
    return 0.92 + (end_b - 0.92) * _smooth(0.65, 1.0, f)


def ribbon_mesh(ctr, nv=16):
    cols = columns()
    span = P["xmax"] - P["xmin"]
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    shade = bm.verts.layers.float_color.new("shade")
    grid = []
    for xc, lam, y0, y1 in cols:
        col = []
        for i in range(nv + 1):
            y = y0 + (y1 - y0) * i / nv
            x = xc + lam * (y - YC) * SLANT
            v = bm.verts.new(to_blender(*fold(x, y), ctr))
            k = fold_shade(x, y)
            v[shade] = (k, k, k, 1.0)
            col.append((v, ((P["xmax"] - x) / span, 1 - (y - YT) / W)))
        grid.append(col)
    for a, b in zip(grid, grid[1:]):
        for i in range(nv):
            quad = (a[i], b[i], b[i + 1], a[i + 1])
            f = bm.faces.new([q[0] for q in quad])
            for loop, q in zip(f.loops, quad):
                loop[uv].uv = q[1]
    bm.normal_update()
    # The top band must face the viewer (−Y).
    probe = max(bm.faces, key=lambda f: f.calc_center_median().x)
    if probe.normal.y > 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    me = bpy.data.meshes.new("skilli_ribbon")
    bm.to_mesh(me)
    bm.free()
    me.color_attributes.active_color_name = "shade"
    return me


def dot_mesh(ctr, segments=96, rings=48):
    """The dot: a glass sphere of the SVG circle's radius, centred on the
    front plane (with the bottom band). Seen from the front it is the SVG dot."""
    cx, cy, r = DOT
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings,
                              radius=r * SCALE, calc_uvs=True)
    bmesh.ops.translate(bm, verts=bm.verts, vec=to_blender(cx, cy, 0.0, ctr))
    shade = bm.verts.layers.float_color.new("shade")
    for v in bm.verts:
        v[shade] = (1.0, 1.0, 1.0, 1.0)
    for f in bm.faces:
        f.smooth = True
    me = bpy.data.meshes.new("skilli_dot")
    bm.to_mesh(me)
    bm.free()
    me.color_attributes.active_color_name = "shade"
    return me


def glass_material():
    mat = bpy.data.materials.get("skilli_glass") or bpy.data.materials.new("skilli_glass")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (500, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (0, 0)
    vals = {
        "Base Color": GLASS_TINT,                 # tints what passes through
        "Roughness": 0.16,                        # "verre légèrement givré": blurred halo
        "IOR": 1.45,
        "Transmission Weight": 1.0,
        "Specular IOR Level": 0.5,
        "Coat Weight": 1.0,                       # polished skin over the frosted body:
        "Coat Roughness": 0.04,                   # crisp softbox reflections on the folds
        "Coat IOR": 1.5,
    }
    for k, v in vals.items():
        if k in bsdf.inputs:
            bsdf.inputs[k].default_value = v
    # Opal share: diffuse transmission lit by the halo behind; the 3D twin of
    # the site's whitish "face" layer over the refracted halo.
    opal = nt.nodes.new("ShaderNodeBsdfTranslucent")
    opal.location = (0, 300)
    # Both tints are multiplied by the ribbon's "shade" (the SVG fold gradient).
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "shade"
    attr.location = (-500, 200)
    for target, colour in ((bsdf.inputs["Base Color"], GLASS_TINT), (opal.inputs["Color"], OPAL_TINT)):
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.location = (-250, target.node.location.y + 150)
        mul.inputs["Factor"].default_value = 1.0
        mul.inputs[6].default_value = colour
        nt.links.new(attr.outputs["Color"], mul.inputs[7])
        nt.links.new(mul.outputs[2], target)
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.location = (300, 100)
    mix.inputs["Fac"].default_value = OPAL
    nt.links.new(bsdf.outputs[0], mix.inputs[1])
    nt.links.new(opal.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    # Thickness-dependent tint: grazing views through more glass turn deeper mint.
    absorb = nt.nodes.new("ShaderNodeVolumeAbsorption")
    absorb.location = (0, -380)
    absorb.inputs["Color"].default_value = (0.55, 0.92, 0.85, 1.0)
    absorb.inputs["Density"].default_value = 6.0
    nt.links.new(absorb.outputs[0], out.inputs["Volume"])
    if hasattr(mat, "use_screen_refraction"):
        mat.use_screen_refraction = True
    if hasattr(mat, "surface_render_method"):
        mat.surface_render_method = "DITHERED"
    if hasattr(mat, "use_raytrace_refraction"):
        mat.use_raytrace_refraction = True
    return mat


def add_glass_modifiers(ob):
    sol = ob.modifiers.new("thickness", "SOLIDIFY")
    sol.thickness = THICKNESS * SCALE
    sol.offset = 0.0
    sol.use_even_offset = True
    sol.use_quality_normals = True
    bev = ob.modifiers.new("rounded edge", "BEVEL")
    bev.width = THICKNESS * SCALE * 0.48
    bev.segments = 5
    bev.limit_method = "ANGLE"
    bev.angle_limit = math.radians(60)
    bev.harden_normals = True
    for poly in ob.data.polygons:
        poly.use_smooth = True


def build():
    old = bpy.data.collections.get(COLLECTION)
    if old:
        for ob in list(old.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
    else:
        old = bpy.data.collections.new(COLLECTION)
        bpy.context.scene.collection.children.link(old)
    for me in list(bpy.data.meshes):
        if me.name.startswith(("skilli_ribbon", "skilli_dot")) and me.users == 0:
            bpy.data.meshes.remove(me)
    ctr = centre()
    mat = glass_material()
    root = bpy.data.objects.new("skilli_logo", None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.3
    old.objects.link(root)
    # Same glass for the sphere, a touch more frosted: on a ball, a crisp coat
    # mirrors the whole studio ring as a hard "O".
    sphere_mat = bpy.data.materials.get("skilli_glass_sphere")
    if sphere_mat:
        bpy.data.materials.remove(sphere_mat)
    sphere_mat = mat.copy()
    sphere_mat.name = "skilli_glass_sphere"
    sb = next(n for n in sphere_mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    sb.inputs["Roughness"].default_value = 0.32
    sb.inputs["Coat Roughness"].default_value = 0.14
    for name, me in (("skilli_ribbon", ribbon_mesh(ctr)), ("skilli_dot", dot_mesh(ctr))):
        me.materials.append(mat if name == "skilli_ribbon" else sphere_mat)
        ob = bpy.data.objects.new(name, me)
        old.objects.link(ob)
        ob.parent = root
        if name == "skilli_ribbon":
            add_glass_modifiers(ob)       # the sphere is already a solid
        if name == "skilli_ribbon":
            # For web shaders (exported as glTF extras): fold-1 arc length s
            # as a linear function of the UVs, s = a·u + b·v + c, and where the
            # diagonal's glint sits (middle of its flat part).
            span = P["xmax"] - P["xmin"]
            a = -span * N[0]
            b = -W * N[1]
            c = (P["xmax"] - Q1[0]) * N[0] + (YT + W - Q1[1]) * N[1]
            ob["s_from_uv"] = [a, b, c]
            ob["glint_s"] = (L + P["D"]) / 2
            ob["glint_width"] = 0.12 * (P["D"] - L)
    return root


if __name__ == "__main__":
    build()
