"""skil.li — web exports of the glass ribbon, for three.js.

Run in Blender after build_logo.py and build_scene.py. Writes next to this file:

- skilli-logo.glb   the ribbon + dot, modifiers applied (thickness, rounded
                    edges), UVs, and a glTF-friendly glass material
                    (transmission, IOR, clearcoat, volume tint).
- studio-env.hdr    the studio lights (softboxes + outline ring) as an
                    equirectangular map, to use as three.js `scene.environment`
                    so the rims and edges catch the same highlights as in Blender.

The Blender scene is left as it was.
"""
import math
import os

import bpy

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else "//"
LOGO = "skilli_logo"
THICKNESS_M = 0.02                      # build_logo.THICKNESS * SCALE
DOT_DIAMETER_M = 0.35                   # the sphere: 2 × 17.5 SVG units
VIEWBOX = (270, 264)                    # ribbon-glass.svg
VIEWBOX_CENTRE = (135.0, 132.0)
LOGO_CENTRE = ((53.0 + 215.0 + 17.5) / 2, (37.0 + 209.0 + 17.5) / 2)
SCALE = 0.01


def web_material(name, thickness, source="skilli_glass"):
    """Principled-only twin of skilli_glass: what glTF can carry.

    The opal share and the site's refraction recipe (halo ×1.65, saturate .72)
    are not glTF; viewer.html adds them in three.js's transmission shader.
    """
    src = bpy.data.materials[source]
    sb = next(n for n in src.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    for name in ("Roughness", "IOR", "Transmission Weight", "Specular IOR Level",
                 "Coat Weight", "Coat Roughness", "Coat IOR"):
        bsdf.inputs[name].default_value = sb.inputs[name].default_value
    # Base colour = the ribbon's "shade" (fold gradient), exported as COLOR_0;
    # three.js multiplies it into the glass (vertexColors).
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "shade"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    absorb = nt.nodes.new("ShaderNodeVolumeAbsorption")
    sa = next(n for n in src.node_tree.nodes if n.type == "VOLUME_ABSORPTION")
    absorb.inputs["Color"].default_value = sa.inputs["Color"].default_value
    absorb.inputs["Density"].default_value = sa.inputs["Density"].default_value
    nt.links.new(absorb.outputs[0], out.inputs["Volume"])
    # The exporter reads KHR_materials_volume thickness from this node group.
    grp = bpy.data.node_groups.get("glTF Material Output")
    if grp is None:
        grp = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        for name in ("Occlusion", "Thickness", "Specular", "Specular Color"):
            kind = "NodeSocketColor" if name == "Specular Color" else "NodeSocketFloat"
            grp.interface.new_socket(name, in_out="INPUT", socket_type=kind)
    gout = nt.nodes.new("ShaderNodeGroup")
    gout.node_tree = grp
    gout.inputs["Thickness"].default_value = thickness
    mat.use_backface_culling = True     # a closed solid: no double-sided transmission
    return mat


def export_glb(path):
    root = bpy.data.objects[LOGO]
    parts = list(root.children)
    web = {"skilli_ribbon": web_material("skilli_glass_web", THICKNESS_M),
           "skilli_dot": web_material("skilli_glass_web_sphere", DOT_DIAMETER_M, "skilli_glass_sphere")}
    saved = {ob.name: list(ob.data.materials) for ob in parts}
    for ob in parts:
        ob.data.materials.clear()
        ob.data.materials.append(web[ob.name])
    bpy.ops.object.select_all(action="DESELECT")
    for ob in [root, *parts]:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = root
    try:
        bpy.ops.export_scene.gltf(
            filepath=path,
            export_format="GLB",
            use_selection=True,
            export_apply=True,
            export_yup=True,
            export_texcoords=True,
            export_normals=True,
            export_materials="EXPORT",
            export_vertex_color="NAME",            # the "shade" fold gradient → COLOR_0
            export_vertex_color_name="shade",
            export_all_vertex_colors=False,
            export_cameras=False,
            export_lights=False,
            export_animations=False,
            export_extras=True,                    # s_from_uv / glint_s for web shaders
        )
    finally:
        for ob in parts:
            ob.data.materials.clear()
            for m in saved[ob.name]:
                ob.data.materials.append(m)


def export_env(path, width=2048):
    """Equirectangular render of the studio from the logo's centre."""
    scene = bpy.context.scene
    hidden = []
    for name in (LOGO, "skilli_ribbon", "skilli_dot", "skilli_halo", "shadow_sun"):
        ob = bpy.data.objects.get(name)
        if ob:
            hidden.append((ob, ob.hide_render))
            ob.hide_render = True
    ring = bpy.data.objects.get("outline_ring")
    ring_cam = ring.visible_camera if ring else None
    if ring:
        ring.visible_camera = True
    lights = [ob for ob in bpy.data.collections["skilli_studio"].objects if ob.type == "LIGHT"]
    light_cam = {ob.name: ob.visible_camera for ob in lights}
    for ob in lights:
        ob.visible_camera = True
    cd = bpy.data.cameras.new("env_probe")
    cd.type = "PANO"
    cd.panorama_type = "EQUIRECTANGULAR"
    cam = bpy.data.objects.new("env_probe", cd)
    scene.collection.objects.link(cam)
    # three.js puts the centre of an equirect map on +X and its right on +Z;
    # Blender +X / −Y are those axes after the glTF Y-up conversion.
    cam.rotation_euler = (math.radians(90), 0, math.radians(-90))
    old = (scene.camera, scene.render.resolution_x, scene.render.resolution_y,
           scene.render.resolution_percentage, scene.render.image_settings.file_format,
           scene.render.filepath, scene.cycles.samples, scene.render.film_transparent)
    try:
        scene.camera = cam
        scene.render.resolution_x, scene.render.resolution_y = width, width // 2
        scene.render.resolution_percentage = 100
        scene.render.image_settings.file_format = "HDR"
        scene.render.filepath = path
        scene.cycles.samples = 64
        scene.render.film_transparent = False
        bpy.ops.render.render(write_still=True)
    finally:
        (scene.camera, scene.render.resolution_x, scene.render.resolution_y,
         scene.render.resolution_percentage, scene.render.image_settings.file_format,
         scene.render.filepath, scene.cycles.samples, scene.render.film_transparent) = old
        bpy.data.objects.remove(cam, do_unlink=True)
        bpy.data.cameras.remove(cd)
        for ob, h in hidden:
            ob.hide_render = h
        if ring:
            ring.visible_camera = ring_cam
        for ob in lights:
            ob.visible_camera = light_cam[ob.name]


def _render_flat(path, px_per_unit, transparent):
    scene = bpy.context.scene
    cd = bpy.data.cameras.new("flat_probe")
    cd.type = "ORTHO"
    cd.ortho_scale = VIEWBOX[0] * SCALE
    cam = bpy.data.objects.new("flat_probe", cd)
    scene.collection.objects.link(cam)
    cam.location = ((VIEWBOX_CENTRE[0] - LOGO_CENTRE[0]) * SCALE, -12.0,
                    -(VIEWBOX_CENTRE[1] - LOGO_CENTRE[1]) * SCALE)
    cam.rotation_euler = (math.radians(90), 0, 0)
    img = scene.render.image_settings
    old = (scene.camera, scene.render.resolution_x, scene.render.resolution_y,
           scene.render.resolution_percentage, scene.render.film_transparent,
           img.file_format, img.color_mode, img.color_depth, scene.render.filepath)
    try:
        scene.camera = cam
        scene.render.resolution_x = VIEWBOX[0] * px_per_unit
        scene.render.resolution_y = VIEWBOX[1] * px_per_unit
        scene.render.resolution_percentage = 100
        scene.render.film_transparent = transparent
        img.file_format = "PNG"
        img.color_mode = "RGBA" if transparent else "RGB"
        img.color_depth = "8" if transparent else "16"
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
    finally:
        (scene.camera, scene.render.resolution_x, scene.render.resolution_y,
         scene.render.resolution_percentage, scene.render.film_transparent,
         img.file_format, img.color_mode, img.color_depth, scene.render.filepath) = old
        bpy.data.objects.remove(cam, do_unlink=True)
        bpy.data.cameras.remove(cd)


def export_flat(path, px_per_unit=4, see_through=True):
    """The mark alone on a transparent background, framed exactly like
    ribbon-glass.svg (viewBox 270 × 264), so it can replace the SVG on the site.

    see_through=True (default): the glass is partly transparent in the PNG, so
    what the site puts behind it (the live halo, text) shows through; tint,
    highlights and rims are baked. Made by difference matting: the mark is
    rendered over pure black, then pure white, both seen only *through* the
    glass (reflections keep the studio), and alpha = 1 − (white − black).
    Both renders are denoised, so the alpha is clean. A flat image cannot bend
    what is behind it: no refraction of the site's background.
    see_through=False: the glass refracts the halo, baked in; opaque inside the
    mark (the v1–v3 export).
    No drop shadow: the site adds its own (CSS drop-shadow on .glass-ribbon).
    """
    halo = bpy.data.materials["skilli_halo"]
    halo_ob = bpy.data.objects["skilli_halo"]
    if not see_through:
        nt = halo.node_tree
        out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        surface = out.inputs["Surface"].links[0].from_socket
        path_node = nt.nodes.new("ShaderNodeLightPath")
        clear = nt.nodes.new("ShaderNodeBsdfTransparent")
        cut = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(path_node.outputs["Is Camera Ray"], cut.inputs["Fac"])
        nt.links.new(surface, cut.inputs[1])
        nt.links.new(clear.outputs[0], cut.inputs[2])
        nt.links.new(cut.outputs[0], out.inputs["Surface"])
        try:
            _render_flat(path, px_per_unit, transparent=True)
        finally:
            nt.links.new(surface, out.inputs["Surface"])
            for n in (path_node, clear, cut):
                nt.nodes.remove(n)
        return

    import numpy as np
    world = bpy.context.scene.world
    wt = world.node_tree
    wout = next(n for n in wt.nodes if n.type == "OUTPUT_WORLD")
    wsurf = wout.inputs["Surface"].links[0].from_socket
    lp = wt.nodes.new("ShaderNodeLightPath")
    seen = wt.nodes.new("ShaderNodeMath")
    seen.operation = "MAXIMUM"                    # camera or transmission ray
    wt.links.new(lp.outputs["Is Camera Ray"], seen.inputs[0])
    wt.links.new(lp.outputs["Is Transmission Ray"], seen.inputs[1])
    plate = wt.nodes.new("ShaderNodeBackground")
    pick = wt.nodes.new("ShaderNodeMixShader")
    wt.links.new(seen.outputs[0], pick.inputs["Fac"])
    wt.links.new(wsurf, pick.inputs[1])
    wt.links.new(plate.outputs[0], pick.inputs[2])
    wt.links.new(pick.outputs[0], wout.inputs["Surface"])
    hidden = halo_ob.hide_render
    halo_ob.hide_render = True
    tmp = {}
    try:
        for name, value in (("black", 0.0), ("white", 1.0)):
            plate.inputs["Color"].default_value = (value, value, value, 1.0)
            tmp[name] = path + f".{name}.png"
            _render_flat(tmp[name], px_per_unit, transparent=False)
    finally:
        halo_ob.hide_render = hidden
        wt.links.new(wsurf, wout.inputs["Surface"])
        for n in (lp, seen, plate, pick):
            wt.nodes.remove(n)

    def pixels(p):
        im = bpy.data.images.load(p)
        im.colorspace_settings.name = "Non-Color"       # keep the encoded values
        a = np.array(im.pixels[:], dtype=np.float32).reshape(im.size[1], im.size[0], 4)[..., :3]
        bpy.data.images.remove(im)
        return a

    black, white = pixels(tmp["black"]), pixels(tmp["white"])
    alpha = np.clip(1.0 - (white - black).mean(axis=2), 0.0, 1.0)
    colour = np.clip(black / np.maximum(alpha, 1e-4)[..., None], 0.0, 1.0)
    rgba = np.dstack([colour, alpha]).astype(np.float32)
    h, w = alpha.shape
    out_im = bpy.data.images.new("flat_out", w, h, alpha=True)
    out_im.colorspace_settings.name = "Non-Color"
    out_im.pixels[:] = rgba.ravel()
    out_im.filepath_raw = path
    out_im.file_format = "PNG"
    out_im.save()
    bpy.data.images.remove(out_im)
    for p in tmp.values():
        os.remove(p)


if __name__ == "__main__":
    export_glb(os.path.join(HERE, "skilli-logo.glb"))
    export_env(os.path.join(HERE, "studio-env.hdr"))
    export_flat(os.path.join(HERE, "skilli-mark@2x.png"))
    export_flat(os.path.join(HERE, "skilli-mark-halo@2x.png"), see_through=False)
