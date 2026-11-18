"""P03-03 Gebaeudeecke01 - building corner / bay cutaway sample (Blender 5.1).

Self-contained bpy script. Builds ONLY a new owned scene, validates geometry,
writes .blend (owned scene only), FBX exports, JSON checks/manifest and PNG renders.

Package dir = parent of this tools/ folder, or env P03_PACKAGE_DIR.
Run inside Blender:
    exec(compile(open(p, encoding="utf-8").read(), p, "exec"), {"__file__": p, "__name__": "__main__"})
Optional global P03_STAGES (set in exec globals) = subset of
    ("build", "regress", "check", "save", "export", "roundtrip", "render"); default all.

Coordinates: the reference sheet (assets/p03-reference/reference.md) uses Roblox
target coordinates in metres (X right, Y up, -Z front, building runs +Z).
Blender: metres, +Z up, +Y front. Mapping (Blender X,Y,Z) -> (Roblox X,Z,-Y),
i.e. Blender = (Rx, -Rz, Ry). All geometry below is authored in Roblox coords
through R(); all checks are reported in Roblox coords.
Pivot (D-G0): outer front-left wall corner on the ground = (0,0,0).
"""
import bpy, bmesh, os, json, math, time
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

# ---------------------------------------------------------------- paths
_here = globals().get("__file__")
PKG = os.environ.get("P03_PACKAGE_DIR") or os.path.dirname(os.path.dirname(os.path.abspath(_here)))
EXPORTS = os.path.join(PKG, "exports")
RENDERS = os.path.join(PKG, "renders")
BLEND_PATH = os.path.join(PKG, "p03-03-gebaeudeecke01-v01.blend")
CHECKS_PATH = os.path.join(PKG, "checks.json")
MANIFEST_PATH = os.path.join(PKG, "manifest.json")
ROUNDTRIP_PATH = os.path.join(PKG, "fbx-roundtrip.json")
SCENE_NAME = "P03-03_Gebaeudeecke01"
OWN = "p03_03_owned"
EPS = 1e-5

STAGES = globals().get("P03_STAGES") or ("build", "regress", "check", "save", "export", "roundtrip", "render")

# ---------------------------------------------------------------- reference values (Roblox metres)
WALL_T = 0.24
WALL_TOP = 2.90
PLATE_TOP = 3.00
BAY_W = 4.80
BAY_D = 3.00
RIDGE_X = 2.40
EAVE = 0.30            # side overhang (G6)
VERGE = 0.25           # front/rear overhang (G7)
BOARD = 0.020          # fascia/verge thickness
RAFTER_D, RAFTER_W = 0.16, 0.08
SHEATH_B, SHEATH_T, SKIN_T = 0.160, 0.184, 0.196
RAFTER_AXES = (0.12, 1.12, 2.12, 2.88)


def U(x):
    """Rafter underside line (G4)."""
    return 4.26 - 0.50 * abs(x - RIDGE_X)


def R(x, y, z):
    """Roblox target coords -> Blender coords."""
    return Vector((x, -z, y))


def toR(v):
    """Blender coords -> Roblox target coords."""
    return (v.x, v.z, -v.y)


def mx(x):
    return 2 * RIDGE_X - x  # mirror about ridge plane


# ---------------------------------------------------------------- utilities
def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [((v / 12.92) if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4) for v in c] + [1.0]


def set_input(node, names, value):
    for n in names:
        s = node.inputs.get(n)
        if s is not None:
            try:
                s.default_value = value
                return True
            except Exception:
                pass
    return False


def enum_ids(rna_owner, prop):
    return [i.identifier for i in rna_owner.bl_rna.properties[prop].enum_items]


class OwnershipError(RuntimeError):
    pass


def cleanup_owned():
    """Remove ONLY data created by this script. Ownership is verified before ANY deletion:
    a scene named SCENE_NAME without the owner flag, or an owned scene that contains objects
    not created by this script, aborts with OwnershipError and nothing is removed."""
    sc = bpy.data.scenes.get(SCENE_NAME)
    if sc is not None:
        if not sc.get(OWN):
            raise OwnershipError(f"scene '{SCENE_NAME}' exists but is not owned by P03-03; nothing deleted")
        foreign = [o.name for o in sc.objects if not o.get(OWN)]
        if foreign:
            raise OwnershipError(f"owned scene '{SCENE_NAME}' contains foreign objects {foreign}; nothing deleted")
    if sc is not None:
        for o in list(sc.objects):
            if o.get(OWN):
                data = o.data
                bpy.data.objects.remove(o, do_unlink=True)
                if data is not None and data.users == 0:
                    for coll in (bpy.data.meshes, bpy.data.cameras, bpy.data.lights):
                        if data.name in coll and coll[data.name] == data:
                            coll.remove(data)
                            break
        bpy.data.scenes.remove(sc)
    for coll in (bpy.data.collections, bpy.data.materials, bpy.data.worlds, bpy.data.meshes,
                 bpy.data.cameras, bpy.data.lights):
        for d in list(coll):
            if d.get(OWN) and d.users == 0:
                coll.remove(d)


# ---------------------------------------------------------------- materials
PALETTE = {
    "WallPaint": ("#E8E0D1", 0.85, 0.0),
    "WoodRaw": ("#C59664", 0.70, 0.0),
    "MachineSteel": ("#34383C", 0.45, 0.6),
    "MutedGreen": ("#788678", 0.65, 0.0),   # painted metal; no metallic so the palette green stays readable
    "Glass": ("#B9CCD0", 0.05, 0.0),
    "Seal": ("#202224", 0.80, 0.0),
}


def make_materials():
    mats = {}
    for key, (hexc, rough, metal) in PALETTE.items():
        m = bpy.data.materials.new("P03_" + key)
        m[OWN] = True
        try:
            m.use_nodes = True
        except Exception:
            pass
        col = srgb(hexc)
        m.diffuse_color = col
        bsdf = None
        if m.node_tree is not None:
            bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is not None:
            set_input(bsdf, ["Base Color", "Color"], col)
            set_input(bsdf, ["Roughness"], rough)
            set_input(bsdf, ["Metallic"], metal)
            if key == "Glass":
                set_input(bsdf, ["Alpha"], 0.45)
                set_input(bsdf, ["Specular IOR Level", "Specular"], 0.6)
        if key == "Glass":
            try:
                if "BLENDED" in enum_ids(m, "surface_render_method"):
                    m.surface_render_method = "BLENDED"
            except Exception:
                pass
        mats[key] = m
    return mats


# ---------------------------------------------------------------- mesh construction
def box_uv(bm):
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        a, b = [(1, 2), (0, 2), (0, 1)][ax]
        for l in f.loops:
            l[uv].uv = (l.vert.co[a], l.vert.co[b])


class Builder:
    def __init__(self, scene, coll, root, mats):
        self.scene, self.coll, self.root, self.mats = scene, coll, root, mats
        self.parts = {}   # name -> object
        self.meta = {}    # name -> dict(group, expected bounds etc.)

    def solid(self, name, verts_r, faces, mat, group, triangulate=False, bevel=None, exp=None):
        bm = bmesh.new()
        bv = [bm.verts.new(R(*v)) for v in verts_r]
        for f in faces:
            bm.faces.new([bv[i] for i in f])
        bm.normal_update()
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        if triangulate:
            ng = [f for f in bm.faces if len(f.verts) > 4]
            if ng:
                bmesh.ops.triangulate(bm, faces=ng)
        if bevel:
            sel_fn, off = bevel
            edges = [e for e in bm.edges if sel_fn(e)]
            if edges:
                vs = list({v for e in edges for v in e.verts})
                bmesh.ops.bevel(bm, geom=edges + vs, offset=off, segments=1, profile=0.5,
                                affect="EDGES", clamp_overlap=True)
        bm.normal_update()
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        box_uv(bm)
        me = bpy.data.meshes.new("Gebaeudeecke01_" + name)
        me[OWN] = True
        bm.to_mesh(me)
        bm.free()
        me.materials.append(self.mats[mat])
        ob = bpy.data.objects.new("Gebaeudeecke01_" + name, me)
        ob[OWN] = True
        ob["p03_group"] = group
        self.coll.objects.link(ob)
        ob.parent = self.root
        self.parts[name] = ob
        self.meta[name] = {"group": group, "material": "P03_" + mat, "expected_bounds_roblox": exp}
        return ob

    # -- primitives (all Roblox coords)
    def hexa(self, name, v8, mat, group, **kw):
        faces = [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        return self.solid(name, v8, faces, mat, group, **kw)

    def box(self, name, lo, hi, mat, group, **kw):
        (x0, y0, z0), (x1, y1, z1) = lo, hi
        v = [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1),
             (x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)]
        kw.setdefault("exp", [list(lo), list(hi)])
        return self.hexa(name, v, mat, group, **kw)

    def loft_z(self, name, prof_a, za, prof_b, zb, mat, group, **kw):
        """Two XY profiles of equal topology at z=za and z=zb (allows mitred ends)."""
        n = len(prof_a)
        v = [(x, y, za) for x, y in prof_a] + [(x, y, zb) for x, y in prof_b]
        faces = [tuple(range(n)), tuple(range(n, 2 * n))]
        faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
        kw.setdefault("triangulate", n > 4)
        return self.solid(name, v, faces, mat, group, **kw)

    def prism_z(self, name, prof, z0, z1, mat, group, **kw):
        return self.loft_z(name, prof, z0, prof, z1, mat, group, **kw)

    def grid_voxel(self, name, xs, ys, zs, solid_fn, mat, group, **kw):
        """3D cell grid; solid_fn(i,j,k) True=material. Boundary faces only (closed all-quad
        manifold as long as no two solid cells touch along an edge only). Used for stepped profiles."""
        n = (len(xs) - 1, len(ys) - 1, len(zs) - 1)
        S = lambda i, j, k: 0 <= i < n[0] and 0 <= j < n[1] and 0 <= k < n[2] and solid_fn(i, j, k)
        g = (xs, ys, zs)
        idx, verts = {}, []

        def vid(c):
            if c not in idx:
                idx[c] = len(verts)
                verts.append(tuple(g[a][c[a]] for a in range(3)))
            return idx[c]

        faces = []
        for ax in range(3):
            u, w = [a for a in range(3) if a != ax]
            for p in range(n[ax] + 1):
                for a in range(n[u]):
                    for b in range(n[w]):
                        lo = [0, 0, 0]; lo[ax] = p - 1; lo[u] = a; lo[w] = b
                        hi = list(lo); hi[ax] = p
                        if S(*lo) == S(*hi):
                            continue
                        quad = []
                        for du, dw in ((0, 0), (1, 0), (1, 1), (0, 1)):
                            c = [0, 0, 0]; c[ax] = p; c[u] = a + du; c[w] = b + dw
                            quad.append(vid(tuple(c)))
                        faces.append(tuple(quad))
        return self.solid(name, verts, faces, mat, group, **kw)

    def grid_slab(self, name, xs, ys, z0, z1, solid_fn, mat, group, **kw):
        """Slab in the XY plane from z0..z1 made of grid cells; solid_fn(i,j) True=material.
        Produces a closed all-quad manifold with exact holes (no booleans)."""
        nx, ny = len(xs) - 1, len(ys) - 1
        S = lambda i, j: 0 <= i < nx and 0 <= j < ny and solid_fn(i, j)
        idx, verts = {}, []

        def vid(i, j, k):
            key = (i, j, k)
            if key not in idx:
                idx[key] = len(verts)
                verts.append((xs[i], ys[j], (z0, z1)[k]))
            return idx[key]

        faces = []
        for i in range(nx):
            for j in range(ny):
                if S(i, j):
                    for k in (0, 1):
                        faces.append((vid(i, j, k), vid(i + 1, j, k), vid(i + 1, j + 1, k), vid(i, j + 1, k)))
        for i in range(nx + 1):          # side faces on x = xs[i]
            for j in range(ny):
                if S(i - 1, j) != S(i, j):
                    faces.append((vid(i, j, 0), vid(i, j + 1, 0), vid(i, j + 1, 1), vid(i, j, 1)))
        for j in range(ny + 1):          # side faces on y = ys[j]
            for i in range(nx):
                if S(i, j - 1) != S(i, j):
                    faces.append((vid(i, j, 0), vid(i + 1, j, 0), vid(i + 1, j, 1), vid(i, j, 1)))
        return self.solid(name, verts, faces, mat, group, **kw)


def near(a, b, t=EPS):
    return abs(a - b) <= t


def edge_on(e, fn):
    return all(fn(toR(v.co)) for v in e.verts)


# ---------------------------------------------------------------- build
def build():
    cleanup_owned()
    sc = bpy.data.scenes.new(SCENE_NAME)
    sc[OWN] = True
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.scale_length = 1.0
    try:
        sc.unit_settings.length_unit = "METERS"
    except Exception:
        pass
    model = bpy.data.collections.new("P03-03_Model")
    pres = bpy.data.collections.new("P03-03_Presentation")
    for c in (model, pres):
        c[OWN] = True
        sc.collection.children.link(c)

    root = bpy.data.objects.new("Gebaeudeecke01", None)
    root[OWN] = True
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.5
    model.objects.link(root)

    mats = make_materials()
    B = Builder(sc, model, root, mats)
    T, W, D = WALL_T, BAY_W, BAY_D

    # G1 walls ---------------------------------------------------------
    xs = [0.0, 0.96, 1.00, 2.20, 2.24, W]
    ys = [0.0, 0.96, 1.00, 2.20, WALL_TOP]

    def front_solid(i, j):
        if j == 1 and 1 <= i <= 3:   # sill slot X 0.96..2.24, Y 0.96..1.00
            return False
        if j == 2 and i == 2:        # window opening X 1.00..2.20, Y 1.00..2.20
            return False
        return True

    corner = lambda e: edge_on(e, lambda p: near(p[2], 0.0) and (near(p[0], 0.0) or near(p[0], W)))
    B.grid_slab("FrontWall", xs, ys, 0.0, T, front_solid, "WallPaint", "wall",
                bevel=(corner, 0.005), exp=[[0, 0, 0], [W, WALL_TOP, T]])
    B.box("SideWall_L", (0, 0, T), (T, WALL_TOP, D), "WallPaint", "wall")
    B.box("SideWall_R", (W - T, 0, T), (W, WALL_TOP, D), "WallPaint", "wall")

    # G2 ring/wall plate ----------------------------------------------
    B.box("Plate_Front", (0, WALL_TOP, 0), (W, PLATE_TOP, T), "WoodRaw", "bearing")
    B.box("Plate_L", (0, WALL_TOP, T), (T, PLATE_TOP, D), "WoodRaw", "bearing")
    B.box("Plate_R", (W - T, WALL_TOP, T), (W, PLATE_TOP, D), "WoodRaw", "bearing")

    # G3 wedges + gable infill ----------------------------------------
    B.prism_z("Wedge_L", [(0, PLATE_TOP), (T, PLATE_TOP), (T, U(T)), (0, U(0))], T, D, "WoodRaw", "bearing",
              exp=[[0, PLATE_TOP, T], [T, U(T), D]])
    B.prism_z("Wedge_R", [(W - T, PLATE_TOP), (W, PLATE_TOP), (W, U(W)), (W - T, U(W - T))], T, D, "WoodRaw",
              "bearing", exp=[[W - T, PLATE_TOP, T], [W, U(W - T), D]])
    B.prism_z("GableFill", [(0, PLATE_TOP), (W, PLATE_TOP), (W, U(W)), (RIDGE_X, U(RIDGE_X)), (0, U(0))],
              0, T, "WallPaint", "wall", exp=[[0, PLATE_TOP, 0], [W, U(RIDGE_X), T]])

    # G4 rafters, two halves per pair, plumb-cut mitre at ridge ---------
    xe = -EAVE + BOARD   # -0.28, rafter foot butts fascia inner face
    for k, zc in enumerate(RAFTER_AXES, 1):
        z0, z1 = zc - RAFTER_W / 2, zc + RAFTER_W / 2
        pl = [(xe, U(xe)), (RIDGE_X, U(RIDGE_X)), (RIDGE_X, U(RIDGE_X) + RAFTER_D), (xe, U(xe) + RAFTER_D)]
        pr = [(mx(x), y) for x, y in pl]
        B.prism_z(f"Rafter{k}_L", pl, z0, z1, "WoodRaw", "rafter",
                  exp=[[xe, U(xe), z0], [RIDGE_X, U(RIDGE_X) + RAFTER_D, z1]])
        B.prism_z(f"Rafter{k}_R", pr, z0, z1, "WoodRaw", "rafter",
                  exp=[[RIDGE_X, U(xe), z0], [mx(xe), U(RIDGE_X) + RAFTER_D, z1]])

    # G5 sheathing + metal skin, two roof planes meeting at X=2.40 ----------
    zs0, zs1 = -VERGE + BOARD, D + VERGE - BOARD     # sheathing butts verge boards
    sl = [(xe, U(xe) + SHEATH_B), (RIDGE_X, U(RIDGE_X) + SHEATH_B), (RIDGE_X, U(RIDGE_X) + SHEATH_T),
          (xe, U(xe) + SHEATH_T)]
    B.prism_z("Sheathing_L", sl, zs0, zs1, "WoodRaw", "roof",
              exp=[[xe, U(xe) + SHEATH_B, zs0], [RIDGE_X, U(RIDGE_X) + SHEATH_T, zs1]])
    B.prism_z("Sheathing_R", [(mx(x), y) for x, y in sl], zs0, zs1, "WoodRaw", "roof",
              exp=[[RIDGE_X, U(xe) + SHEATH_B, zs0], [mx(xe), U(RIDGE_X) + SHEATH_T, zs1]])
    # D-G21: sheathing AND metal skin end at the inner face of the 0.020 edge boards
    # (X -0.28..5.08, Z -0.23..3.23). The G5 roof envelope X -0.30..5.10 / Z -0.25..3.25 is closed by
    # the fascia/verge boards, whose top lies in the skin top plane U+0.196 (coplanar, butt joint,
    # no overlapping volume). This keeps the exact G6/G7 board profile (0.200 high, top flush).
    xo = -EAVE
    zk0, zk1 = -VERGE, D + VERGE
    kl = [(xe, U(xe) + SHEATH_T), (RIDGE_X, U(RIDGE_X) + SHEATH_T), (RIDGE_X, U(RIDGE_X) + SKIN_T),
          (xe, U(xe) + SKIN_T)]
    B.prism_z("Skin_L", kl, zs0, zs1, "MutedGreen", "roof",
              exp=[[xe, U(xe) + SHEATH_T, zs0], [RIDGE_X, U(RIDGE_X) + SKIN_T, zs1]])
    B.prism_z("Skin_R", [(mx(x), y) for x, y in kl], zs0, zs1, "MutedGreen", "roof",
              exp=[[RIDGE_X, U(xe) + SHEATH_T, zs0], [mx(xe), U(RIDGE_X) + SKIN_T, zs1]])

    # G6 eaves fascia: exact reference profile, bottom U(-0.30)-0.004 = 2.906 (horizontal),
    # top in the metal-skin top plane U+0.196 -> 0.200 high at the outer face; 45deg mitred ends ----
    yb = U(xo) - 0.004
    for side in ("L", "R"):
        f = (lambda x: x) if side == "L" else mx
        v = [(f(xo), yb, zk0), (f(xe), yb, zs0), (f(xe), yb, zs1), (f(xo), yb, zk1),
             (f(xo), U(xo) + SKIN_T, zk0), (f(xe), U(xe) + SKIN_T, zs0),
             (f(xe), U(xe) + SKIN_T, zs1), (f(xo), U(xo) + SKIN_T, zk1)]
        lo = [min(f(xo), f(xe)), yb, zk0]
        hi = [max(f(xo), f(xe)), U(xe) + SKIN_T, zk1]
        B.hexa(f"Fascia_{side}", v, "MachineSteel", "edge", exp=[lo, hi])

    # G7 verge boards front/rear: U-0.004 .. U+0.196 (0.200 vertical), follow roof contour, mitred ----
    po = [(xo, U(xo) - 0.004), (RIDGE_X, U(RIDGE_X) - 0.004), (mx(xo), U(xo) - 0.004),
          (mx(xo), U(xo) + SKIN_T), (RIDGE_X, U(RIDGE_X) + SKIN_T), (xo, U(xo) + SKIN_T)]
    pi = [(xe, U(xe) - 0.004), (RIDGE_X, U(RIDGE_X) - 0.004), (mx(xe), U(xe) - 0.004),
          (mx(xe), U(xe) + SKIN_T), (RIDGE_X, U(RIDGE_X) + SKIN_T), (xe, U(xe) + SKIN_T)]
    B.loft_z("Verge_Front", po, zk0, pi, zs0, "MachineSteel", "edge",
             exp=[[xo, yb, zk0], [mx(xo), U(RIDGE_X) + SKIN_T, zs0]])
    B.loft_z("Verge_Rear", pi, zs1, po, zk1, "MachineSteel", "edge",
             exp=[[xo, yb, zs1], [mx(xo), U(RIDGE_X) + SKIN_T, zk1]])

    # G8 ridge cap + end caps -------------------------------------------
    cap_lo = [(2.28, 4.396), (2.40, 4.494), (2.52, 4.396)]
    cap = cap_lo + [(x, y + 0.006) for x, y in reversed(cap_lo)]
    B.prism_z("RidgeCap", cap, zk0, zk1, "MachineSteel", "ridge", triangulate=True,
              exp=[[2.28, 4.396, zk0], [2.52, 4.500, zk1]])
    dart = [(2.28, 4.396), (2.40, U(RIDGE_X) + SKIN_T), (2.52, 4.396), (2.40, 4.494)]
    B.prism_z("RidgeEnd_Front", dart, zk0, zk0 + 0.006, "MachineSteel", "ridge", triangulate=True,
              exp=[[2.28, 4.396, zk0], [2.52, 4.494, zk0 + 0.006]])
    B.prism_z("RidgeEnd_Rear", dart, zk1 - 0.006, zk1, "MachineSteel", "ridge", triangulate=True,
              exp=[[2.28, 4.396, zk1 - 0.006], [2.52, 4.494, zk1]])
    # triangulate=True on a 4-gon dart: force (concave) - handled below
    for nm in ("RidgeEnd_Front", "RidgeEnd_Rear"):
        me = B.parts[nm].data
        bm = bmesh.new(); bm.from_mesh(me)
        concave = [f for f in bm.faces if len(f.verts) == 4 and abs(f.normal.y) > 0.99]
        bmesh.ops.triangulate(bm, faces=concave)
        bm.normal_update(); bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        bm.to_mesh(me); bm.free()

    # G9-G12 window ---------------------------------------------------------
    # Stepped frame profile with a real glazing rebate (D-G22):
    #   outer section  Z 0.040..0.113: light opening X/Y 1.07..2.13 (= 1.06, profile 0.06, rebate side wall)
    #   rear stop lip  Z 0.113..0.180: clear 1.08..2.12 (= 1.04); its front face Z=0.113 is the rebate
    #   shoulder the glass (Z 0.107..0.113, 1.07..2.13) rests on with a 0.010 band all round.
    fx = [1.01, 1.07, 1.08, 2.12, 2.13, 2.19]
    fz = [0.04, 0.113, 0.18]

    def frame_solid(i, j, k):
        if k == 0:
            return not (1 <= i <= 3 and 1 <= j <= 3)
        return not (i == 2 and j == 2)
    # only convex edges (a bevel on concave edges would ADD material into the opening), and never the
    # rebate shoulder edges in plane Z=0.113, so the glass seat stays a full flat contact band
    sharp = lambda e: (len(e.link_faces) == 2 and e.calc_face_angle(0) > 0.5 and e.is_convex
                       and not edge_on(e, lambda p: near(p[2], 0.113)))
    B.grid_voxel("WindowFrame", fx, fx, fz, frame_solid, "MutedGreen",
                 "window", bevel=(sharp, 0.003), exp=[[1.01, 1.01, 0.04], [2.19, 2.19, 0.18]])
    sx = [1.00, 1.01, 2.19, 2.20]
    B.grid_slab("WindowSeal", sx, sx, 0.06, 0.16, lambda i, j: not (i == 1 and j == 1), "Seal", "window",
                exp=[[1.00, 1.00, 0.06], [2.20, 2.20, 0.16]])
    B.box("Glass", (1.07, 1.07, 0.107), (2.13, 2.13, 0.113), "Glass", "window")
    sill_front = lambda e: edge_on(e, lambda p: near(p[2], -0.04) and (near(p[1], 0.96) or near(p[1], 1.00)))
    B.box("Sill", (0.96, 0.96, -0.04), (2.24, 1.00, T), "MachineSteel", "window", bevel=(sill_front, 0.006))

    # 1 m control cube (own export, hidden in presentation) -----------------
    cc = bpy.data.meshes.new("ControlCube_1m")
    cc[OWN] = True
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=Vector((0, 0, 0.5)))
    bm.to_mesh(cc); bm.free()
    cco = bpy.data.objects.new("ControlCube_1m", cc)
    cco[OWN] = True
    cco.location = (-3.0, 0.0, 0.0)
    pres.objects.link(cco)
    cco.hide_render = True

    setup_presentation(sc, pres)
    sc["p03_meta"] = json.dumps(B.meta)
    return sc


# ---------------------------------------------------------------- presentation
def look_at(ob, loc, target):
    ob.location = loc
    d = Vector(target) - Vector(loc)
    ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


CAMERAS = {
    # name: (ortho_scale or None, lens, Blender loc, Blender target, resolution)
    "front": (7.6, None, (2.4, 14.0, 2.25), (2.4, 0.0, 2.25), (1280, 960)),
    "side_left": (7.4, None, (-14.0, -1.5, 2.25), (0.0, -1.5, 2.25), (1280, 960)),
    "top": (7.2, None, (2.4, -1.5, 16.0), (2.4, -1.4999, 0.0), (1280, 960)),
    "three_quarter": (None, 32, (-5.2, 7.6, 5.0), (2.2, -1.3, 2.1), (1280, 960)),
    "rear_cutaway": (None, 30, (5.6, -9.4, 3.2), (2.3, -1.2, 2.4), (1280, 960)),
    # detail views (Blender coords); comments give Roblox target
    "detail_gj2_bearing": (None, 35, (1.45, -3.75, 2.35), (0.12, -2.95, 3.08), (1024, 768)),   # left wall head from inside rear
    "detail_gj4_eaves_verge": (None, 50, (-1.3, 1.4, 2.4), (-0.30, 0.25, 3.0), (1024, 768)),  # front-left eaves/verge mitre
    "detail_gj5_ridge": (None, 50, (2.95, 1.05, 4.75), (2.4, 0.2, 4.45), (1024, 768)),        # ridge front end
    "detail_gj6_window": (None, 45, (2.0, 0.95, 1.5), (1.0, -0.06, 1.0), (1024, 768)),        # reveal X=1.00, sill, frame
    "detail_gj6_window_rear": (None, 40, (2.1, -1.5, 1.9), (1.4, -0.1, 1.5), (1024, 768)),    # inner reveal 0.06
    # rebate close-ups at the lower-left glass corner (Roblox 1.07;1.07)
    "detail_gj6_rebate_front": (None, 60, (1.42, 0.38, 1.40), (1.075, -0.10, 1.075), (1024, 768)),
    "detail_gj6_rebate_rear": (None, 60, (1.40, -0.62, 1.38), (1.08, -0.12, 1.08), (1024, 768)),
    # vertical section through the bottom rail at X=1.60 (camera clip plane = cut), looking -X
    "detail_gj6_section": (0.40, None, (2.10, -0.10, 1.07), (1.60, -0.10, 1.07), (1024, 768)),
}


CAM_CLIP = {"detail_gj6_section": 0.50}   # clip plane at X=1.60 -> section through bottom rail, glass, sill, wall


def setup_presentation(sc, pres):
    try:
        sc.render.engine = "BLENDER_EEVEE"
    except TypeError as ex:
        print("engine:", ex)
    try:
        sc.eevee.taa_render_samples = 48
    except Exception:
        pass
    try:
        sc.view_settings.view_transform = "Standard"
    except Exception:
        pass
    sc.render.image_settings.file_format = "PNG"
    w = bpy.data.worlds.new("P03-03_World")
    w[OWN] = True
    try:
        w.use_nodes = True
    except Exception:
        pass
    bg = None
    if w.node_tree is not None:
        bg = next((n for n in w.node_tree.nodes if n.type == "BACKGROUND"), None)
    if bg is not None:
        bg.inputs[0].default_value = (0.62, 0.66, 0.70, 1.0)
        bg.inputs[1].default_value = 0.9
    w.color = (0.62, 0.66, 0.70)
    sc.world = w

    ld = bpy.data.lights.new("P03-03_Sun", "SUN")
    ld[OWN] = True
    ld.energy = 2.6
    ld.angle = math.radians(4)
    lo = bpy.data.objects.new("P03-03_Sun", ld)
    lo[OWN] = True
    lo.rotation_euler = (math.radians(50), math.radians(8), math.radians(-35))
    pres.objects.link(lo)
    fd = bpy.data.lights.new("P03-03_Fill", "SUN")   # weak counter light so joint faces separate
    fd[OWN] = True
    fd.energy = 0.9
    fd.angle = math.radians(20)
    try:
        fd.use_shadow = False
    except Exception:
        pass
    fo = bpy.data.objects.new("P03-03_Fill", fd)
    fo[OWN] = True
    fo.rotation_euler = (math.radians(-60), math.radians(0), math.radians(150))
    pres.objects.link(fo)
    try:
        sc.render.line_thickness_mode = "ABSOLUTE"
        sc.render.line_thickness = 1.0
        ls = sc.view_layers[0].freestyle_settings.linesets
        lset = ls[0] if len(ls) else ls.new("P03_lines")
        for a in ("select_silhouette", "select_border", "select_crease", "select_material_boundary"):
            setattr(lset, a, True)
        lset.linestyle.color = (0.08, 0.08, 0.09)
        lset.linestyle.thickness = 1.2
    except Exception as ex:
        print("freestyle setup:", ex)

    gm = bpy.data.meshes.new("P03-03_Ground")
    gm[OWN] = True
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=12.0)
    bmesh.ops.translate(bm, verts=bm.verts[:], vec=Vector((2.4, -1.5, -0.002)))
    bm.to_mesh(gm); bm.free()
    gmat = bpy.data.materials.new("P03-03_Ground")
    gmat[OWN] = True
    gmat.diffuse_color = (0.30, 0.31, 0.30, 1)
    if gmat.node_tree is not None:
        b = next((n for n in gmat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if b is not None:
            set_input(b, ["Base Color"], (0.30, 0.31, 0.30, 1))
            set_input(b, ["Roughness"], 0.9)
    gm.materials.append(gmat)
    go = bpy.data.objects.new("P03-03_Ground", gm)
    go[OWN] = True
    pres.objects.link(go)

    for name, (osc, lens, loc, tgt, res) in CAMERAS.items():
        cd = bpy.data.cameras.new("Cam_" + name)
        cd[OWN] = True
        if osc:
            cd.type = "ORTHO"
            cd.ortho_scale = osc
        else:
            cd.lens = lens
        cd.clip_start, cd.clip_end = CAM_CLIP.get(name, 0.02), 100
        co = bpy.data.objects.new("Cam_" + name, cd)
        co[OWN] = True
        look_at(co, loc, tgt)
        pres.objects.link(co)
    sc.camera = sc.objects["Cam_three_quarter"]


# ---------------------------------------------------------------- validation
def model_parts(sc):
    return sorted([o for o in sc.objects if o.get(OWN) and o.type == "MESH" and o.get("p03_group")],
                  key=lambda o: o.name)


def short(o):
    return o.name.split(".")[0].replace("Gebaeudeecke01_", "")


def world_verts_R(o):
    m = o.matrix_world
    return [toR(m @ v.co) for v in o.data.vertices]


def bounds(vs):
    return [[min(v[i] for v in vs) for i in range(3)], [max(v[i] for v in vs) for i in range(3)]]


def mesh_health(o):
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.transform(o.matrix_world)
    finite = all(all(math.isfinite(c) for c in v.co) for v in bm.verts)
    nonman = sum(1 for e in bm.edges if len(e.link_faces) != 2)
    # consistent winding: each manifold edge traversed in opposite directions
    bad_wind = 0
    for e in bm.edges:
        if len(e.link_faces) == 2:
            dirs = []
            for f in e.link_faces:
                for l in f.loops:
                    if l.edge == e:
                        dirs.append(l.vert == e.verts[0])
            if dirs[0] == dirs[1]:
                bad_wind += 1
    loose = sum(1 for v in bm.verts if not v.link_faces)
    tris = bm.calc_loop_triangles()
    vol = 0.0
    for t in tris:
        a, b, c = (l.vert.co for l in t)
        vol += a.dot(b.cross(c)) / 6.0
    degenerate = sum(1 for f in bm.faces if f.calc_area() < 1e-9)
    res = dict(finite=finite, non_manifold_edges=nonman, bad_winding_edges=bad_wind, loose_verts=loose,
               triangles=len(tris), signed_volume=vol, degenerate_faces=degenerate)
    bm.free()
    return res


def bvh_of(o):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.transform(o.matrix_world)
    t = BVHTree.FromBMesh(bm)
    pts = []
    bm.faces.ensure_lookup_table()
    for f in bm.faces:
        c = f.calc_center_median()
        n = f.normal
        pts.append(c - n * 0.0005)
        for v in f.verts:
            pts.append(v.co.lerp(c, 0.08) - n * 0.0005)
    # dense barycentric samples (~0.08 m spacing) on every triangle, 0.5 mm below the surface
    for lt in bm.calc_loop_triangles():
        a, b, c = (l.vert.co for l in lt)
        n = lt[0].face.normal
        k = min(30, max(2, math.ceil(max((b - a).length, (c - b).length, (a - c).length) / 0.08)))
        for i in range(1, k):
            for j in range(1, k - i):
                u, w = i / k, j / k
                pts.append(a + (b - a) * u + (c - a) * w - n * 0.0005)
    bb = [Vector([min(v.co[i] for v in bm.verts) for i in range(3)]),
          Vector([max(v.co[i] for v in bm.verts) for i in range(3)])]
    bm.free()
    return t, pts, bb


def inside(tree, p, d):
    n, o = 0, Vector(p)
    for _ in range(64):
        hit = tree.ray_cast(o, d, 100.0)
        if hit[0] is None:
            break
        n += 1
        o = hit[0] + d * 1e-6
    return n % 2 == 1


def run_checks(sc):
    checks = []

    def chk(cid, desc, expected, measured, ok):
        checks.append({"id": cid, "check": desc, "expected": expected, "measured": measured, "pass": bool(ok)})

    meta = json.loads(sc.get("p03_meta", "{}"))
    parts = model_parts(sc)
    P = {short(o): o for o in parts}
    V = {k: world_verts_R(o) for k, o in P.items()}
    BB = {k: bounds(v) for k, v in V.items()}
    r3 = lambda b: [[round(c, 5) for c in b[0]], [round(c, 5) for c in b[1]]]

    def bb_eq(a, b, t=1e-4):
        return all(abs(a[i][j] - b[i][j]) <= t for i in range(2) for j in range(3))

    # units / pivot / transforms
    us = sc.unit_settings
    chk("UNIT", "scene metric, scale_length 1.0", "METRIC/1.0", f"{us.system}/{us.scale_length}",
        us.system == "METRIC" and near(us.scale_length, 1.0))
    root = sc.objects.get("Gebaeudeecke01")
    chk("PIVOT", "root Gebaeudeecke01 at (0,0,0), identity transform (D-G0 outer front-left corner at ground)",
        [0, 0, 0], list(root.location) if root else None,
        root is not None and root.matrix_world == Matrix.Identity(4))
    badtf = [short(o) for o in parts if o.matrix_world != Matrix.Identity(4) or o.parent != root]
    chk("PART_TF", "all parts parented to root, identity world matrix (geometry authored in place)", [], badtf,
        not badtf)
    mods = [short(o) for o in parts if len(o.modifiers)]
    chk("NO_MODIFIERS", "no part has modifiers, so the measured mesh data IS the evaluated/exported mesh", [], mods,
        not mods)
    texts = [o.name for o in sc.objects if o.type == "FONT"]
    chk("NO_TEXT", "no text/language meshes in scene", [], texts, not texts)

    allv = [v for vs in V.values() for v in vs]
    ab = bounds(allv)
    chk("BOUNDS", "overall Roblox bounds = X -0.30..5.10, Y 0..4.50, Z -0.25..3.25 (5.40 x 4.50 x 3.50)",
        [[-0.30, 0, -0.25], [5.10, 4.50, 3.25]], r3(ab), bb_eq(ab, [[-0.30, 0, -0.25], [5.10, 4.50, 3.25]]))
    for k in sorted(P):
        e = meta.get(k, {}).get("expected_bounds_roblox")
        if e:
            chk(f"BB_{k}", f"{k} bounds", e, r3(BB[k]), bb_eq(BB[k], e))

    # G1 / GJ1
    chk("G1_front_t", "front wall thickness Z 0..0.24", 0.24, round(BB["FrontWall"][1][2] - BB["FrontWall"][0][2], 6),
        near(BB["FrontWall"][1][2] - BB["FrontWall"][0][2], 0.24))
    for s in ("L", "R"):
        b = BB[f"SideWall_{s}"]
        chk(f"G1_side_{s}_t", f"side wall {s} thickness X", 0.24, round(b[1][0] - b[0][0], 6), near(b[1][0] - b[0][0], 0.24))
        chk(f"GJ1_{s}", f"front wall Zmax == side wall {s} Zmin (single corner butt joint)", 0.24,
            [round(BB["FrontWall"][1][2], 6), round(b[0][2], 6)], near(BB["FrontWall"][1][2], b[0][2]))

    # GJ2 wall / plate / wedge / rafter stack
    for s in ("L", "R"):
        wt = BB[f"SideWall_{s}"][1][1]; pb, pt = BB[f"Plate_{s}"][0][1], BB[f"Plate_{s}"][1][1]
        wb = BB[f"Wedge_{s}"][0][1]
        chk(f"GJ2_wall_plate_{s}", f"side wall {s} top 2.90 == plate underside", 2.90, [round(wt, 6), round(pb, 6)],
            near(wt, 2.90) and near(pb, 2.90))
        chk(f"GJ2_plate_wedge_{s}", f"plate {s} top 3.00 == wedge underside", 3.00, [round(pt, 6), round(wb, 6)],
            near(pt, 3.0) and near(wb, 3.0))
        top = [v for v in V[f"Wedge_{s}"] if v[1] > 3.0 + 1e-4]
        dev = max(abs(v[1] - U(v[0])) for v in top)
        hts = sorted({round(v[1] - 3.0, 4) for v in top})
        chk(f"GJ2_wedge_top_{s}", f"wedge {s} top vertices on U(X); heights 0.06/0.18", [0.06, 0.18],
            {"heights": hts, "max_dev": dev}, dev < EPS and hts == [0.06, 0.18])
    chk("GJ2_front_plate", "front wall top == front plate underside; plate top == gable infill underside",
        [2.90, 3.00], [round(BB["FrontWall"][1][1], 6), round(BB["Plate_Front"][0][1], 6),
                       round(BB["Plate_Front"][1][1], 6), round(BB["GableFill"][0][1], 6)],
        near(BB["FrontWall"][1][1], 2.9) and near(BB["Plate_Front"][0][1], 2.9)
        and near(BB["Plate_Front"][1][1], 3.0) and near(BB["GableFill"][0][1], 3.0))
    top = [v for v in V["GableFill"] if v[1] > 3.0 + 1e-4]
    dev = max(abs(v[1] - U(v[0])) for v in top)
    chk("G3_gable_top", "gable infill top vertices on U(X)", 0, dev, dev < EPS)

    # G4 rafters: every vertex on U or U+0.16, axes, halves meet at ridge
    for k, zc in enumerate(RAFTER_AXES, 1):
        for s in ("L", "R"):
            vs = V[f"Rafter{k}_{s}"]
            dev = max(min(abs(v[1] - U(v[0])), abs(v[1] - U(v[0]) - RAFTER_D)) for v in vs)
            b = BB[f"Rafter{k}_{s}"]
            zc_m = (b[0][2] + b[1][2]) / 2
            chk(f"G4_rafter{k}_{s}", f"rafter {k}{s}: verts on U/U+0.16, axis Z={zc}, width 0.08",
                {"axis": zc, "width": 0.08}, {"axis": round(zc_m, 6), "width": round(b[1][2] - b[0][2], 6),
                                              "max_dev": dev},
                dev < EPS and near(zc_m, zc) and near(b[1][2] - b[0][2], 0.08))
        ridge_l = sorted({(round(v[1], 5), round(v[2], 5)) for v in V[f"Rafter{k}_L"] if near(v[0], RIDGE_X)})
        ridge_r = sorted({(round(v[1], 5), round(v[2], 5)) for v in V[f"Rafter{k}_R"] if near(v[0], RIDGE_X)})
        chk(f"GJ3_rafter{k}_mitre", f"rafter pair {k}: identical plumb-cut faces at X=2.40 (no overlap)",
            "equal vertex sets, Y 4.26/4.42", ridge_l, ridge_l == ridge_r and len(ridge_l) == 4
            and BB[f"Rafter{k}_L"][1][0] <= RIDGE_X + EPS and BB[f"Rafter{k}_R"][0][0] >= RIDGE_X - EPS)
    # rafters bear on both side wedges
    for k in range(1, 5):
        b = BB[f"Rafter{k}_L"]
        on = BB["Wedge_L"][0][2] - EPS <= b[0][2] and b[1][2] <= BB["Wedge_L"][1][2] + EPS
        on_g = BB["GableFill"][0][2] - EPS <= b[0][2] and b[1][2] <= BB["GableFill"][1][2] + EPS
        chk(f"GJ2_rafter{k}_bearing", f"rafter {k} Z-span lies on wedge (or gable infill for axis 0.12)",
            True, {"wedge": on, "gable": on_g}, on or on_g)

    # G5 sheathing & skin planes
    for nm, a, b in (("Sheathing", SHEATH_B, SHEATH_T), ("Skin", SHEATH_T, SKIN_T)):
        for s in ("L", "R"):
            vs = V[f"{nm}_{s}"]
            dev = max(min(abs(v[1] - U(v[0]) - a), abs(v[1] - U(v[0]) - b)) for v in vs)
            chk(f"GJ3_{nm}_{s}", f"{nm} {s}: all vertices on U+{a} / U+{b}", 0, dev, dev < EPS)
    z_sk0 = BB["Skin_L"][0][2]
    sk = sorted(v for v in V["Skin_L"] if near(v[1] - U(v[0]), SKIN_T) and near(v[2], z_sk0))
    slope = math.degrees(math.atan2(sk[-1][1] - sk[0][1], sk[-1][0] - sk[0][0]))
    chk("G5_pitch", "roof pitch measured on Skin_L top edge", 26.565, round(slope, 4), abs(slope - 26.5651) < 0.001)

    # D-G21 roof-layer coverage vs nominal G5 envelope (measured, not assumed)
    cov = {k: r3(BB[k]) for k in ("Sheathing_L", "Sheathing_R", "Skin_L", "Skin_R")}
    lay_x = [min(BB["Skin_L"][0][0], BB["Sheathing_L"][0][0]), max(BB["Skin_R"][1][0], BB["Sheathing_R"][1][0])]
    lay_z = [min(BB["Skin_L"][0][2], BB["Sheathing_L"][0][2]), max(BB["Skin_L"][1][2], BB["Sheathing_L"][1][2])]
    chk("DG21_layer_coverage", "D-G21: sheathing+skin actually cover X -0.28..5.08, Z -0.23..3.23 "
        "(0.020 short of nominal G5 envelope on every edge; that strip is the edge board)",
        {"X": [-0.28, 5.08], "Z": [-0.23, 3.23]}, {"X": [round(c, 6) for c in lay_x], "Z": [round(c, 6) for c in lay_z],
                                                  "parts": cov},
        near(lay_x[0], -0.28) and near(lay_x[1], 5.08) and near(lay_z[0], -0.23) and near(lay_z[1], 3.23))
    roof = [k for k in P if k.split("_")[0] in ("Skin", "Sheathing", "Fascia", "Verge", "RidgeCap")]
    rb = bounds([v for k in roof for v in V[k]])
    chk("DG21_envelope_closed", "nominal G5 roof envelope X -0.30..5.10, Z -0.25..3.25 measured over "
        "skin+sheathing+fascia+verge+ridge cap", [[-0.30, -0.25], [5.10, 3.25]],
        [[round(rb[0][0], 6), round(rb[0][2], 6)], [round(rb[1][0], 6), round(rb[1][2], 6)]],
        near(rb[0][0], -0.30) and near(rb[1][0], 5.10) and near(rb[0][2], -0.25) and near(rb[1][2], 3.25))

    # G6 eaves fascia - measured on the fascia mesh alone
    for s in ("L", "R"):
        f = BB[f"Fascia_{s}"]
        xo_ = -0.30 if s == "L" else 5.10
        xi_ = -0.28 if s == "L" else 5.08
        oh = (0 - f[0][0]) if s == "L" else (f[1][0] - BAY_W)
        chk(f"G6_overhang_{s}", f"eaves overhang {s}: outer fascia face from outer wall face", 0.30, round(oh, 6),
            near(oh, 0.30))
        chk(f"G6_fascia_t_{s}", f"fascia {s} thickness", 0.02, round(f[1][0] - f[0][0], 6), near(f[1][0] - f[0][0], 0.02))
        outer = sorted({round(v[1], 6) for v in V[f"Fascia_{s}"] if near(v[0], xo_)})
        h = outer[-1] - outer[0]
        chk(f"G6_fascia_h_{s}", f"fascia {s} ALONE at outer face: bottom 2.906, top 3.106 (=U+0.196), height 0.200",
            {"bottom": 2.906, "top": 3.106, "height": 0.200},
            {"bottom": outer[0], "top": outer[-1], "height": round(h, 6)},
            len(outer) == 2 and near(outer[0], 2.906) and near(outer[-1], 3.106) and near(h, 0.200))
        topv = [v for v in V[f"Fascia_{s}"] if v[1] > 3.0]
        dev = max(abs(v[1] - U(v[0]) - SKIN_T) for v in topv)
        skin_end = sorted({round(v[1], 6) for v in V[f"Skin_{s}"] if near(v[0], xi_)})
        fas_in = sorted({round(v[1], 6) for v in V[f"Fascia_{s}"] if near(v[0], xi_)})
        chk(f"GJ4_fascia_flush_{s}", f"fascia {s} top in skin top plane U+0.196; skin end face X={xi_} "
            f"(Y 3.104..3.116) lies on fascia inner face (Y 2.906..3.116)",
            {"top_plane_dev": 0, "skin_end_Y": [3.104, 3.116], "fascia_inner_Y": [2.906, 3.116]},
            {"top_plane_dev": dev, "skin_end_Y": skin_end, "fascia_inner_Y": fas_in},
            dev < EPS and skin_end == [3.104, 3.116] and fas_in == [2.906, 3.116])
    # G7 verges - measured on the verge mesh alone
    for nm, zo, zi in (("Verge_Front", -0.25, -0.23), ("Verge_Rear", 3.25, 3.23)):
        vs = V[nm]
        dev = max(min(abs(v[1] - U(v[0]) + 0.004), abs(v[1] - U(v[0]) - SKIN_T)) for v in vs)
        b = BB[nm]
        ov = sorted({round(v[1], 6) for v in vs if near(v[2], zo) and near(v[0], -0.30)})
        chk(f"G7_{nm}", f"{nm}: all verts on U-0.004 / U+0.196, thickness 0.02, outer corner height 0.200",
            {"t": 0.02, "outer_Y": [2.906, 3.106]}, {"t": round(b[1][2] - b[0][2], 6), "max_dev": dev, "outer_Y": ov},
            dev < EPS and near(b[1][2] - b[0][2], 0.02) and ov == [2.906, 3.106])
    of = -BB["Verge_Front"][0][2]; orr = BB["Verge_Rear"][1][2] - 3.0
    chk("G7_overhang_front", "verge outer face in front of front wall face", 0.25, round(of, 6), near(of, 0.25))
    chk("G7_overhang_rear", "verge outer face behind rear cut Z=3.00", 0.25, round(orr, 6), near(orr, 0.25))

    # GJ4 mitres: faces of both boards lying in the 45deg mitre plane, measured from the meshes
    def plane_faces(o, on_plane):
        polys = []
        m = o.matrix_world
        for poly in o.data.polygons:
            pts = [toR(m @ o.data.vertices[i].co) for i in poly.vertices]
            if all(on_plane(p) for p in pts):
                polys.append(pts)
        return polys

    def area2d(pp):
        return abs(sum(pp[i][0] * pp[(i + 1) % len(pp)][1] - pp[(i + 1) % len(pp)][0] * pp[i][1]
                       for i in range(len(pp)))) / 2

    def in_convex(pt, poly, tol=1e-7):
        sgn = 0
        for i in range(len(poly)):
            a_, b_ = poly[i], poly[(i + 1) % len(poly)]
            cr = (b_[0] - a_[0]) * (pt[1] - a_[1]) - (b_[1] - a_[1]) * (pt[0] - a_[0])
            if abs(cr) <= tol:
                continue
            s_ = 1 if cr > 0 else -1
            if sgn and s_ != sgn:
                return False
            sgn = s_
        return True

    for side, fz, vname in (("L", "front", "Verge_Front"), ("L", "rear", "Verge_Rear"),
                            ("R", "front", "Verge_Front"), ("R", "rear", "Verge_Rear")):
        xo_ = -0.30 if side == "L" else 5.10
        zo_ = -0.25 if fz == "front" else 3.25
        xi_ = -0.28 if side == "L" else 5.08
        zi_ = -0.23 if fz == "front" else 3.23
        a = Vector((xi_ - xo_, zi_ - zo_)).normalized()
        on = lambda p: abs((p[0] - xo_) * a.y - (p[2] - zo_) * a.x) < 1e-5
        to2 = lambda p: (round((p[0] - xo_) * a.x + (p[2] - zo_) * a.y, 6), round(p[1], 6))
        ff = [[to2(p) for p in q] for q in plane_faces(P[f"Fascia_{side}"], on)]
        vf = [[to2(p) for p in q] for q in plane_faces(P[vname], on)]
        ok = len(ff) == 1 and len(vf) == 1
        if ok:
            fa, va = area2d(ff[0]), area2d(vf[0])
            contained = all(in_convex(p, ff[0]) for p in vf[0])
            sliver = fa - va
            d = round(math.hypot(xi_ - xo_, zi_ - zo_), 6)
            f_in = sorted(p[1] for p in ff[0] if near(p[0], d)); v_in = sorted(p[1] for p in vf[0] if near(p[0], d))
            f_out = sorted(p[1] for p in ff[0] if near(p[0], 0)); v_out = sorted(p[1] for p in vf[0] if near(p[0], 0))
            exp_sliver = 0.5 * d * 0.010
            ok = (contained and f_out == v_out == [2.906, 3.106] and f_in[-1] == v_in[-1] == 3.116
                  and f_in[0] == 2.906 and v_in[0] == 2.916 and abs(sliver - exp_sliver) < 1e-8)
            meas = {"fascia_face_(s,Y)": ff[0], "verge_face_(s,Y)": vf[0], "outer_edge_Y": [f_out, v_out],
                    "inner_edge_Y": {"fascia": f_in, "verge": v_in}, "verge_face_inside_fascia_face": contained,
                    "fascia_area_m2": round(fa, 9), "verge_area_m2": round(va, 9),
                    "exposed_fascia_sliver_m2": round(sliver, 9)}
        else:
            meas = {"fascia_faces": len(ff), "verge_faces": len(vf)}
        chk(f"GJ4_mitre_{side}_{fz}", f"fascia {side}/{vname}: coplanar 45deg mitre, common outer edge 2.906..3.106 "
            "and common top 3.116; verge face lies fully on the fascia face. NOT identical faces: at the inner "
            "corner the horizontal fascia bottom (2.906) is 0.010 below the raking verge bottom (2.916), leaving "
            "an exposed fascia end sliver triangle",
            {"outer_edge_Y": [2.906, 3.106], "inner_edge_Y": {"fascia": [2.906, 3.116], "verge": [2.916, 3.116]},
             "exposed_fascia_sliver_m2": round(0.5 * 0.028284 * 0.010, 9)}, meas, ok)

    # G8 / GJ5 ridge
    rl = sorted({round(v[1], 5) for v in V["Skin_L"] if near(v[0], RIDGE_X)})
    rr = sorted({round(v[1], 5) for v in V["Skin_R"] if near(v[0], RIDGE_X)})
    chk("GJ5_skin_ridge", "both skin halves end at X=2.40 with top Y=4.456 (closed seam)", [4.444, 4.456],
        [rl, rr], rl == rr == [4.444, 4.456])
    capv = sorted({(round(v[0], 4), round(v[1], 4)) for v in V["RidgeCap"]})
    exp_cap = sorted([(2.28, 4.396), (2.40, 4.494), (2.52, 4.396), (2.28, 4.402), (2.40, 4.5), (2.52, 4.402)])
    chk("G8_cap_profile", "ridge cap profile points (X;Y) incl. apex 4.500", exp_cap, capv, capv == exp_cap)
    for xf in (2.28, 2.52):
        sy = U(xf) + SKIN_T
        chk(f"GJ5_cap_foot_{xf}", f"cap foot X={xf} sits on skin top", 4.396, round(sy, 6), near(sy, 4.396))
    for nm in ("RidgeEnd_Front", "RidgeEnd_Rear"):
        ev = sorted({(round(v[0], 4), round(v[1], 4)) for v in V[nm]})
        exp_e = sorted([(2.28, 4.396), (2.40, 4.456), (2.52, 4.396), (2.40, 4.494)])
        chk(f"GJ5_{nm}", f"{nm} closes gap between roof top plane (4.456 at ridge; over Z -0.25..-0.23 / "
            f"3.23..3.25 this plane is the verge-board top) and cap underside (4.494)", exp_e, ev, ev == exp_e)

    # G9-G12 window via rays against the wall
    wt = bvh_of(P["FrontWall"])[0]

    def ray_R(o, d):
        h = wt.ray_cast(R(*o), R(*d) - R(0, 0, 0), 10)
        return None if h[0] is None else toR(h[0])

    hit_open = ray_R((1.6, 1.6, -1.0), (0, 0, 1))
    hit_wall = ray_R((0.5, 1.6, -1.0), (0, 0, 1))
    chk("G9_open", "opening passes through whole wall; solid wall beside it starts at Z=0",
        {"opening": None, "wall_hit_Z": 0.0}, {"opening": hit_open, "wall_hit": hit_wall},
        hit_open is None and hit_wall is not None and near(hit_wall[2], 0.0))
    # raw wall cutout (FrontWall alone) vs finished opening (FrontWall + Sill assembled)
    st = bvh_of(P["Sill"])[0]

    def ray_multi(trees, o, d):
        best = None
        for tr in trees:
            h = tr.ray_cast(R(*o), R(*d) - R(0, 0, 0), 10)
            if h[0] is not None and (best is None or h[3] < best[1]):
                best = (toR(h[0]), h[3])
        return None if best is None else best[0]

    raw_dn = ray_R((1.6, 1.6, 0.12), (0, -1, 0))
    raw_l = ray_R((1.6, 0.98, 0.12), (-1, 0, 0)); raw_r = ray_R((1.6, 0.98, 0.12), (1, 0, 0))
    raw_h = round(2.20 - raw_dn[1], 6) if raw_dn else None
    raw_w = round(raw_r[0] - raw_l[0], 6) if raw_l and raw_r else None
    chk("G9_raw_wall_cutout", "FrontWall ALONE: cutout = opening 1.20x1.20 plus sill slot X 0.96..2.24 / "
        "Y 0.96..1.00 -> clear height 0.96..2.20 = 1.24 at X=1.6, slot width 1.28 at Y=0.98 (filled by the sill)",
        {"height_incl_slot": 1.24, "slot_width": 1.28}, {"height_incl_slot": raw_h, "slot_width": raw_w},
        raw_h is not None and near(raw_h, 1.24, 1e-4) and raw_w is not None and near(raw_w, 1.28, 1e-4))
    fin = {}
    ok_fin = True
    for (px, py, pz) in ((1.6, 1.6, 0.02), (1.6, 1.6, 0.12), (1.6, 1.6, 0.22), (1.05, 1.05, 0.12), (2.15, 2.15, 0.12)):
        l_ = ray_multi([wt, st], (px, py, pz), (-1, 0, 0)); r_ = ray_multi([wt, st], (px, py, pz), (1, 0, 0))
        d_ = ray_multi([wt, st], (px, py, pz), (0, -1, 0)); u_ = ray_multi([wt, st], (px, py, pz), (0, 1, 0))
        w_ = round(r_[0] - l_[0], 6) if l_ and r_ else None
        h_ = round(u_[1] - d_[1], 6) if d_ and u_ else None
        fin[f"{px},{py},{pz}"] = {"w": w_, "h": h_, "bottom_Y": round(d_[1], 6) if d_ else None}
        ok_fin &= (w_ is not None and near(w_, 1.20, 1e-4) and h_ is not None and near(h_, 1.20, 1e-4)
                   and near(d_[1], 1.00, 1e-4))
    chk("G9_finished_opening", "assembled FrontWall+Sill: finished opening 1.20 x 1.20, bottom = sill top 1.00 "
        "(rays from 5 points in the opening, front/mid/rear depth)", {"w": 1.20, "h": 1.20, "bottom_Y": 1.00},
        fin, ok_fin)
    fb = BB["WindowFrame"]
    chk("G10_outer", "frame outer size", [1.18, 1.18], [round(fb[1][0] - fb[0][0], 6), round(fb[1][1] - fb[0][1], 6)],
        near(fb[1][0] - fb[0][0], 1.18) and near(fb[1][1] - fb[0][1], 1.18))
    chk("GJ6_recess", "frame 0.04 behind outer plaster, 0.06 before inner face", [0.04, 0.06],
        [round(fb[0][2], 6), round(0.24 - fb[1][2], 6)], near(fb[0][2], 0.04) and near(0.24 - fb[1][2], 0.06))
    gaps = [round(fb[0][0] - 1.0, 6), round(2.2 - fb[1][0], 6), round(fb[0][1] - 1.0, 6), round(2.2 - fb[1][1], 6)]
    chk("GJ6_gap", "0.01 sealing joint around frame", 0.01, gaps, all(near(g, 0.01) for g in gaps))
    ft = bvh_of(P["WindowFrame"])[0]

    def clear_x(z):
        a_ = ft.ray_cast(R(1.6, 1.6, z), Vector((-1, 0, 0)), 5)
        b_ = ft.ray_cast(R(1.6, 1.6, z), Vector((1, 0, 0)), 5)
        return (round(b_[0].x - a_[0].x, 6), round(a_[0].x, 6)) if a_[0] is not None and b_[0] is not None else (None, None)
    lm_front, lx_front = clear_x(0.08)
    lm_glass, lx_glass = clear_x(0.110)
    lm_rear, lx_rear = clear_x(0.15)
    chk("G10_light", "frame light opening 1.06 (profile 0.06) in the outer section Z 0.04..0.113 incl. glass plane",
        {"Z0.08": 1.06, "Z0.110": 1.06}, {"Z0.08": lm_front, "Z0.110": lm_glass},
        lm_front is not None and near(lm_front, 1.06, 1e-4) and lm_glass is not None and near(lm_glass, 1.06, 1e-4))
    chk("DG22_rear_stop", "D-G22: rear glazing stop Z 0.113..0.18 leaves clear 1.04 (0.010 rebate shoulder)",
        1.04, lm_rear, lm_rear is not None and near(lm_rear, 1.04, 1e-4))
    # glass seating measured on the actual meshes
    gb = BB["Glass"]
    shoulder = []
    m = P["WindowFrame"].matrix_world
    for poly in P["WindowFrame"].data.polygons:
        pts = [toR(m @ P["WindowFrame"].data.vertices[i].co) for i in poly.vertices]
        n_r = toR(m.to_3x3() @ poly.normal)
        if all(near(p[2], 0.113) for p in pts) and n_r[2] < -0.99:
            shoulder.append((poly.area, pts))
    sh_area = sum(a_ for a_, _ in shoulder)
    sh_in = all(gb[0][0] - EPS <= p[0] <= gb[1][0] + EPS and gb[0][1] - EPS <= p[1] <= gb[1][1] + EPS
                for _, pts in shoulder for p in pts)
    d1_ = Vector((0.5773, 0.5778, 0.5769)).normalized(); d2_ = Vector((-0.31, 0.83, -0.46)).normalized()
    ins = lambda pr: inside(ft, R(*pr), d1_) and inside(ft, R(*pr), d2_)
    # probe positions are derived from the MEASURED glass mesh bounds (gx0..gx1, gy0..gy1, gz0..gz1)
    gx0, gy0, gz0 = gb[0]; gx1, gy1, gz1 = gb[1]
    ts = [gy0 + 0.03 + (gy1 - gy0 - 0.06) * i / 19 for i in range(20)]
    tx = [gx0 + 0.03 + (gx1 - gx0 - 0.06) * i / 19 for i in range(20)]
    zr = gz1 + 0.0005                                   # 0.5 mm behind the glass rear face
    seat = [ins((gx0 + 0.005, t, zr)) for t in ts] + [ins((gx1 - 0.005, t, zr)) for t in ts] + \
           [ins((t, gy0 + 0.005, zr)) for t in tx] + [ins((t, gy1 - 0.005, zr)) for t in tx]
    clear = [ins((gx0 + 0.0155, t, zr)) for t in ts] + [ins(((gx0 + gx1) / 2, t, zr)) for t in ts]
    zs_ = (gz0 + 0.0005, (gz0 + gz1) / 2, gz1 - 0.0005)
    edge = [ins((gx0 - 0.0005, t, z)) for t in ts for z in zs_] + \
           [ins((gx1 + 0.0005, t, z)) for t in ts for z in zs_] + \
           [ins((t, gy0 - 0.0005, zs_[1])) for t in tx] + [ins((t, gy1 + 0.0005, zs_[1])) for t in tx]
    front_free = [ins((gx0 + 0.005, t, gz0 - 0.0005)) for t in ts]
    meas = {"glass_Z": [round(gb[0][2], 6), round(gb[1][2], 6)],
            "shoulder_faces": len(shoulder), "shoulder_area_m2": round(sh_area, 6), "shoulder_within_glass_xy": sh_in,
            "rear_band_points_in_frame": f"{sum(seat)}/{len(seat)}",
            "points_behind_clear_glass_in_frame": f"{sum(clear)}/{len(clear)}",
            "edge_points_in_frame": f"{sum(edge)}/{len(edge)}",
            "points_in_front_of_glass_band_in_frame": f"{sum(front_free)}/{len(front_free)}"}
    chk("GJ6_glass_rebate", "glass seated in stepped rebate (actual meshes): glass rear face Z=0.113 lies on the frame "
        "shoulder (faces at Z=0.113 facing the glass, area 1.06^2-1.04^2=0.042 m2, inside glass outline); points "
        "0.5 mm behind the 0.010 glass edge band are inside the frame, behind the clear glass they are not; "
        "points 0.5 mm outside all four glass edges are inside the rebate side walls; front of glass is open "
        "(no glazing bead modelled)",
        {"glass_Z": [0.107, 0.113], "shoulder_area_m2": 0.042, "rear_band_points_in_frame": "80/80",
         "points_behind_clear_glass_in_frame": "0/40", "edge_points_in_frame": "160/160",
         "points_in_front_of_glass_band_in_frame": "0/20"}, meas,
        near(gb[1][2], 0.113) and near(gb[0][2], 0.107) and abs(sh_area - 0.042) < 1e-6 and sh_in
        and all(seat) and not any(clear) and all(edge) and not any(front_free))
    sb = BB["Sill"]
    chk("GJ7_sill", "sill top 1.00 = opening bottom, frame bottom 1.01, sill to inner wall face 0.24, 0.04 projection",
        {"top": 1.0, "frame": 1.01, "rear": 0.24, "front": -0.04},
        {"top": round(sb[1][1], 6), "frame": round(fb[0][1], 6), "rear": round(sb[1][2], 6), "front": round(sb[0][2], 6)},
        near(sb[1][1], 1.0) and near(fb[0][1], 1.01) and near(sb[1][2], 0.24) and near(sb[0][2], -0.04))
    seal = BB["WindowSeal"]
    chk("GJ6_seal_recessed", "seal fills joint, recessed 0.02 behind both frame faces, rests on sill",
        {"Z": [0.06, 0.16], "bottom": 1.0}, r3(seal), near(seal[0][2], 0.06) and near(seal[1][2], 0.16)
        and near(seal[0][1], 1.0))

    # mesh health
    total_tris = 0
    health = {}
    for k, o in P.items():
        h = mesh_health(o)
        health[k] = h
        total_tris += h["triangles"]
        ok = h["finite"] and h["non_manifold_edges"] == 0 and h["bad_winding_edges"] == 0 and h["loose_verts"] == 0 \
            and h["signed_volume"] > 0 and h["degenerate_faces"] == 0
        chk(f"MESH_{k}", f"{k}: finite, closed manifold, consistent outward normals, positive volume",
            "closed, vol>0", {"tris": h["triangles"], "vol_m3": round(h["signed_volume"], 7),
                               "nonmanifold": h["non_manifold_edges"], "badwind": h["bad_winding_edges"]}, ok)

    # interpenetration (sample points 0.5 mm inside every face of A must be outside every B)
    trees = {k: bvh_of(o) for k, o in P.items()}
    d1 = Vector((0.5773, 0.5778, 0.5769)).normalized()
    d2 = Vector((-0.31, 0.83, -0.46)).normalized()
    hits = []
    for ka, (ta, pts_all, _) in trees.items():
        # keep only samples that are really inside A (acute feet/chamfers can push a sample outside A)
        pts = [p for p in pts_all if inside(ta, p, d1) and inside(ta, p, d2)]
        for kb, (tb, _, bbb) in trees.items():
            if ka == kb:
                continue
            for p in pts:
                if not all(bbb[0][i] - 1e-4 <= p[i] <= bbb[1][i] + 1e-4 for i in range(3)):
                    continue
                if inside(tb, p, d1) and inside(tb, p, d2):
                    hits.append([ka, kb, [round(c, 4) for c in toR(p)]])
                    break
    chk("NO_PENETRATION", "no part's interior sample lies inside another part (contacts are face-to-face)",
        [], hits[:20], not hits)
    chk("TRIS", "total exported triangles (report)", "report", total_tris, total_tris > 0)

    passed = sum(c["pass"] for c in checks)
    return {"scene": sc.name, "blender": bpy.app.version_string, "coords": "Roblox metres (X, Y up, Z back; front -Z)",
            "passed": passed, "failed": len(checks) - passed, "total_triangles": total_tris,
            "triangles": {k: h["triangles"] for k, h in health.items()}, "checks": checks}


# ---------------------------------------------------------------- ownership regression
SENT = "p03_03_sentinel"
REGRESS_PATH_NAME = "regression-ownership.json"


def _snapshot_foreign_scenes():
    snap = {}
    for s in bpy.data.scenes:
        if s.get(OWN) or s.get(SENT):
            continue
        snap[s.name] = sorted((o.name, tuple(round(c, 6) for row in o.matrix_world for c in row), o.type)
                              for o in s.objects)
    return snap


def regress_ownership():
    """Isolated regression for cleanup_owned():
    A) an UNOWNED scene named SCENE_NAME (with a plain sentinel mesh object and a sentinel object that even
       carries the owner flag) must survive: cleanup raises OwnershipError and deletes nothing;
    B) the real owned scene with one foreign object linked into it must also abort without deletions.
    Only the sentinels created here are removed afterwards; the owned scene name and window scene are restored."""
    win = bpy.context.window_manager.windows[0]
    orig_win_scene = win.scene.name
    before = _snapshot_foreign_scenes()
    res = {"A_unowned_collision": {}, "B_foreign_object_in_owned_scene": {}}
    owned = bpy.data.scenes.get(SCENE_NAME)
    if owned is not None and not owned.get(OWN):
        raise OwnershipError("unowned scene already present; regression refuses to run")
    hold_name = SCENE_NAME + "__regress_hold"
    created = []
    try:
        if owned is not None:
            owned.name = hold_name
        # --- A
        s = bpy.data.scenes.new(SCENE_NAME)
        s[SENT] = True
        created.append(("scene", s.name))
        me = bpy.data.meshes.new("P03_SENTINEL_mesh"); me[SENT] = True
        o1 = bpy.data.objects.new("P03_SENTINEL_plain", me); o1[SENT] = True
        o2 = bpy.data.objects.new("P03_SENTINEL_flagged", None); o2[SENT] = True; o2[OWN] = True
        s.collection.objects.link(o1); s.collection.objects.link(o2)
        created += [("object", o1.name), ("object", o2.name), ("mesh", me.name)]
        err = None
        try:
            cleanup_owned()
        except OwnershipError as ex:
            err = str(ex)
        s_alive = bpy.data.scenes.get(SCENE_NAME)
        alive = {n: (bpy.data.objects.get(n) is not None and s_alive is not None and n in s_alive.objects)
                 for n in ("P03_SENTINEL_plain", "P03_SENTINEL_flagged")}
        res["A_unowned_collision"] = {"raised": err, "scene_survived": s_alive is not None and s_alive == s,
                                      "objects_survived": alive, "mesh_survived": bpy.data.meshes.get(me.name) is not None,
                                      "pass": bool(err) and s_alive is not None and all(alive.values())
                                      and bpy.data.meshes.get(me.name) is not None}
        # remove ONLY sentinel A data
        for n in ("P03_SENTINEL_plain", "P03_SENTINEL_flagged"):
            ob = bpy.data.objects.get(n)
            if ob is not None and ob.get(SENT):
                bpy.data.objects.remove(ob, do_unlink=True)
        if bpy.data.meshes.get("P03_SENTINEL_mesh") is not None and bpy.data.meshes["P03_SENTINEL_mesh"].get(SENT):
            bpy.data.meshes.remove(bpy.data.meshes["P03_SENTINEL_mesh"])
        if s_alive is not None and s_alive.get(SENT):
            bpy.data.scenes.remove(s_alive)
        # --- B
        if owned is not None:
            owned.name = SCENE_NAME
            n_before = len(owned.objects)
            f = bpy.data.objects.new("P03_SENTINEL_foreign", None); f[SENT] = True
            owned.collection.objects.link(f)
            err = None
            try:
                cleanup_owned()
            except OwnershipError as ex:
                err = str(ex)
            still = bpy.data.scenes.get(SCENE_NAME)
            n_after = len(still.objects) if still else None
            res["B_foreign_object_in_owned_scene"] = {"raised": err, "owned_objects_before": n_before + 1,
                                                      "owned_objects_after": n_after,
                                                      "pass": bool(err) and still == owned and n_after == n_before + 1}
            if f.get(SENT):
                bpy.data.objects.remove(f, do_unlink=True)
        else:
            res["B_foreign_object_in_owned_scene"] = {"skipped": "no owned scene present", "pass": True}
    finally:
        for n in ("P03_SENTINEL_plain", "P03_SENTINEL_flagged", "P03_SENTINEL_foreign"):
            ob = bpy.data.objects.get(n)
            if ob is not None and ob.get(SENT):
                bpy.data.objects.remove(ob, do_unlink=True)
        sm = bpy.data.meshes.get("P03_SENTINEL_mesh")
        if sm is not None and sm.get(SENT):
            bpy.data.meshes.remove(sm)
        ss = bpy.data.scenes.get(SCENE_NAME)
        if ss is not None and ss.get(SENT):
            bpy.data.scenes.remove(ss)
        h = bpy.data.scenes.get(hold_name)
        if h is not None and h.get(OWN) and bpy.data.scenes.get(SCENE_NAME) is None:
            h.name = SCENE_NAME
        win.scene = bpy.data.scenes[orig_win_scene]
    after = _snapshot_foreign_scenes()
    leftovers = [d.name for c in (bpy.data.objects, bpy.data.meshes, bpy.data.scenes) for d in c if d.get(SENT)]
    res["foreign_scenes_unchanged"] = before == after
    res["sentinel_leftovers"] = leftovers
    res["owned_scene_restored"] = bpy.data.scenes.get(SCENE_NAME) is not None and bool(bpy.data.scenes[SCENE_NAME].get(OWN))
    res["window_scene_restored"] = win.scene.name == orig_win_scene
    res["pass"] = (res["A_unowned_collision"].get("pass") and res["B_foreign_object_in_owned_scene"].get("pass")
                   and res["foreign_scenes_unchanged"] and not leftovers and res["owned_scene_restored"]
                   and res["window_scene_restored"])
    with open(os.path.join(PKG, REGRESS_PATH_NAME), "w", encoding="utf-8") as fh:
        json.dump(res, fh, indent=2)
    return res


# ---------------------------------------------------------------- save / export / roundtrip / render
def with_scene(sc, fn):
    win = bpy.context.window_manager.windows[0]
    orig = win.scene
    win.scene = sc
    try:
        with bpy.context.temp_override(window=win, scene=sc, view_layer=sc.view_layers[0]):
            return fn()
    finally:
        win.scene = orig


def save_blend(sc):
    ids = {sc} | {o for o in sc.objects} | {c for c in bpy.data.collections if c.get(OWN)}
    if sc.world:
        ids.add(sc.world)
    bpy.data.libraries.write(BLEND_PATH, ids, path_remap="RELATIVE_ALL", fake_user=True)
    with bpy.data.libraries.load(BLEND_PATH) as (src, _):
        info = {"scenes": list(src.scenes), "objects": len(src.objects), "meshes": len(src.meshes),
                "materials": sorted(src.materials)}
    return {"path": BLEND_PATH, "bytes": os.path.getsize(BLEND_PATH), "contents": info}


FBX_KW = dict(use_selection=True, object_types={"EMPTY", "MESH"}, global_scale=1.0, apply_unit_scale=True,
              apply_scale_options="FBX_SCALE_NONE", axis_forward="-Z", axis_up="Y", use_mesh_modifiers=True,
              mesh_smooth_type="FACE", add_leaf_bones=False, bake_anim=False, use_custom_props=False,
              path_mode="AUTO")


def export_fbx(sc):
    os.makedirs(EXPORTS, exist_ok=True)
    rna = bpy.ops.export_scene.fbx.get_rna_type()
    for p in ("axis_forward", "axis_up", "apply_scale_options", "mesh_smooth_type"):
        assert FBX_KW[p] in [i.identifier for i in rna.properties[p].enum_items], p
    vl = sc.view_layers[0]
    out = {}
    root = sc.objects["Gebaeudeecke01"]
    cube = sc.objects["ControlCube_1m"]
    jobs = {"Gebaeudeecke01.fbx": [root] + model_parts(sc), "ControlCube_1m.fbx": [cube]}

    def go():
        for fname, objs in jobs.items():
            saved = {o: o.location.copy() for o in objs}
            for o in sc.objects:
                o.select_set(False, view_layer=vl)
            for o in objs:
                o.select_set(True, view_layer=vl)
            if cube in objs:
                cube.location = (0, 0, 0)
            path = os.path.join(EXPORTS, fname)
            r = bpy.ops.export_scene.fbx(filepath=path, **FBX_KW)
            for o, l in saved.items():
                o.location = l
            for o in objs:
                o.select_set(False, view_layer=vl)
            out[fname] = {"result": list(r), "bytes": os.path.getsize(path), "objects": len(objs)}
    with_scene(sc, go)
    return out


def roundtrip(src_tris=None):
    res = {}
    expected = {"Gebaeudeecke01.fbx": [[-0.30, -3.25, 0.0], [5.10, 0.25, 4.50]],
                "ControlCube_1m.fbx": [[-0.5, -0.5, 0.0], [0.5, 0.5, 1.0]]}
    exp_tris = {"Gebaeudeecke01.fbx": src_tris, "ControlCube_1m.fbx": 12}
    for fname, exp in expected.items():
        tmp = bpy.data.scenes.new("P03-03_roundtrip_tmp")
        before = {k: set(getattr(bpy.data, k)) for k in ("objects", "meshes", "materials")}
        try:
            def go():
                bpy.ops.import_scene.fbx(filepath=os.path.join(EXPORTS, fname))
            with_scene(tmp, go)
            new = [o for o in bpy.data.objects if o not in before["objects"]]
            meshes = [o for o in new if o.type == "MESH"]
            dg = bpy.context.evaluated_depsgraph_get()
            vs = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
            bb = [[min(v[i] for v in vs) for i in range(3)], [max(v[i] for v in vs) for i in range(3)]]
            ok = all(abs(bb[i][j] - exp[i][j]) < 1e-4 for i in range(2) for j in range(3))
            tris = sum(len(o.data.loop_triangles) if (o.data.calc_loop_triangles() or True) else 0 for o in meshes)
            roots = [o.name for o in new if o.parent is None]
            if exp_tris.get(fname) is not None:
                ok = ok and tris == exp_tris[fname]
            res[fname] = {"expected_blender_bounds": exp, "measured": [[round(c, 5) for c in b] for b in bb],
                          "expected_triangles": exp_tris.get(fname),
                          "mesh_objects": len(meshes), "triangles": tris, "roots": roots, "pass": ok,
                          "materials": sorted({m.name for o in meshes for m in o.data.materials if m})}
        finally:
            for o in [o for o in bpy.data.objects if o not in before["objects"]]:
                bpy.data.objects.remove(o, do_unlink=True)
            for k in ("meshes", "materials"):
                for d in [d for d in getattr(bpy.data, k) if d not in before[k]]:
                    getattr(bpy.data, k).remove(d)
            bpy.data.scenes.remove(tmp)
    with open(ROUNDTRIP_PATH, "w", encoding="utf-8") as f:
        json.dump(res, f, indent=2)
    return res


def render_all(sc, only=None):
    os.makedirs(RENDERS, exist_ok=True)
    orig_cam = sc.camera
    orig_res = (sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage)
    out = {}
    try:
        for name, (_, _, _, _, res) in CAMERAS.items():
            if only and name not in only:
                continue
            sc.camera = sc.objects["Cam_" + name]
            sc.render.resolution_x, sc.render.resolution_y = res
            sc.render.resolution_percentage = 100
            sc.render.use_freestyle = name.startswith("detail_")   # outline part boundaries in joint details only
            sc.render.filepath = os.path.join(RENDERS, name + ".png")
            t = time.time()
            bpy.ops.render.render(write_still=True, scene=sc.name)
            out[name] = {"path": sc.render.filepath, "seconds": round(time.time() - t, 2),
                         "exists": os.path.isfile(sc.render.filepath)}
    finally:
        sc.render.use_freestyle = False
        sc.camera = orig_cam
        sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = orig_res
    return out


def main():
    report = {"stages": list(STAGES), "package": PKG}
    sc = bpy.data.scenes.get(SCENE_NAME)
    if "build" in STAGES or sc is None:
        sc = build()
        report["built"] = sc.name
    if "regress" in STAGES:
        report["regress"] = regress_ownership()
        sc = bpy.data.scenes[SCENE_NAME]
    if "check" in STAGES:
        c = run_checks(sc)
        with open(CHECKS_PATH, "w", encoding="utf-8") as f:
            json.dump(c, f, indent=2)
        report["checks"] = {"passed": c["passed"], "failed": c["failed"], "tris": c["total_triangles"],
                            "failures": [x for x in c["checks"] if not x["pass"]]}
    if "save" in STAGES:
        report["blend"] = save_blend(sc)
    if "export" in STAGES:
        report["fbx"] = export_fbx(sc)
    if "roundtrip" in STAGES:
        report["roundtrip"] = roundtrip(sum(mesh_health(o)["triangles"] for o in model_parts(sc)))
    if "render" in STAGES:
        report["renders"] = render_all(sc, globals().get("P03_RENDER_ONLY"))
    manifest = {}
    if os.path.isfile(MANIFEST_PATH):
        with open(MANIFEST_PATH, encoding="utf-8") as f:
            manifest = json.load(f)
    manifest.update({"asset": "Gebaeudeecke01", "task": "P03-03", "scene": SCENE_NAME,
                     "blender": bpy.app.version_string, "units": "metres, scale_length 1.0",
                     "axes": "Blender X,Y,Z -> Roblox X,Z,-Y; FBX axis_forward=-Z axis_up=Y global_scale=1",
                     "pivot": "Roblox (0,0,0) = outer front-left wall corner at ground (D-G0)",
                     "parts": {short(o): {"group": o.get("p03_group"),
                                          "material": o.data.materials[0].name if o.data.materials else None,
                                          "triangles": len(o.data.loop_triangles) if (o.data.calc_loop_triangles() or True) else 0}
                               for o in model_parts(sc)},
                     "detail_decisions": {
                         "D-G21": "Sheathing and metal skin end at the inner face of the 0.020 fascia/verge boards: "
                                  "actual coverage X -0.28..5.08, Z -0.23..3.23 (nominal G5 -0.30..5.10 / -0.25..3.25 "
                                  "is closed by the boards). Fascia outer face is 0.200 high with horizontal bottom 2.906 "
                                  "(inner face 0.210); verge is 0.200 along the U-0.004..U+0.196 contour. "
                                  "Tops are coplanar with skin top, butt joint, no overlapping volume.",
                         "D-G22": "Window frame stepped: outer section Z 0.040..0.113 light 1.06 (rebate side walls), "
                                  "rear stop Z 0.113..0.180 clear 1.04. Glass 1.06x1.06x0.006 rests with a 0.010 band "
                                  "on the stop shoulder at Z=0.113; no glazing bead in front.",
                         "GJ4_mitre_profile": "Coplanar 45deg mitre, common outer edge 2.906..3.106 and top 3.116; at "
                                              "the inner corner fascia bottom 2.906 vs verge bottom 2.916 -> exposed "
                                              "fascia sliver 0.5*0.028284*0.010 = 1.414e-4 m2 per corner (recorded, "
                                              "not hidden).",
                         "G9": "FrontWall raw cutout includes the sill slot (height 1.24 at X=1.6, slot width 1.28); "
                               "finished opening with sill assembled is 1.20 x 1.20.",
                         "cleanup": "cleanup_owned() verifies scene ownership and absence of foreign objects before "
                                    "any deletion; see regression-ownership.json."}})
    for k in ("checks", "blend", "fbx", "roundtrip", "renders", "regress"):
        if k in report:
            manifest["last_" + k] = report[k] if k != "checks" else {kk: report[k][kk] for kk in ("passed", "failed", "tris")}
    manifest["last_run"] = time.strftime("%Y-%m-%d %H:%M:%S")
    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, default=str)
    return report


if __name__ == "__main__":
    REPORT = main()
    print(json.dumps(REPORT, indent=1, default=str)[:6000])
