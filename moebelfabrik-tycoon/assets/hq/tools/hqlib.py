"""Shared Blender helpers for the HQ asset series (Blender 5.1, metres, Z up).

Project conventions (see docs/design/DIMENSIONS.md):
  * Blender (X, Y, Z) -> Roblox (X, Z, -Y). Front of an asset is Blender +Y.
  * Asset root = bottom centre of the outer footprint, at the origin.
  * FBX: axis_forward=-Z, axis_up=Y, global_scale=1, metres; Studio applies
    25/7 studs per metre exactly once.

Mobile-first structure (target: weak Android phone, graphics level 1):
  * Geometry is accumulated per (group, material) and written as ONE mesh
    object each -> few MeshParts / draw calls per asset.
  * Moving parts get their own group so Studio can animate them.
  * Hard edges are bevelled in the mesh and shaded with weighted normals,
    so silhouettes stay soft without normal-map baking.
  * Wood UVs are projected so U follows the grain axis of every part,
    with the same texel density across the series (TILE_M metres per tile).
"""
import bpy, bmesh, math, json, random
from mathutils import Vector, Matrix
from pathlib import Path

HQ = Path(__file__).resolve().parents[1]
TEX = HQ / "textures"
TILE_M = 0.5          # one texture tile covers 0.5 m -> consistent grain size
SHARP_DEG = 50        # bevel steps (45 deg) stay smooth, 90 deg corners stay sharp


def lin(hexcode):
    c = [int(hexcode[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in c) + (1.0,)


# ------------------------------------------------------------------ materials
# Roblox mapping is recorded per material in the manifest:
#   textured -> SurfaceAppearance (Color/Normal/Roughness maps)
#   flat     -> MeshPart.Color + MeshPart.Material, no texture memory
FLAT = {
    # name:         (hex,     rough, metal, roblox_material)
    "SteelDark":    ("34383C", .58, 0.0, "SmoothPlastic"),   # powder-coated frame (matte)
    "SteelGreen":   ("788678", .48, 0.0, "SmoothPlastic"),   # machine housing
    "SafetyOrange": ("D88B3D", .45, 0.0, "SmoothPlastic"),
    "BareSteel":    ("A3A8AD", .32, 1.0, "Metal"),           # tables, blades, bolts
    "Rubber":       ("2B2D2F", .85, 0.0, "Rubber"),          # pads, feet, tyres
    "Black":        ("1C1E20", .82, 0.0, "Rubber"),          # rubber mats, feet, knobs, slots
    "WallWhite":    ("E8E0D1", .70, 0.0, "SmoothPlastic"),   # blank sign faces
    "SignalRed":    ("B8382E", .40, 0.0, "SmoothPlastic"),
    "SignalGreen":  ("4E9A5B", .40, 0.0, "SmoothPlastic"),
    "ClearGuard":   ("D5E4EA", .08, 0.0, "Glass"),           # polycarbonate guard, transparent
}
TRANSPARENT = {"ClearGuard": 0.6}   # Roblox Transparency per flat material
TEXTURED = {
    # name:        (texture set, tint hex for viewport only)
    "WoodRaw":    ("WoodRaw", "DDBB8C"),
    "WoodFinish": ("WoodFinish", "C99260"),
    "WoodBench":  ("WoodBench", "D6B48A"),
    "Cardboard":  ("Cardboard", "B98C5B"),
    "BeltRubber": ("Rubber", "2B2D2F"),
}
_MATS = {}


def _image(path):
    """Reuse an already loaded image of this file (by absolute path), so the
    file never gets .001 copies, whatever relative/absolute form it has."""
    want = str(Path(path).resolve()).lower()
    for im in bpy.data.images:
        if im.filepath and str(Path(bpy.path.abspath(im.filepath)).resolve()).lower() == want:
            return im
    return bpy.data.images.load(str(path))


def _principled(mat):
    mat.use_nodes = True
    return next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")


def material(name):
    """One Blender material per HQ material name, reused across rebuilds so
    exported material names stay stable (no .001 suffixes)."""
    if name in _MATS:
        return _MATS[name]
    mat = bpy.data.materials.get("HQ_" + name) or bpy.data.materials.new("HQ_" + name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    if name in FLAT:
        hx, rough, metal, _ = FLAT[name]
        bsdf.inputs["Base Color"].default_value = lin(hx)
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metal
        mat.diffuse_color = lin(hx)
        if name in TRANSPARENT:
            bsdf.inputs["Alpha"].default_value = 1 - TRANSPARENT[name]
            try:
                mat.surface_render_method = "BLENDED"
            except (AttributeError, TypeError):
                mat.blend_method = "BLEND"
    elif name in TEXTURED:
        tset, hx = TEXTURED[name]
        mat.diffuse_color = lin(hx)

        def img(kind, colorspace):
            im = _image(TEX / f"{tset}_{kind}.png")
            im.colorspace_settings.name = colorspace
            node = nt.nodes.new("ShaderNodeTexImage")
            node.image = im
            return node
        c = img("Color", "sRGB")
        nt.links.new(c.outputs["Color"], bsdf.inputs["Base Color"])
        r = img("Roughness", "Non-Color")
        nt.links.new(r.outputs["Color"], bsdf.inputs["Roughness"])
        n = img("Normal", "Non-Color")
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(n.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
        bsdf.inputs["Metallic"].default_value = 0.0
    else:
        raise KeyError(name)
    _MATS[name] = mat
    return mat


def roblox_mapping(name):
    if name in FLAT:
        hx, rough, metal, rmat = FLAT[name]
        d = {"kind": "flat", "Color": "#" + hx, "Material": rmat}
        if name in TRANSPARENT:
            d["Transparency"] = TRANSPARENT[name]
        return d
    tset, _ = TEXTURED[name]
    return {"kind": "SurfaceAppearance", "ColorMap": f"{tset}_Color.png",
            "NormalMap": f"{tset}_Normal.png", "RoughnessMap": f"{tset}_Roughness.png"}


# --------------------------------------------------------------------- scene
def new_scene(name):
    sc = bpy.data.scenes.get(name)
    if sc is None:
        sc = bpy.data.scenes.new(name)
    bpy.context.window.scene = sc
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.scale_length = 1.0
    try:
        sc.render.engine = "BLENDER_EEVEE"
    except TypeError:
        pass
    sc.view_settings.view_transform = "AgX"
    if sc.world is None:
        w = bpy.data.worlds.new(name + "_World")
        w.use_nodes = True
        bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND")
        bg.inputs["Color"].default_value = (.42, .45, .48, 1)
        bg.inputs["Strength"].default_value = .8
        sc.world = w
    return sc


def clear_collection(name):
    """Remove only objects inside our own collection (never user objects)."""
    col = bpy.data.collections.get(name)
    if col:
        datas = []
        for ob in list(col.all_objects):
            if ob.data is not None:
                datas.append(ob.data)
            bpy.data.objects.remove(ob, do_unlink=True)
        for d in datas:                       # free names for the next build
            if d.users == 0:
                (bpy.data.meshes if isinstance(d, bpy.types.Mesh) else
                 bpy.data.lights if isinstance(d, bpy.types.Light) else
                 bpy.data.cameras).remove(d)
        for c in list(col.children_recursive):
            bpy.data.collections.remove(c)
    else:
        col = bpy.data.collections.new(name)
    if col.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(col)
    return col


# ------------------------------------------------------------- geometry core
def _uv_project(bm, grain, off, scale=1.0):
    """Planar projection per face, U along the grain axis (0/1/2) in the
    piece's local frame. End-grain faces use the two cross axes."""
    uv = bm.loops.layers.uv.verify()
    t = TILE_M / scale
    for f in bm.faces:
        n = f.normal
        a = max(range(3), key=lambda i: abs(n[i]))
        if a != grain:
            o = 3 - a - grain
            ui, vi = grain, o
        else:
            ui, vi = [i for i in range(3) if i != a]
        for l in f.loops:
            co = l.vert.co
            l[uv].uv = (co[ui] / t + off[0], co[vi] / t + off[1])


class Asset:
    """Collects geometry per (group, material) and writes one object each."""

    def __init__(self, name, collection, seed=1):
        self.name = name
        self.col = bpy.data.collections.new(name)
        collection.children.link(self.col)
        self.acc = {}           # (group, mat) -> bmesh
        self.rng = random.Random(seed)
        self.markers = {}
        self.root = bpy.data.objects.new(name, None)
        self.root.empty_display_type = "PLAIN_AXES"
        self.root.empty_display_size = .15
        self.col.objects.link(self.root)

    # -- low level
    def _acc(self, group, mat):
        key = (group, mat)
        if key not in self.acc:
            bm = bmesh.new()
            bm.loops.layers.uv.verify()
            self.acc[key] = bm
        return self.acc[key]

    def add_bm(self, piece, mat, matrix=Matrix(), group="Main", grain=0, uv_off=None, uv_scale=1.0, uv=True):
        """Project UVs in the piece frame (so grain follows the part), then
        transform into asset space and append."""
        if uv:
            off = uv_off if uv_off is not None else (self.rng.random(), self.rng.random())
            piece.normal_update()
            _uv_project(piece, grain, off, uv_scale)
        piece.transform(matrix)
        me = bpy.data.meshes.new("_tmp")
        piece.to_mesh(me)
        piece.free()
        self._acc(group, mat).from_mesh(me)
        bpy.data.meshes.remove(me)

    # -- primitives
    def box(self, size, loc, mat, bevel=.002, segs=2, grain=0, rot=None, group="Main", uv_off=None):
        """size/loc in metres, loc = box centre. rot = (rx, ry, rz) degrees."""
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        for v in bm.verts:
            v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        if bevel > 0:
            b = min(bevel, min(size) * .45)
            bmesh.ops.bevel(bm, geom=list(bm.edges) + list(bm.verts), offset=b, offset_type="OFFSET",
                            segments=segs, profile=.5, affect="EDGES", clamp_overlap=True)
        self.add_bm(bm, mat, _mx(loc, rot), group, grain, uv_off)

    def box_mm(self, mn, mx, mat, **kw):
        """Box from min/max corners."""
        size = [mx[i] - mn[i] for i in range(3)]
        loc = [(mx[i] + mn[i]) / 2 for i in range(3)]
        self.box(size, loc, mat, **kw)

    def cyl(self, r, depth, loc, mat, axis="Z", segs=16, bevel=0.0, bsegs=1, r2=None, group="Main", rot=None, grain=2):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs,
                              radius1=r, radius2=r if r2 is None else r2, depth=depth)
        if bevel > 0:
            caps = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-6]
            bmesh.ops.bevel(bm, geom=caps, offset=min(bevel, r * .45, depth * .45), offset_type="OFFSET",
                            segments=bsegs, profile=.5, affect="EDGES", clamp_overlap=True)
        base = {"Z": Matrix(), "X": Matrix.Rotation(math.radians(90), 4, "Y"),
                "Y": Matrix.Rotation(math.radians(90), 4, "X")}[axis]
        self.add_bm(bm, mat, _mx(loc, rot) @ base, group, grain)

    def poly_extrude(self, pts2d, z0, z1, mat, bevel=0.0, segs=1, matrix=Matrix(), group="Main", grain=0):
        """Extrude a closed 2D outline (XY, counter-clockwise) from z0 to z1."""
        bm = bmesh.new()
        vs0 = [bm.verts.new((x, y, z0)) for x, y in pts2d]
        vs1 = [bm.verts.new((x, y, z1)) for x, y in pts2d]
        n = len(pts2d)
        bm.faces.new(list(reversed(vs0)))
        bm.faces.new(vs1)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((vs0[i], vs0[j], vs1[j], vs1[i]))
        bm.normal_update()
        if bevel > 0:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, offset_type="OFFSET",
                            segments=segs, profile=.5, affect="EDGES", clamp_overlap=True)
        self.add_bm(bm, mat, matrix, group, grain)

    def tube_path(self, path, r, mat, segs=10, group="Main", closed=False):
        """Round bar along a polyline (handles, guard rails). Mitred joints."""
        bm = bmesh.new()
        rings = []
        P = [Vector(p) for p in path]
        n = len(P)
        for i, p in enumerate(P):
            if closed:
                t = (P[(i + 1) % n] - P[i - 1]).normalized()
            elif i == 0:
                t = (P[1] - P[0]).normalized()
            elif i == n - 1:
                t = (P[-1] - P[-2]).normalized()
            else:
                t = ((P[i + 1] - P[i]).normalized() + (P[i] - P[i - 1]).normalized()).normalized()
            ref = Vector((0, 0, 1)) if abs(t.z) < .9 else Vector((1, 0, 0))
            a = t.cross(ref).normalized()
            b = t.cross(a).normalized()
            k = 1.0
            if 0 < i < n - 1 or closed:
                d0 = (P[i] - P[i - 1]).normalized()
                k = 1.0 / max(.3, d0.dot(t))
            rings.append([bm.verts.new(p + (a * math.cos(2 * math.pi * s / segs) + b * math.sin(2 * math.pi * s / segs)) * r * k)
                          for s in range(segs)])
        m = n if closed else n - 1
        for i in range(m):
            r0, r1 = rings[i], rings[(i + 1) % n]
            for s in range(segs):
                bm.faces.new((r0[s], r0[(s + 1) % segs], r1[(s + 1) % segs], r1[s]))
        if not closed:
            bm.faces.new(list(reversed(rings[0])))
            bm.faces.new(rings[-1])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        self.add_bm(bm, mat, Matrix(), group, 0)

    def marker(self, name, loc, rot=(0, 0, 0)):
        e = bpy.data.objects.new(f"{self.name}.{name}", None)
        e.empty_display_type = "ARROWS"
        e.empty_display_size = .08
        e.location = loc
        e.rotation_euler = [math.radians(a) for a in rot]
        e.parent = self.root
        e["hq_marker"] = name
        self.col.objects.link(e)
        self.markers[name] = {"blender_m": [round(c, 5) for c in loc],
                              "roblox_studs": [round(loc[0] / .28, 4), round(loc[2] / .28, 4), round(-loc[1] / .28, 4)],
                              "rot_deg": list(rot)}

    # -- output
    def finish(self, location=(0, 0, 0)):
        objs = []
        for (group, mat), bm in sorted(self.acc.items()):
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
            name = f"{self.name}__{group}__{mat}" if group != "Main" else f"{self.name}__{mat}"
            me = bpy.data.meshes.new(name)
            bm.to_mesh(me)
            bm.free()
            me.materials.append(material(mat))
            me.shade_smooth()
            me.set_sharp_from_angle(angle=math.radians(SHARP_DEG))
            ob = bpy.data.objects.new(name, me)
            ob.parent = self.root
            ob["hq_group"] = group
            ob["hq_material"] = mat
            wn = ob.modifiers.new("WeightedNormals", "WEIGHTED_NORMAL")
            wn.mode = "FACE_AREA"
            wn.weight = 80
            wn.keep_sharp = True
            self.col.objects.link(ob)
            objs.append(ob)
        self.acc.clear()
        self.root.location = location
        return objs

    def stats(self):
        dg = bpy.context.evaluated_depsgraph_get()
        tris, parts, mats = 0, [], set()
        for ob in self.root.children:
            if ob.type != "MESH":
                continue
            ev = ob.evaluated_get(dg)
            me = ev.to_mesh()
            t = sum(len(p.vertices) - 2 for p in me.polygons)
            ev.to_mesh_clear()
            tris += t
            parts.append({"object": ob.name, "group": ob["hq_group"], "material": ob["hq_material"], "tris": t})
            mats.add(ob["hq_material"])
        bb = self.bounds()
        return {"tris": tris, "mesh_parts": len(parts), "parts": parts,
                "materials": sorted(mats), "bounds_m": bb}

    def bounds(self):
        dg = bpy.context.evaluated_depsgraph_get()
        mn = Vector((1e9,) * 3)
        mx = Vector((-1e9,) * 3)
        for ob in self.root.children:
            if ob.type != "MESH":
                continue
            ev = ob.evaluated_get(dg)
            me = ev.to_mesh()
            for v in me.vertices:
                w = ob.matrix_world @ v.co - self.root.matrix_world.translation
                mn = Vector(map(min, mn, w))
                mx = Vector(map(max, mx, w))
            ev.to_mesh_clear()
        return {"min": [round(c, 4) for c in mn], "max": [round(c, 4) for c in mx],
                "size": [round(mx[i] - mn[i], 4) for i in range(3)]}


def _mx(loc, rot):
    m = Matrix.Translation(Vector(loc))
    if rot:
        m = m @ (Matrix.Rotation(math.radians(rot[2]), 4, "Z") @ Matrix.Rotation(math.radians(rot[1]), 4, "Y")
                 @ Matrix.Rotation(math.radians(rot[0]), 4, "X"))
    return m


# --------------------------------------------------------------------- export
def export_asset(asset, out_dir):
    """Write <name>.fbx (project convention) and <name>.glb (best PBR mapping
    for the Roblox 3D importer). Root temporarily moved to the origin."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    keep = asset.root.location.copy()
    asset.root.location = (0, 0, 0)
    bpy.context.view_layer.update()
    for ob in bpy.context.view_layer.objects:
        ob.select_set(False)
    sel = [asset.root] + [c for c in asset.root.children if c.type == "MESH"]
    for ob in sel:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = asset.root
    bpy.ops.export_scene.fbx(filepath=str(out_dir / f"{asset.name}.fbx"), use_selection=True,
                             object_types={"MESH", "EMPTY"}, apply_unit_scale=False,
                             apply_scale_options="FBX_SCALE_NONE", axis_forward="-Z", axis_up="Y",
                             global_scale=1.0, use_mesh_modifiers=True, mesh_smooth_type="OFF",
                             use_custom_props=True, add_leaf_bones=False, bake_anim=False,
                             path_mode="RELATIVE", embed_textures=False)   # maps live in ../textures
    bpy.ops.export_scene.gltf(filepath=str(out_dir / f"{asset.name}.glb"), export_format="GLB",
                              use_selection=True, use_active_scene=True, export_apply=True, export_yup=True,
                              export_extras=True, export_texcoords=True, export_normals=True)
    for ob in sel:
        ob.select_set(False)
    asset.root.location = keep
    bpy.context.view_layer.update()


def write_manifest(path, assets, notes=None):
    data = {"generated_by": "assets/hq/tools", "units": "metres, Blender Z up, front +Y",
            "roblox_axes": "(X,Y,Z)->(X,Z,-Y), 25/7 studs per metre applied once in Studio",
            "tile_m": TILE_M, "assets": {}, "materials": {}}
    used = set()
    for a in assets:
        st = a.stats()
        used.update(st["materials"])
        data["assets"][a.name] = {**st, "markers": a.markers}
    for m in sorted(used):
        data["materials"][m] = roblox_mapping(m)
    if notes:
        data["notes"] = notes
    Path(path).write_text(json.dumps(data, indent=1, ensure_ascii=False), encoding="utf-8")
    return data
