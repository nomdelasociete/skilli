"""skil.li — studio around the glass ribbon: halo backdrop, softboxes, camera.

Run after build_logo.py. Rebuilds the collection "skilli_studio" only.

The backdrop is the website's halo shader (website/halo.js, "menthe" mode)
rebuilt in nodes, on an emissive plane behind the logo, so the glass really
refracts it, as in the approved still. Its `halo_time` input (same unit as the
website's `t`) can be keyframed; the logo itself never moves on its own.
"""
import math

import bpy
from mathutils import Vector

COLLECTION = "skilli_studio"
FRAME_SVG = 270 / 0.72          # README: the 270-unit viewBox fills 72 % of the square
SCALE = 0.01
VIEWBOX_CENTRE = (135.0, 132.0)
CREASE_TILT = 105.4221 - 90    # fold direction vs vertical (build_logo P["theta"])
GLINT = 4.0                    # glint strip strength
HALO_SPAN = 3.0                # backdrop size, in front frames (room for angled cameras)
SHADOW_SHARE = 0.55            # how dark the drop shadow gets (reference: #00141a66)
LOGO_CENTRE = ((53.0 + 215.0 + 17.5) / 2, (37.0 + 209.0 + 17.5) / 2)


def srgb(c):
    """Website colours are sRGB-encoded; Blender wants linear."""
    def ch(v):
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return tuple(ch(v) for v in c)


def fcurves(action):
    """F-curves of an action, layered (Blender 4.4+) or legacy."""
    if hasattr(action, "layers") and action.layers:
        return [fc for layer in action.layers for strip in layer.strips
                for bag in strip.channelbags for fc in bag.fcurves]
    return list(getattr(action, "fcurves", []))


def halo_material():
    mat = bpy.data.materials.get("skilli_halo") or bpy.data.materials.new("skilli_halo")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    N, Lk = nt.nodes, nt.links

    def node(kind, x, y, **inputs):
        n = N.new(kind)
        n.location = (x, y)
        for k, v in inputs.items():
            n.inputs[k].default_value = v
        return n

    def math_op(op, a, b=None, x=0, y=0):
        n = N.new("ShaderNodeMath")
        n.operation = op
        n.location = (x, y)
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = v
            else:
                Lk.new(v, n.inputs[i])
        return n.outputs[0]

    # time = halo_time * 0.38 (halo.js)
    t_in = node("ShaderNodeValue", -1600, 400)
    t_in.label = "halo_time"
    t_in.name = "halo_time"
    t_in.outputs[0].default_value = 3.0
    # Same pace as the website: one unit of halo_time per second.
    fps = bpy.context.scene.render.fps / bpy.context.scene.render.fps_base
    f0, f1 = bpy.context.scene.frame_start, bpy.context.scene.frame_end
    for f in (f0, f1):
        t_in.outputs[0].default_value = 3.0 + (f - f0) / fps
        t_in.outputs[0].keyframe_insert("default_value", frame=f)
    for fc in fcurves(nt.animation_data.action):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    time = math_op("MULTIPLY", t_in.outputs[0], 0.38, -1400, 400)

    def wave(fn, freq, phase, amp, base, y):
        a = math_op("MULTIPLY", time, freq, -1200, y)
        a = math_op("ADD", a, phase, -1050, y)
        a = math_op(fn, a, None, -900, y)
        a = math_op("MULTIPLY", a, amp, -750, y)
        return math_op("ADD", a, base, -600, y)

    # The plane spans HALO_SPAN front frames; remap so the front camera's frame
    # is exactly uv 0..1 (as on the website) and the halo simply continues around it.
    tc = node("ShaderNodeTexCoord", -1800, 0)
    remap = N.new("ShaderNodeVectorMath")
    remap.operation = "MULTIPLY_ADD"
    remap.location = (-1600, 0)
    Lk.new(tc.outputs["UV"], remap.inputs[0])
    remap.inputs[1].default_value = (HALO_SPAN, HALO_SPAN, 1.0)
    remap.inputs[2].default_value = (0.5 - HALO_SPAN / 2, 0.5 - HALO_SPAN / 2, 0.0)
    sep = node("ShaderNodeSeparateXYZ", -1400, 0)
    Lk.new(remap.outputs[0], sep.inputs[0])

    def blob(cx, cy, k, y):
        dx = math_op("SUBTRACT", sep.outputs[0], cx, -450, y)
        dy = math_op("SUBTRACT", sep.outputs[1], cy, -450, y - 60)
        d2 = math_op("ADD", math_op("MULTIPLY", dx, dx, -300, y),
                     math_op("MULTIPLY", dy, dy, -300, y - 60), -150, y)
        e = math_op("MULTIPLY", d2, k, 0, y)
        e = math_op("MULTIPLY", e, -1.0, 150, y)
        return math_op("EXPONENT", e, None, 300, y)

    a = blob(wave("SINE", 1.0, 0.0, 0.22, 0.64, 800), wave("COSINE", 0.8, 0.0, 0.18, 0.70, 700),
             wave("SINE", 0.65, 0.0, 0.7, 5.3, 600), 700)
    b = blob(wave("COSINE", 0.75, 0.0, 0.13, 0.16, 300), wave("SINE", 0.9, 0.0, 0.18, 0.18, 200),
             7.0, 200)
    h = blob(wave("SINE", 0.85, 0.7, 0.18, 0.75, -200), wave("COSINE", 0.7, 0.0, 0.12, 0.86, -300),
             16.0, -250)

    # col = mix(base, mint, a) + blue * b + warm * h   (all sRGB-encoded, like the GLSL)
    def rgb(c, x, y):
        n = node("ShaderNodeRGB", x, y)
        n.outputs[0].default_value = (*c, 1.0)
        return n.outputs[0]

    mix = N.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.location = (500, 600)
    Lk.new(a, mix.inputs["Factor"])
    Lk.new(rgb((0.015, 0.09, 0.13), 300, 500), mix.inputs[6])
    Lk.new(rgb((0.06, 0.58, 0.55), 300, 400), mix.inputs[7])

    def add_scaled(col, colour, f, y):
        sc = N.new("ShaderNodeVectorMath")
        sc.operation = "SCALE"
        sc.location = (650, y)
        Lk.new(rgb(colour, 500, y), sc.inputs[0])
        Lk.new(f, sc.inputs["Scale"])
        ad = N.new("ShaderNodeVectorMath")
        ad.operation = "ADD"
        ad.location = (800, y)
        Lk.new(col, ad.inputs[0])
        Lk.new(sc.outputs[0], ad.inputs[1])
        return ad.outputs[0]

    col = add_scaled(mix.outputs[2], (0.12, 0.25, 0.31), b, 300)
    col = add_scaled(col, (0.25, 0.34, 0.22), h, 0)
    # sRGB-encoded → linear (gamma 2.2 is within a hair of the sRGB curve here)
    # What the glass sees is the site's refracted layer: the same halo,
    # brightness(1.65) saturate(.72) (style.css, .halo-refraction). Camera rays
    # still see the plain halo.
    bright = N.new("ShaderNodeVectorMath")
    bright.operation = "SCALE"
    bright.location = (820, -300)
    Lk.new(col, bright.inputs[0])
    bright.inputs["Scale"].default_value = 1.65
    lum = N.new("ShaderNodeVectorMath")
    lum.operation = "DOT_PRODUCT"
    lum.location = (960, -450)
    Lk.new(bright.outputs[0], lum.inputs[0])
    lum.inputs[1].default_value = (0.2126, 0.7152, 0.0722)
    grey = N.new("ShaderNodeCombineXYZ")
    grey.location = (1100, -500)
    for i in range(3):
        Lk.new(lum.outputs["Value"], grey.inputs[i])
    sat = N.new("ShaderNodeMix")
    sat.data_type = "VECTOR"
    sat.location = (1250, -350)
    sat.inputs["Factor"].default_value = 0.72
    Lk.new(grey.outputs[0], sat.inputs[4])
    Lk.new(bright.outputs[0], sat.inputs[5])
    path = node("ShaderNodeLightPath", 1250, -650)
    pick = N.new("ShaderNodeMix")
    pick.data_type = "RGBA"
    pick.location = (1450, 0)
    Lk.new(path.outputs["Is Camera Ray"], pick.inputs["Factor"])
    Lk.new(sat.outputs[1], pick.inputs[6])
    Lk.new(col, pick.inputs[7])
    gam = node("ShaderNodeGamma", 1650, 200)
    gam.inputs["Gamma"].default_value = 2.2
    Lk.new(pick.outputs[2], gam.inputs["Color"])
    # Emission carries most of the halo; a diffuse share, lit only by the
    # "shadow_sun", lets the logo cast the soft drop shadow of the approved still
    # while unshadowed areas keep the exact website colours (sum = 1).
    em = node("ShaderNodeEmission", 1850, 300)
    em.inputs["Strength"].default_value = 1.0 - SHADOW_SHARE
    Lk.new(gam.outputs[0], em.inputs["Color"])
    dif = node("ShaderNodeBsdfDiffuse", 1850, 100)
    Lk.new(gam.outputs[0], dif.inputs["Color"])
    add = node("ShaderNodeAddShader", 2050, 200)
    Lk.new(em.outputs[0], add.inputs[0])
    Lk.new(dif.outputs[0], add.inputs[1])
    out = node("ShaderNodeOutputMaterial", 2250, 200)
    Lk.new(add.outputs[0], out.inputs["Surface"])
    return mat


def ring_material():
    mat = bpy.data.materials.get("skilli_ring") or bpy.data.materials.new("skilli_ring")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    tc = nt.nodes.new("ShaderNodeTexCoord")
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    dot.inputs[1].default_value = (-0.7071, 0.7071, 0.0)   # upper left, in ring space
    nt.links.new(tc.outputs["Object"], dot.inputs[0])
    ramp = nt.nodes.new("ShaderNodeMapRange")
    ramp.inputs["From Min"].default_value = -6.0
    ramp.inputs["From Max"].default_value = 6.0
    ramp.inputs["To Min"].default_value = 0.6
    ramp.inputs["To Max"].default_value = 4.5
    nt.links.new(dot.outputs["Value"], ramp.inputs["Value"])
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (0.9, 1.0, 0.97, 1.0)
    nt.links.new(ramp.outputs[0], em.inputs["Strength"])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return mat


def diagonal_centre():
    """Centre of the visible diagonal: the ribbon's vertices on the back plane."""
    ob = bpy.data.objects["skilli_ribbon"]
    ys = [v.co.y for v in ob.data.vertices]
    back = max(ys)
    pts = [ob.matrix_world @ v.co for v in ob.data.vertices if v.co.y > back - 0.005]
    return sum(pts, Vector()) / len(pts)


def glint_material():
    mat = bpy.data.materials.get("skilli_glint") or bpy.data.materials.new("skilli_glint")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    # Soft across the strip: sin(pi * x), peaking in the middle.
    m1 = nt.nodes.new("ShaderNodeMath")
    m1.operation = "MULTIPLY"
    m1.inputs[1].default_value = math.pi
    nt.links.new(sep.outputs["X"], m1.inputs[0])
    m2 = nt.nodes.new("ShaderNodeMath")
    m2.operation = "SINE"
    nt.links.new(m1.outputs[0], m2.inputs[0])
    m3 = nt.nodes.new("ShaderNodeMath")
    m3.operation = "POWER"
    m3.inputs[1].default_value = 2.0
    nt.links.new(m2.outputs[0], m3.inputs[0])
    m4 = nt.nodes.new("ShaderNodeMath")
    m4.operation = "MULTIPLY"
    m4.inputs[1].default_value = GLINT
    nt.links.new(m3.outputs[0], m4.inputs[0])
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (0.9, 1.0, 0.98, 1.0)
    nt.links.new(m4.outputs[0], em.inputs["Strength"])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return mat


def area(coll, name, loc, target, size, energy, colour, shape="RECTANGLE", size_y=None):
    ld = bpy.data.lights.new(name, "AREA")
    ld.shape = shape
    ld.size = size
    if size_y:
        ld.size_y = size_y
    ld.energy = energy
    ld.color = colour
    ld.use_shadow = False   # studio lights shape highlights; only the halo sun casts shadows
    ob = bpy.data.objects.new(name, ld)
    coll.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    return ob


def build():
    coll = bpy.data.collections.get(COLLECTION)
    if coll:
        for ob in list(coll.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
    else:
        coll = bpy.data.collections.new(COLLECTION)
        bpy.context.scene.collection.children.link(coll)
    for name in ("Camera", "Light"):
        ob = bpy.data.objects.get(name)
        if ob and ob.users_collection and ob.users_collection[0] == bpy.context.scene.collection:
            bpy.data.objects.remove(ob, do_unlink=True)

    scene = bpy.context.scene
    frame = FRAME_SVG * SCALE
    offset = ((VIEWBOX_CENTRE[0] - LOGO_CENTRE[0]) * SCALE, -(VIEWBOX_CENTRE[1] - LOGO_CENTRE[1]) * SCALE)

    # Camera: orthographic, square, framed exactly like halo-menthe-glass.png.
    cd = bpy.data.cameras.new("skilli_camera")
    cd.type = "ORTHO"
    cd.ortho_scale = frame
    cd.clip_start, cd.clip_end = 0.1, 100
    cam = bpy.data.objects.new("skilli_camera", cd)
    coll.objects.link(cam)
    cam.location = (offset[0], -12.0, offset[1])
    cam.rotation_euler = (math.radians(90), 0, 0)
    scene.camera = cam

    # A second, angled camera that shows the ribbon is one folded piece.
    ad = bpy.data.cameras.new("skilli_camera_angle")
    ad.lens = 85
    ad.clip_start, ad.clip_end = 0.1, 100
    angle = bpy.data.objects.new("skilli_camera_angle", ad)
    coll.objects.link(angle)
    angle.location = (5.2, -9.6, 3.0)
    angle.rotation_euler = (Vector((0, 0, 0)) - angle.location).to_track_quat("-Z", "Y").to_euler()

    # Halo backdrop, filling the frame (and more, for refraction at the edges).
    bpy.ops.mesh.primitive_plane_add(size=1)
    bd = bpy.context.active_object
    for c in bd.users_collection:
        c.objects.unlink(bd)
    coll.objects.link(bd)
    bd.name = "skilli_halo"
    depth = 3.0
    bd.scale = (frame * HALO_SPAN, frame * HALO_SPAN, 1)
    bd.location = (offset[0], depth, offset[1])
    bd.rotation_euler = (math.radians(90), 0, 0)
    bd.data.materials.clear()
    bd.data.materials.append(halo_material())
    bd.visible_shadow = False             # the halo lights the glass's opal share

    # Lights: soft key from the upper left (the SVG's edge gradient is brightest
    # there), a mint rim from behind on the right, a thin strip above for the
    # rims of the folds. Highlights stay fixed on the folds: nothing sweeps.
    area(coll, "key_softbox", (-2.0, -2.4, 2.2), (0, 0, 0), 2.0, 160, (1.0, 1.0, 1.0), size_y=2.2)
    area(coll, "rim_mint", (3.4, 3.0, 1.8), (0, 0, 0), 2.5, 250, (0.62, 1.0, 0.9))
    area(coll, "strip_top", (0.0, -2.2, 4.2), (0, 0, 0), 4.0, 350, (0.92, 1.0, 0.98), size_y=0.35)
    area(coll, "fill_low", (1.5, -4.5, -3.0), (0, 0, 0), 3.0, 120, (0.55, 0.85, 1.0))

    # Outline ring: an emissive ring around the view axis, seen only in
    # reflections. Every rounded glass edge mirrors it as one thin bright line,
    # the physical version of the SVG's edge stroke. Brighter towards the upper
    # left, like the stroke gradient (#fff → dimmer at the lower right).
    bpy.ops.mesh.primitive_torus_add(major_radius=4.4, minor_radius=1.8,
                                     major_segments=128, minor_segments=12)
    ring = bpy.context.active_object
    for c in ring.users_collection:
        c.objects.unlink(ring)
    coll.objects.link(ring)
    ring.name = "outline_ring"
    ring.location = (offset[0], -4.6, offset[1])
    ring.rotation_euler = (math.radians(90), 0, 0)
    ring.scale = (1, 1, 0.02)                  # flatten into an annulus, 2.6 m → 6.2 m: flat faces never see it
    ring.visible_camera = False
    ring.visible_shadow = False
    ring.visible_transmission = False          # reflections only: no ring inside the sphere
    ring.data.materials.clear()
    ring.data.materials.append(ring_material())

    # Glint on the diagonal: a soft strip, invisible to the camera, hanging in
    # front of the middle of the diagonal and aligned with the folds. With an
    # orthographic camera a flat face mirrors it as one fixed, soft streak:
    # the light band of the SVG "fold" gradient. It never moves.
    streak_centre = diagonal_centre()
    bpy.ops.mesh.primitive_plane_add(size=1)
    streak = bpy.context.active_object
    for c in streak.users_collection:
        c.objects.unlink(streak)
    coll.objects.link(streak)
    streak.name = "glint_strip"
    streak.location = (streak_centre.x, -2.0, streak_centre.z)
    streak.rotation_euler = (math.radians(90), math.radians(CREASE_TILT), 0)
    streak.scale = (0.16, 0.56, 1)
    streak.visible_camera = False
    streak.visible_shadow = False
    streak.data.materials.clear()
    streak.data.materials.append(glint_material())

    # Drop shadow: a soft sun from above-front that only lights the halo.
    sd = bpy.data.lights.new("shadow_sun", "SUN")
    sd.energy = math.pi * SHADOW_SHARE          # diffuse radiance = albedo * E / pi
    sd.angle = math.radians(5)
    sun = bpy.data.objects.new("shadow_sun", sd)
    coll.objects.link(sun)
    sun.rotation_euler = (Vector((0, 0, 0)) - Vector((0.0, -3.5, 0.16))).to_track_quat("-Z", "Y").to_euler()
    halo_only = bpy.data.collections.get("skilli_halo_only") or bpy.data.collections.new("skilli_halo_only")
    for o in list(halo_only.objects):
        halo_only.objects.unlink(o)
    halo_only.objects.link(bd)
    sun.light_linking.receiver_collection = halo_only
    logo = bpy.data.collections.get("skilli_logo")
    # The outline ring draws edges on the ribbon; on the sphere it would mirror
    # as a hard "O", so it only lights the ribbon.
    ribbon_only = bpy.data.collections.get("skilli_ribbon_only") or bpy.data.collections.new("skilli_ribbon_only")
    for o in list(ribbon_only.objects):
        ribbon_only.objects.unlink(o)
    if bpy.data.objects.get("skilli_ribbon"):
        ribbon_only.objects.link(bpy.data.objects["skilli_ribbon"])
    for ob in coll.objects:
        if (ob.type == "LIGHT" or ob.name in ("outline_ring", "glint_strip")) and ob is not sun and logo:
            ob.light_linking.receiver_collection = ribbon_only if ob.name == "outline_ring" else logo

    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (*srgb((0.02, 0.07, 0.09)), 1.0)
    bg.inputs["Strength"].default_value = 1.0

    # Render: square 1024, brand colours untouched by a filmic curve.
    scene.render.resolution_x = scene.render.resolution_y = 1024
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_depth = "8"
    try:
        scene.render.engine = "CYCLES"
    except TypeError:
        pass
    if scene.render.engine == "CYCLES":
        scene.cycles.samples = 256
        scene.cycles.use_denoising = True
        scene.cycles.max_bounces = 24
        scene.cycles.transmission_bounces = 24
        scene.cycles.glossy_bounces = 8
        scene.cycles.transparent_max_bounces = 24
        scene.cycles.caustics_refractive = False
        scene.cycles.caustics_reflective = False
        scene.cycles.blur_glossy = 0.5
    ee = scene.eevee
    for attr, val in (("use_raytracing", True), ("ray_tracing_method", "SCREEN"),
                      ("use_shadows", True)):
        if hasattr(ee, attr):
            try:
                setattr(ee, attr, val)
            except Exception:
                pass
    return cam


if __name__ == "__main__":
    build()
