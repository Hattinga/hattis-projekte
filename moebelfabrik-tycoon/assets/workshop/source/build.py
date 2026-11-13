import bpy
import bmesh
import sys
import os
import math
import random
from mathutils import Vector, Matrix

# ---------------------------------------------------------------------------
# Output directory
# ---------------------------------------------------------------------------
argv = sys.argv
OUT = None
if "--" in argv:
    rest = argv[argv.index("--") + 1:]
    if rest:
        OUT = rest[0]
if not OUT:
    OUT = os.path.join(os.getcwd(), "out")
OUT = os.path.abspath(OUT)
os.makedirs(OUT, exist_ok=True)

# ---------------------------------------------------------------------------
# Clean factory scene
# ---------------------------------------------------------------------------
scene = bpy.context.scene
for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob, do_unlink=True)
for c in list(bpy.data.collections):
    bpy.data.collections.remove(c)
for datablocks in (bpy.data.meshes, bpy.data.lights, bpy.data.cameras, bpy.data.materials):
    for b in list(datablocks):
        try:
            datablocks.remove(b)
        except Exception:
            pass
try:
    scene.world = None
    for w in list(bpy.data.worlds):
        bpy.data.worlds.remove(w)
except Exception:
    pass
try:
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1.0
except Exception:
    pass


def new_coll(name, parent):
    c = bpy.data.collections.new(name)
    parent.children.link(c)
    return c


ASSET = new_coll("ASSET", scene.collection)
SHELL = new_coll("SHELL", ASSET)
INTERIOR = new_coll("INTERIOR", ASSET)
ROOF = new_coll("ROOF", ASSET)

# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------


def _lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _hex(h, k=1.0):
    h = h.lstrip('#')
    vals = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return [_lin(max(0.0, min(1.0, v * k))) for v in vals]


MATS = {}


def mk(key, hx, k=1.0, rough=0.8, metal=0.0, alpha=1.0):
    col = _hex(hx, k)
    m = bpy.data.materials.new("WS_" + key)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = getattr(m, "node_tree", None)
    bsdf = None
    if nt is not None:
        for n in nt.nodes:
            if n.type == 'BSDF_PRINCIPLED':
                bsdf = n
                break
        if bsdf is None:
            try:
                bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
                outn = None
                for n in nt.nodes:
                    if n.type == 'OUTPUT_MATERIAL':
                        outn = n
                        break
                if outn is None:
                    outn = nt.nodes.new('ShaderNodeOutputMaterial')
                nt.links.new(bsdf.outputs[0], outn.inputs[0])
            except Exception:
                bsdf = None
    if bsdf is not None:
        try:
            if 'Base Color' in bsdf.inputs:
                bsdf.inputs['Base Color'].default_value = (col[0], col[1], col[2], 1.0)
            if 'Roughness' in bsdf.inputs:
                bsdf.inputs['Roughness'].default_value = rough
            if 'Metallic' in bsdf.inputs:
                bsdf.inputs['Metallic'].default_value = metal
            if 'Alpha' in bsdf.inputs:
                bsdf.inputs['Alpha'].default_value = alpha
        except Exception:
            pass
    try:
        m.diffuse_color = (col[0], col[1], col[2], alpha)
        m.roughness = rough
        m.metallic = metal
    except Exception:
        pass
    if alpha < 1.0:
        try:
            if hasattr(m, "surface_render_method"):
                m.surface_render_method = 'BLENDED'
            elif hasattr(m, "blend_method"):
                m.blend_method = 'BLEND'
        except Exception:
            pass
    MATS[key] = m
    return m


WALL = mk("wall_white", "E8E0D1", 1.0, 0.9)
WALL_B = mk("wall_white_batten", "E8E0D1", 0.95, 0.9)
LINING = mk("lining_ply", "E0D2B8", 1.0, 0.85)
LINING_D = mk("lining_strip", "E0D2B8", 0.92, 0.85)
WOOD = mk("wood", "C59664", 1.0, 0.8)
WOOD_L = mk("wood_light", "C59664", 1.1, 0.8)
WOOD_M = mk("wood_mid", "C59664", 0.93, 0.82)
WOOD_D = mk("wood_dark", "C59664", 0.84, 0.85)
WOOD_DD = mk("wood_endgrain", "C59664", 0.68, 0.9)
STEEL = mk("roof_steel", "34383C", 1.0, 0.6, 0.35)
STEEL_B = mk("roof_steel_b", "34383C", 1.14, 0.6, 0.35)
STEEL_D = mk("roof_steel_seam", "34383C", 0.86, 0.6, 0.35)
TOOL = mk("tool_steel", "8E9499", 1.0, 0.45, 0.6)
GREEN = mk("green", "788678", 1.0, 0.8)
GREEN_L = mk("green_light", "788678", 1.08, 0.8)
GREEN_D = mk("green_dark", "788678", 0.85, 0.8)
CONC = mk("concrete", "9A968D", 1.0, 0.95)
CONC_B = mk("concrete_b", "A7A39A", 1.0, 0.95)
RUBBER = mk("rubber", "2C2F31", 1.0, 0.9)
DARK = mk("dark_recess", "2A2420", 1.0, 0.95)
GLASS = mk("glass", "B4C6C2", 1.0, 0.12, 0.0, 0.35)
BULB = mk("bulb", "F1E9D2", 1.0, 0.5)

# ---------------------------------------------------------------------------
# Geometry builder
# ---------------------------------------------------------------------------
TRIS = [0]


class Part:
    def __init__(self, mirror=False):
        self.v = []
        self.f = []
        self.m = []
        self.s = []
        self.mats = []
        self.M = Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0)) if mirror else None

    def _mi(self, mat):
        for i, mm in enumerate(self.mats):
            if mm.name == mat.name:
                return i
        self.mats.append(mat)
        return len(self.mats) - 1

    def add(self, verts, faces, mat, smooth=False):
        b = len(self.v)
        mi = self._mi(mat)
        for p in verts:
            if self.M is not None:
                q = self.M @ Vector((p[0], p[1], p[2]))
                self.v.append((q.x, q.y, q.z))
            else:
                self.v.append((float(p[0]), float(p[1]), float(p[2])))
        for i, f in enumerate(faces):
            self.f.append(tuple(b + k for k in f))
            self.m.append(mi)
            if isinstance(smooth, (list, tuple)):
                self.s.append(bool(smooth[i]))
            else:
                self.s.append(bool(smooth))

    def box(self, x0, x1, y0, y1, z0, z1, mat):
        x0, x1 = min(x0, x1), max(x0, x1)
        y0, y1 = min(y0, y1), max(y0, y1)
        z0, z1 = min(z0, z1), max(z0, z1)
        v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
             (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        self.add(v, f, mat)

    def frustum(self, x0, x1, y0, y1, z0, z1, inset, mat):
        v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
             (x0 + inset, y0 + inset, z1), (x1 - inset, y0 + inset, z1),
             (x1 - inset, y1 - inset, z1), (x0 + inset, y1 - inset, z1)]
        f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        self.add(v, f, mat)

    def prism(self, poly, axis, a0, a1, mat):
        n = len(poly)

        def p3(p, q, a):
            if axis == 'x':
                return (a, p, q)
            if axis == 'y':
                return (p, a, q)
            return (p, q, a)
        v = [p3(p, q, a0) for (p, q) in poly] + [p3(p, q, a1) for (p, q) in poly]
        f = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
        for i in range(n):
            j = (i + 1) % n
            f.append((i, j, j + n, i + n))
        self.add(v, f, mat)

    def cyl(self, p0, p1, r, mat, n=10, r1=None):
        a = Vector(p0)
        b = Vector(p1)
        ax = (b - a)
        if ax.length < 1e-9:
            return
        ax.normalize()
        up = Vector((0, 0, 1)) if abs(ax.z) < 0.9 else Vector((1, 0, 0))
        u = ax.cross(up)
        u.normalize()
        w = ax.cross(u)
        if r1 is None:
            r1 = r
        v = []
        for i in range(n):
            ang = 2.0 * math.pi * i / n
            d = u * math.cos(ang) + w * math.sin(ang)
            q = a + d * r
            v.append((q.x, q.y, q.z))
        for i in range(n):
            ang = 2.0 * math.pi * i / n
            d = u * math.cos(ang) + w * math.sin(ang)
            q = b + d * r1
            v.append((q.x, q.y, q.z))
        f = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
        sm = [False, False]
        for i in range(n):
            j = (i + 1) % n
            f.append((i, j, j + n, i + n))
            sm.append(True)
        self.add(v, f, mat, sm)


def finish(P, name, coll, loc=None, rotz=0.0):
    me = bpy.data.meshes.new(name)
    me.from_pydata(P.v, [], P.f)
    for m in P.mats:
        me.materials.append(m)
    me.polygons.foreach_set("material_index", P.m)
    me.polygons.foreach_set("use_smooth", P.s)
    me.update()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for e in bm.edges:
        lf = e.link_faces
        if len(lf) < 2 or not all(fc.smooth for fc in lf):
            e.smooth = False
    bm.to_mesh(me)
    bm.free()
    me.update()
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    if loc is not None:
        ob.location = loc
        ob.rotation_euler = (0.0, 0.0, rotz)
    TRIS[0] += sum(len(f) - 2 for f in P.f)
    return ob


def beam2d(p0, p1, depth):
    dx = p1[0] - p0[0]
    dz = p1[1] - p0[1]
    L = math.hypot(dx, dz)
    dx /= L
    dz /= L
    nx, nz = -dz * depth * 0.5, dx * depth * 0.5
    return [(p0[0] - nx, p0[1] - nz), (p1[0] - nx, p1[1] - nz),
            (p1[0] + nx, p1[1] + nz), (p0[0] + nx, p0[1] + nz)]


# ---------------------------------------------------------------------------
# Global dimensions
# ---------------------------------------------------------------------------
SL = 1.45 / 3.2
RD = 0.154          # vertical rafter depth
ZB = -0.022         # top of foundation / bottom of wall build-up
XG = 3.17           # half width of gable wall core
WIN = (1.40, 3.65)
RY = [0.23 + i * (4.54 / 7.0) for i in range(8)]
TRUSS_I = (2, 5)


def zu(x):
    return 4.65 - SL * abs(x)


def slab(P, side, xa, xb, v0, v1, y0, y1, mat):
    P.prism([(side * xa, zu(xa) + v0), (side * xb, zu(xb) + v0),
             (side * xb, zu(xb) + v1), (side * xa, zu(xa) + v1)], 'y', y0, y1, mat)


def win_segments(y, zlo, zhi, cut_lo, cut_hi):
    for c in WIN:
        if abs(y - c) < 0.68:
            return [(zlo, cut_lo), (cut_hi, zhi)]
    return [(zlo, zhi)]


# ===========================================================================
# SHELL
# ===========================================================================
# --- Plinth / foundation ---------------------------------------------------
P = Part()
P.box(-3.25, 3.25, -0.05, 5.05, -0.14, -0.05, CONC)
P.frustum(-3.25, 3.25, -0.05, 5.05, -0.05, ZB, 0.028, CONC)
P.prism([(-0.75, -0.14), (-0.05, -0.14), (-0.05, ZB), (-0.16, ZB)], 'x', -1.25, 1.25, CONC_B)
finish(P, "Plinth_Foundation", SHELL)

# --- Front gable wall (door opening) ----------------------------------------
P = Part()
for (ya, yb, mt) in ((0.0, 0.03, WALL), (0.03, 0.17, WOOD_D), (0.17, 0.20, LINING)):
    P.box(-XG, -1.12, ya, yb, ZB, 2.42, mt)
    P.box(1.12, XG, ya, yb, ZB, 2.42, mt)
    P.prism([(-XG, 2.42), (XG, 2.42), (XG, zu(XG)), (0.0, 4.65), (-XG, zu(XG))], 'y', ya, yb, mt)
finish(P, "Wall_Front", SHELL)

# --- Back gable wall ----------------------------------------------------------
P = Part()
for (ya, yb, mt) in ((4.97, 5.0, WALL), (4.83, 4.97, WOOD_D), (4.80, 4.83, LINING)):
    P.prism([(-XG, ZB), (XG, ZB), (XG, zu(XG)), (0.0, 4.65), (-XG, zu(XG))], 'y', ya, yb, mt)
finish(P, "Wall_Back", SHELL)

# --- Left wall ------------------------------------------------------------------
P = Part()
P.box(-3.20, -3.17, 0.0, 5.0, ZB, 2.92, WALL)
P.box(-3.17, -3.03, 0.2, 4.8, ZB, 2.92, WOOD_D)
P.box(-3.03, -3.00, 0.2, 4.8, ZB, 2.92, LINING)
finish(P, "Wall_Left", SHELL)

# --- Right wall with two real window openings -------------------------------
P = Part()
for (xa, xb, ya, yb, mt) in ((3.17, 3.20, 0.0, 5.0, WALL), (3.03, 3.17, 0.2, 4.8, WOOD_D),
                             (3.00, 3.03, 0.2, 4.8, LINING)):
    P.box(xa, xb, ya, yb, ZB, 1.20, mt)
    P.box(xa, xb, ya, yb, 2.20, 2.92, mt)
    for (sa, sb) in ((ya, 0.85), (1.95, 3.10), (4.20, yb)):
        P.box(xa, xb, sa, sb, 1.20, 2.20, mt)
finish(P, "Wall_Right", SHELL)

# --- Wall plates (rafter bearing) ---------------------------------------------
for side, nm in ((-1, "L"), (1, "R")):
    P = Part()
    P.prism([(side * 2.98, 2.92), (side * 3.22, 2.92), (side * 3.22, zu(3.22) - RD),
             (side * 2.98, zu(2.98) - RD)], 'y', -0.25, 5.25, WOOD_D)
    finish(P, "WallPlate_Bearing_" + nm, SHELL)

# --- Board-and-batten cladding strips ----------------------------------------
P = Part()
for i in range(11):
    y = 0.5 + 0.4 * i
    P.box(-3.218, -3.20, y - 0.0225, y + 0.0225, 0.14, 2.92, WALL_B)
    for (za, zb_) in win_segments(y, 0.14, 2.92, 1.16, 2.31):
        P.box(3.20, 3.218, y - 0.0225, y + 0.0225, za, zb_, WALL_B)
for i in range(15):
    x = -2.8 + 0.4 * i
    top = zu(abs(x) + 0.0225) - 0.105
    P.box(x - 0.0225, x + 0.0225, 5.0, 5.018, 0.14, top, WALL_B)
    z0 = 2.58 if abs(x) < 1.3 else 0.14
    P.box(x - 0.0225, x + 0.0225, -0.018, 0.0, z0, top, WALL_B)
finish(P, "Cladding_Battens", SHELL)

# --- Base board, corner boards, gable frieze --------------------------------
P = Part()
P.box(3.20, 3.23, -0.03, 5.03, ZB, 0.14, GREEN_D)
P.box(-3.23, -3.20, -0.03, 5.03, ZB, 0.14, GREEN_D)
P.box(-3.20, 3.20, 5.0, 5.03, ZB, 0.14, GREEN_D)
P.box(-3.20, -1.24, -0.03, 0.0, ZB, 0.14, GREEN_D)
P.box(1.24, 3.20, -0.03, 0.0, ZB, 0.14, GREEN_D)
finish(P, "Trim_BaseBoard", SHELL)

P = Part()
for sx in (-1, 1):
    P.box(sx * 3.08, sx * 3.20, -0.025, 0.0, 0.14, 3.09, GREEN)
    P.box(sx * 3.08, sx * 3.20, 5.0, 5.025, 0.14, 3.09, GREEN)
    P.box(sx * 3.20, sx * 3.225, -0.025, 0.10, 0.14, 2.92, GREEN)
    P.box(sx * 3.20, sx * 3.225, 4.90, 5.025, 0.14, 2.92, GREEN)
finish(P, "Trim_CornerBoards", SHELL)

P = Part()
for side in (-1, 1):
    slab(P, side, 0.0, 3.2, -0.11, 0.0, -0.03, 0.0, GREEN)
    slab(P, side, 0.0, 3.2, -0.11, 0.0, 5.0, 5.03, GREEN)
finish(P, "Trim_GableFrieze", SHELL)

# --- Interior lining joint strips --------------------------------------------
P = Part()
for i in range(7):
    y = 0.8 + 0.6 * i
    P.box(-3.0, -2.992, y - 0.02, y + 0.02, 0.0, 2.92, LINING_D)
    for (za, zb_) in win_segments(y, 0.0, 2.92, 1.10, 2.30):
        P.box(2.992, 3.0, y - 0.02, y + 0.02, za, zb_, LINING_D)
for i in range(9):
    x = -2.4 + 0.6 * i
    top = zu(abs(x) + 0.02)
    P.box(x - 0.02, x + 0.02, 4.792, 4.80, 0.0, top, LINING_D)
    z0 = 2.52 if abs(x) < 1.25 else 0.0
    P.box(x - 0.02, x + 0.02, 0.20, 0.208, z0, top, LINING_D)
finish(P, "Wall_LiningStrips", SHELL)

# --- Door frame, threshold, casings ------------------------------------------
P = Part()
for s in (-1, 1):
    P.box(s * 1.065, s * 1.12, -0.02, 0.02, ZB, 2.365, WOOD)
    P.box(s * 1.05, s * 1.12, 0.02, 0.22, ZB, 2.35, WOOD)
P.box(-1.12, 1.12, -0.02, 0.02, 2.365, 2.42, WOOD)
P.box(-1.12, 1.12, 0.02, 0.22, 2.35, 2.42, WOOD)
# threshold
P.prism([(-0.06, ZB), (0.24, ZB), (0.24, 0.0), (0.20, 0.018), (-0.02, 0.018), (-0.06, 0.0)],
        'x', -1.05, 1.05, WOOD_D)
P.box(-1.05, 1.05, 0.0, 0.06, 0.018, 0.022, STEEL_B)
# interior casing
for s in (-1, 1):
    P.box(s * 1.12, s * 1.20, 0.20, 0.215, 0.0, 2.42, WOOD_L)
P.box(-1.20, 1.20, 0.20, 0.215, 2.42, 2.50, WOOD_L)
finish(P, "Door_Frame_Threshold", SHELL)

P = Part()
for s in (-1, 1):
    P.box(s * 1.12, s * 1.24, -0.028, 0.0, ZB, 2.42, GREEN)
    for z in (0.11, 1.185, 2.29):
        P.box(s * 1.068, s * 1.17, -0.034, -0.028, z - 0.05, z + 0.05, STEEL)
        P.box(s * 1.10, s * 1.116, -0.039, -0.034, z + 0.022, z + 0.038, STEEL_B)
        P.box(s * 1.10, s * 1.116, -0.039, -0.034, z - 0.038, z - 0.022, STEEL_B)
P.box(-1.24, 1.24, -0.028, 0.0, 2.42, 2.54, GREEN)
P.box(-1.27, 1.27, -0.05, 0.0, 2.54, 2.56, STEEL)
finish(P, "Door_Casing_HingePlates", SHELL)

# --- Door leaves (origin on hinge axis, opened 100 deg) ----------------------


def build_leaf(mirror):
    P = Part(mirror=mirror)
    W = 1.058
    z0, z1 = 0.028, 2.357
    T = 0.045
    P.box(0.0, 0.11, 0.0, T, z0, z1, GREEN)
    P.box(W - 0.11, W, 0.0, T, z0, z1, GREEN)
    P.box(0.11, W - 0.11, 0.0, T, z0, z0 + 0.17, GREEN)
    P.box(0.11, W - 0.11, 0.0, T, 1.12, 1.25, GREEN)
    P.box(0.11, W - 0.11, 0.0, T, z1 - 0.13, z1, GREEN)
    u0, u1 = 0.11, W - 0.11
    bw = (u1 - u0) / 6.0
    for i in range(6):
        P.box(u0 + i * bw + 0.002, u0 + (i + 1) * bw - 0.002, 0.014, 0.034,
              z0 + 0.17, z1 - 0.13, GREEN_L if i % 2 == 0 else GREEN)
    # diagonal braces in the recessed panels (exterior side)
    P.prism(beam2d((u0, z0 + 0.22), (u1, 1.07), 0.09), 'y', 0.003, 0.014, GREEN_D)
    P.prism(beam2d((u0, 1.30), (u1, z1 - 0.18), 0.09), 'y', 0.003, 0.014, GREEN_D)
    # strap hinges
    for z in (0.11, 1.185, 2.29):
        P.box(0.0, 0.42, -0.007, 0.0, z - 0.022, z + 0.022, STEEL)
        P.prism([(0.42, z - 0.022), (0.50, z), (0.42, z + 0.022)], 'y', -0.007, 0.0, STEEL)
        P.cyl((-0.002, -0.012, z - 0.055), (-0.002, -0.012, z + 0.055), 0.013, STEEL, 8)
        for u in (0.06, 0.20, 0.36):
            P.box(u - 0.008, u + 0.008, -0.012, -0.007, z - 0.008, z + 0.008, STEEL_B)
    # pull handles on both faces
    for t in (-0.05, T + 0.05):
        P.cyl((W - 0.06, t, 1.02), (W - 0.06, t, 1.26), 0.011, STEEL, 8)
        ta, tb = (t, 0.0) if t < 0 else (T, t)
        P.box(W - 0.07, W - 0.05, ta, tb, 1.045, 1.065, STEEL)
        P.box(W - 0.07, W - 0.05, ta, tb, 1.215, 1.235, STEEL)
    if mirror:
        # meeting strip
        P.box(W - 0.025, W + 0.03, -0.012, 0.0, z0, z1, GREEN_D)
    else:
        # slide bolt on the inside
        P.box(W - 0.095, W - 0.025, T, T + 0.005, 0.10, 0.34, STEEL)
        P.cyl((W - 0.06, T + 0.013, 0.05), (W - 0.06, T + 0.013, 0.36), 0.007, STEEL_B, 6)
        P.box(W - 0.075, W - 0.045, T + 0.005, T + 0.022, 0.14, 0.17, STEEL)
        P.box(W - 0.075, W - 0.045, T + 0.005, T + 0.022, 0.28, 0.31, STEEL)
        P.box(W - 0.066, W - 0.054, T + 0.013, T + 0.04, 0.215, 0.235, STEEL_B)
    return P


finish(build_leaf(False), "Door_Leaf_L", SHELL, (-1.062, -0.036, 0.0), math.radians(-100.0))
finish(build_leaf(True), "Door_Leaf_R", SHELL, (1.062, -0.036, 0.0), math.radians(100.0))

# --- Windows -----------------------------------------------------------------
for wi, c in enumerate(WIN):
    P = Part()
    # reveal lining
    P.box(2.98, 3.20, c - 0.55, c - 0.53, 1.20, 2.20, WOOD_L)
    P.box(2.98, 3.20, c + 0.53, c + 0.55, 1.20, 2.20, WOOD_L)
    P.box(2.98, 3.20, c - 0.53, c + 0.53, 2.18, 2.20, WOOD_L)
    # interior sill, nose and apron
    P.box(3.00, 3.11, c - 0.53, c + 0.53, 1.20, 1.225, WOOD)
    P.box(2.90, 3.00, c - 0.63, c + 0.63, 1.195, 1.225, WOOD)
    P.box(2.975, 3.00, c - 0.60, c + 0.60, 1.125, 1.195, WOOD_M)
    # interior casing
    P.box(2.98, 3.00, c - 0.62, c - 0.55, 1.225, 2.20, WOOD_L)
    P.box(2.98, 3.00, c + 0.55, c + 0.62, 1.225, 2.20, WOOD_L)
    P.box(2.98, 3.00, c - 0.62, c + 0.62, 2.20, 2.27, WOOD_L)
    # sash frame
    P.box(3.11, 3.165, c - 0.53, c - 0.48, 1.20, 2.18, GREEN)
    P.box(3.11, 3.165, c + 0.48, c + 0.53, 1.20, 2.18, GREEN)
    P.box(3.11, 3.165, c - 0.48, c + 0.48, 1.20, 1.285, GREEN)
    P.box(3.11, 3.165, c - 0.48, c + 0.48, 2.13, 2.18, GREEN)
    # glazing bars
    for o in (-0.16, 0.16):
        P.box(3.122, 3.153, c + o - 0.011, c + o + 0.011, 1.285, 2.13, GREEN_D)
    P.box(3.124, 3.151, c - 0.48, c + 0.48, 1.697, 1.719, GREEN_D)
    # glass
    P.box(3.135, 3.140, c - 0.48, c + 0.48, 1.285, 2.13, GLASS)
    # exterior sloped sill
    P.prism([(3.11, 1.20), (3.20, 1.20), (3.20, 1.2086), (3.11, 1.225)], 'y', c - 0.53, c + 0.53, GREEN_D)
    P.prism([(3.20, 1.17), (3.275, 1.17), (3.275, 1.195), (3.20, 1.2086)], 'y', c - 0.63, c + 0.63, GREEN_D)
    # exterior casing and drip cap
    P.box(3.20, 3.225, c - 0.63, c - 0.55, 1.2086, 2.20, GREEN)
    P.box(3.20, 3.225, c + 0.55, c + 0.63, 1.2086, 2.20, GREEN)
    P.box(3.20, 3.225, c - 0.63, c + 0.63, 2.20, 2.28, GREEN)
    P.box(3.20, 3.25, c - 0.65, c + 0.65, 2.28, 2.298, STEEL)
    finish(P, "Window_%d" % (wi + 1), SHELL)

# --- Tie beams with knee braces (stay visible without roof) -------------------
P = Part()
for ti in TRUSS_I:
    ty = RY[ti]
    P.box(-2.98, 2.98, ty - 0.05, ty + 0.05, 2.93, 3.11, WOOD)
    for s in (-1, 1):
        P.prism(beam2d((s * 2.99, 2.42), (s * 2.42, 2.99), 0.08), 'y', ty - 0.035, ty + 0.035, WOOD_M)
        P.box(s * 2.955, s * 3.0, ty - 0.05, ty + 0.05, 2.30, 2.62, WOOD_D)
        P.cyl((s * 2.55, ty - 0.058, 3.02), (s * 2.55, ty + 0.058, 3.02), 0.018, STEEL, 6)
        P.cyl((s * 2.978, ty - 0.02, 2.38), (s * 2.945, ty - 0.02, 2.38), 0.012, STEEL, 6)
        P.cyl((s * 2.978, ty + 0.02, 2.56), (s * 2.945, ty + 0.02, 2.56), 0.012, STEEL, 6)
    P.cyl((0.0, ty - 0.058, 3.02), (0.0, ty + 0.058, 3.02), 0.018, STEEL, 6)
finish(P, "Truss_TieBeams", SHELL)

# ===========================================================================
# ROOF
# ===========================================================================
# --- Rafters ------------------------------------------------------------------
P = Part()
for i, y in enumerate(RY):
    w = 0.10 if i in TRUSS_I else 0.06
    for s in (-1, 1):
        P.prism([(s * 0.04, zu(0.04) - RD), (s * 3.26, zu(3.26) - RD), (s * 3.50, zu(3.50) - 0.085),
                 (s * 3.50, zu(3.50)), (s * 0.04, zu(0.04))], 'y', y - w / 2, y + w / 2,
                WOOD if i % 2 == 0 else WOOD_M)
finish(P, "Roof_Rafters", ROOF)

# --- Ridge beam ----------------------------------------------------------------
P = Part()
P.prism([(-0.04, 4.32), (0.04, 4.32), (0.04, zu(0.04)), (0.0, 4.65), (-0.04, zu(0.04))],
        'y', -0.25, 5.25, WOOD_D)
finish(P, "Roof_RidgeBeam", ROOF)

# --- King posts and struts -----------------------------------------------------
P = Part()
for ti in TRUSS_I:
    ty = RY[ti]
    P.box(-0.06, 0.06, ty - 0.05, ty + 0.05, 3.11, 4.32, WOOD)
    for s in (-1, 1):
        P.prism(beam2d((s * 0.03, 3.17), (s * 1.75, zu(1.75) - RD + 0.03), 0.10),
                'y', ty - 0.04, ty + 0.04, WOOD_M)
        P.cyl((s * 1.62, ty - 0.058, zu(1.62) - RD * 0.5), (s * 1.62, ty + 0.058, zu(1.62) - RD * 0.5),
              0.018, STEEL, 6)
    P.cyl((0.0, ty - 0.058, 3.22), (0.0, ty + 0.058, 3.22), 0.018, STEEL, 6)
    P.cyl((0.0, ty - 0.058, 4.22), (0.0, ty + 0.058, 4.22), 0.018, STEEL, 6)
finish(P, "Roof_KingPosts_Struts", ROOF)

# --- Blocking between rafters above the plate -------------------------------
P = Part()
for s in (-1, 1):
    slab(P, s, 3.16, 3.20, -RD, 0.0, 0.0, 5.0, WOOD_D)
finish(P, "Roof_EaveBlocking", ROOF)

# --- Visible timber sheathing ---------------------------------------------------
P = Part()
NB = 24
bw = 3.56 / NB
tones = (WOOD, WOOD_L, WOOD_M)
for s in (-1, 1):
    for i in range(NB):
        xa = i * bw + (0.0025 if i > 0 else 0.0)
        xb = (i + 1) * bw - (0.0025 if i < NB - 1 else 0.0)
        slab(P, s, xa, xb, 0.0, 0.024, -0.30, 5.30, tones[(i * 7 + (0 if s > 0 else 1)) % 3])
finish(P, "Roof_Sheathing", ROOF)

# --- Standing seam metal skin ---------------------------------------------------
P = Part()
for s in (-1, 1):
    for k in range(14):
        y0 = -0.30 + 0.4 * k
        slab(P, s, 0.0, 3.56, 0.024, 0.036, y0, y0 + 0.4, STEEL if (k + (s > 0)) % 2 == 0 else STEEL_B)
    for k in range(1, 14):
        y = -0.30 + 0.4 * k
        slab(P, s, 0.0, 3.56, 0.036, 0.066, y - 0.012, y + 0.012, STEEL_D)
finish(P, "Roof_MetalSkin", ROOF)

# --- Ridge cap -----------------------------------------------------------------
P = Part()
for s in (-1, 1):
    slab(P, s, 0.0, 0.24, 0.066, 0.078, -0.33, 5.33, STEEL_D)
P.box(-0.028, 0.028, -0.33, 5.33, 4.715, 4.755, STEEL)
finish(P, "Roof_RidgeCap", ROOF)

# --- Verge (Ortgang) and eave (Traufe) trim -----------------------------------
P = Part()
for s in (-1, 1):
    slab(P, s, 0.0, 3.575, -0.03, 0.066, -0.33, -0.30, STEEL_D)
    slab(P, s, 0.0, 3.575, 0.056, 0.066, -0.30, -0.22, STEEL_D)
    slab(P, s, 0.0, 3.575, -0.03, 0.066, 5.30, 5.33, STEEL_D)
    slab(P, s, 0.0, 3.575, 0.056, 0.066, 5.22, 5.30, STEEL_D)
finish(P, "Roof_VergeTrim", ROOF)

P = Part()
for s in (-1, 1):
    slab(P, s, 3.56, 3.575, -0.035, 0.04, -0.30, 5.30, STEEL_D)
finish(P, "Roof_EaveDripEdge", ROOF)

# --- Barge boards --------------------------------------------------------------
P = Part()
for s in (-1, 1):
    slab(P, s, 0.0, 3.555, -0.16, 0.0, -0.30, -0.255, GREEN)
    slab(P, s, 0.0, 3.555, -0.16, 0.0, 5.255, 5.30, GREEN)
finish(P, "Roof_BargeBoards", ROOF)

# ===========================================================================
# INTERIOR
# ===========================================================================
# --- Floor ----------------------------------------------------------------------
P = Part()
for i in range(5):
    xa = -3.0 + 1.2 * i
    P.box(xa + 0.004, xa + 1.196, 0.204, 1.296, ZB, 0.0, CONC_B if i % 2 == 0 else CONC)
finish(P, "Floor_EntryConcrete", INTERIOR)

P = Part()
P.box(-3.0, 3.0, 1.30, 1.34, ZB, 0.004, STEEL_B)
finish(P, "Floor_TransitionStrip", INTERIOR)

P = Part()
ftones = (WOOD_M, WOOD_D, WOOD)
for i in range(30):
    xa = -3.0 + 0.2 * i
    sp = 1.34 + 1.2 + 0.55 * ((i * 3) % 4)
    P.box(xa + 0.003, xa + 0.197, 1.343, sp - 0.003, ZB, 0.0, ftones[(i * 5) % 3])
    P.box(xa + 0.003, xa + 0.197, sp + 0.003, 4.797, ZB, 0.0, ftones[(i * 5 + 1) % 3])
finish(P, "Floor_Planks", INTERIOR)

P = Part()
P.box(-2.22, -1.50, 1.55, 3.65, 0.0, 0.012, RUBBER)
for i in range(6):
    xa = -2.17 + 0.115 * i
    P.box(xa, xa + 0.05, 1.60, 3.60, 0.012, 0.016, RUBBER)
finish(P, "Floor_BenchMat", INTERIOR)

# --- Workbench with vise ----------------------------------------------------------
BY0, BY1 = 1.5, 3.7
P = Part()
sw = 0.7 / 6.0
for i in range(6):
    xa = -2.97 + i * sw
    P.box(xa + 0.001, xa + sw - 0.001, BY0, BY1, 0.82, 0.90, WOOD_L if i % 2 == 0 else WOOD)
P.box(-2.97, -2.27, BY0 - 0.05, BY0, 0.82, 0.90, WOOD_D)
P.box(-2.97, -2.27, BY1, BY1 + 0.05, 0.82, 0.90, WOOD_D)
P.box(-2.35, -2.27, BY0, BY1, 0.74, 0.82, WOOD)
for k in range(5):
    y = 2.62 + 0.21 * k
    P.box(-2.345, -2.323, y - 0.011, y + 0.011, 0.90, 0.902, DARK)
LX = ((-2.93, -2.84), (-2.40, -2.31))
LYS = ((1.66, 1.75), (3.45, 3.54))
for (xa, xb) in LX:
    for (ya, yb) in LYS:
        P.box(xa, xb, ya, yb, 0.0, 0.82, WOOD)
    P.box(xa + 0.02, xb - 0.02, 1.75, 3.45, 0.30, 0.40, WOOD_M)
    # through tenons of the long rails
    P.box(xa + 0.03, xb - 0.03, 1.652, 1.66, 0.32, 0.38, WOOD_DD)
    P.box(xa + 0.03, xb - 0.03, 3.54, 3.548, 0.32, 0.38, WOOD_DD)
P.box(-2.91, -2.86, 1.75, 3.45, 0.72, 0.82, WOOD_M)
for (ya, yb) in LYS:
    P.box(-2.84, -2.40, ya + 0.02, yb - 0.02, 0.16, 0.26, WOOD_M)
    P.box(-2.84, -2.40, ya + 0.02, yb - 0.02, 0.72, 0.82, WOOD_M)
    for (za, zb_) in ((0.18, 0.24), (0.74, 0.80)):
        P.box(-2.31, -2.302, ya + 0.03, yb - 0.03, za, zb_, WOOD_DD)
    yc = (ya + yb) / 2
    P.cyl((-2.314, yc, 0.35), (-2.303, yc, 0.35), 0.009, WOOD_DD, 6)
for i in range(4):
    xa = -2.82 + 0.1 * i
    P.box(xa + 0.002, xa + 0.098, 1.72, 3.48, 0.26, 0.28, WOOD_L if i % 2 else WOOD)
finish(P, "Workbench", INTERIOR)

VY = 2.15
P = Part()
P.box(-2.27, -2.255, VY - 0.21, VY + 0.21, 0.74, 0.90, WOOD_D)       # fixed jaw liner
P.box(-2.225, -2.165, VY - 0.21, VY + 0.21, 0.72, 0.90, WOOD_L)      # moving jaw
P.box(-2.165, -2.15, VY - 0.12, VY + 0.12, 0.735, 0.83, STEEL)       # jaw plate
P.box(-2.62, -2.58, VY - 0.17, VY + 0.17, 0.73, 0.82, STEEL)         # rear bracket
P.cyl((-2.60, VY, 0.78), (-2.10, VY, 0.78), 0.016, TOOL, 10)         # screw
for o in (-0.14, 0.14):
    P.cyl((-2.60, VY + o, 0.78), (-2.165, VY + o, 0.78), 0.011, TOOL, 8)
P.cyl((-2.15, VY, 0.78), (-2.095, VY, 0.78), 0.028, STEEL, 12)       # hub
P.cyl((-2.118, VY, 0.60), (-2.118, VY, 0.86), 0.009, TOOL, 8)        # handle bar
P.cyl((-2.118, VY, 0.585), (-2.118, VY, 0.605), 0.016, WOOD_D, 8)
P.cyl((-2.118, VY, 0.855), (-2.118, VY, 0.875), 0.016, WOOD_D, 8)
P.box(-2.255, -2.225, VY - 0.09, VY + 0.09, 0.76, 1.18, WOOD)        # clamped workpiece
finish(P, "Workbench_Vise", INTERIOR)

P = Part()
# hand plane
P.box(-2.70, -2.64, 2.75, 3.03, 0.90, 0.955, WOOD_D)
P.box(-2.685, -2.655, 2.78, 2.82, 0.955, 1.03, WOOD_M)
P.cyl((-2.67, 2.98, 0.955), (-2.67, 2.98, 1.0), 0.02, WOOD_M, 8)
P.prism([(2.895, 0.955), (2.905, 0.955), (2.875, 1.03), (2.865, 1.03)], 'x', -2.693, -2.647, TOOL)
P.prism([(2.865, 0.955), (2.895, 0.955), (2.86, 1.01)], 'x', -2.69, -2.65, WOOD_L)
# mallet
P.box(-2.75, -2.63, 3.25, 3.34, 0.90, 0.99, WOOD_D)
P.cyl((-2.63, 3.295, 0.945), (-2.36, 3.295, 0.925), 0.016, WOOD_L, 8)
# try square
P.box(-2.72, -2.70, 2.33, 2.50, 0.90, 0.918, WOOD_D)
P.box(-2.92, -2.72, 2.34, 2.375, 0.905, 0.908, TOOL)
# offcuts
P.box(-2.92, -2.62, 1.56, 1.95, 0.90, 0.925, WOOD)
P.box(-2.90, -2.66, 1.60, 1.90, 0.925, 0.95, WOOD_L)
P.box(-2.88, -2.74, 1.63, 1.86, 0.95, 0.99, WOOD_M)
finish(P, "Workbench_Tools", INTERIOR)

# --- Tool wall above the bench ------------------------------------------------------
P = Part()
P.box(-3.0, -2.985, 1.6, 3.6, 1.15, 1.95, LINING)
P.box(-2.985, -2.975, 1.6, 3.6, 1.15, 1.19, WOOD)
P.box(-2.985, -2.975, 1.6, 3.6, 1.91, 1.95, WOOD)
P.box(-2.985, -2.975, 1.6, 1.64, 1.19, 1.91, WOOD)
P.box(-2.985, -2.975, 3.56, 3.6, 1.19, 1.91, WOOD)
# handsaw
P.prism([(1.78, 1.64), (2.38, 1.69), (2.38, 1.72), (1.78, 1.78)], 'x', -2.984, -2.981, TOOL)
P.box(-2.985, -2.963, 1.66, 1.78, 1.60, 1.80, WOOD_D)
P.cyl((-2.985, 1.90, 1.625), (-2.955, 1.90, 1.625), 0.008, WOOD_DD, 6)
# chisel rack
P.box(-2.985, -2.94, 2.50, 3.00, 1.50, 1.53, WOOD)
for i in range(5):
    y = 2.56 + 0.095 * i
    P.cyl((-2.9625, y, 1.53), (-2.9625, y, 1.65), 0.013, WOOD_L if i % 2 == 0 else GREEN, 8)
    P.box(-2.966, -2.959, y - 0.009, y + 0.009, 1.34 + 0.02 * (i % 3), 1.53, TOOL)
# hammer
P.cyl((-2.965, 3.30, 1.30), (-2.965, 3.30, 1.62), 0.012, WOOD_M, 8)
P.box(-2.985, -2.945, 3.24, 3.36, 1.62, 1.665, STEEL)
P.cyl((-2.985, 3.27, 1.605), (-2.94, 3.27, 1.605), 0.007, WOOD_DD, 6)
P.cyl((-2.985, 3.33, 1.605), (-2.94, 3.33, 1.605), 0.007, WOOD_DD, 6)
# small shelf with brackets
P.box(-3.0, -2.80, 1.6, 3.6, 2.0, 2.025, WOOD)
for y in (1.8, 2.6, 3.4):
    P.prism([(-3.0, 2.0), (-2.83, 2.0), (-3.0, 1.84)], 'y', y - 0.012, y + 0.012, WOOD_D)
for i, (y, mt) in enumerate(((1.80, GREEN), (1.96, STEEL_B), (2.12, WALL))):
    P.cyl((-2.90, y, 2.025), (-2.90, y, 2.155), 0.06, mt, 12)
    P.cyl((-2.90, y, 2.155), (-2.90, y, 2.163), 0.062, TOOL, 12)
P.box(-2.97, -2.83, 2.60, 2.90, 2.025, 2.13, WOOD_L)
P.box(-2.96, -2.84, 3.00, 3.40, 2.025, 2.10, WOOD_D)
# clamp rail with three bar clamps
P.box(-3.0, -2.94, 3.82, 4.48, 1.62, 1.66, WOOD)
for y in (3.90, 4.10, 4.30):
    P.cyl((-2.94, y + 0.05, 1.665), (-2.88, y + 0.05, 1.665), 0.008, WOOD_DD, 6)
    P.box(-2.915, -2.90, y - 0.012, y + 0.012, 1.10, 1.71, TOOL)
    P.box(-2.915, -2.90, y, y + 0.11, 1.675, 1.71, STEEL)
    P.box(-2.915, -2.90, y, y + 0.10, 1.30, 1.335, STEEL)
    P.cyl((-2.9075, y + 0.085, 1.20), (-2.9075, y + 0.085, 1.42), 0.006, TOOL, 6)
    P.cyl((-2.9075, y + 0.085, 1.09), (-2.9075, y + 0.085, 1.20), 0.014, WOOD_D, 8)
finish(P, "ToolWall", INTERIOR)

# --- Open shelf at the back ---------------------------------------------------------
SX0, SX1 = -2.9, -1.2
SMID = (SX0 + SX1) / 2
P = Part()
P.box(SX0, SX0 + 0.03, 4.35, 4.79, 0.0, 2.05, WOOD)
P.box(SX1 - 0.03, SX1, 4.35, 4.79, 0.0, 2.05, WOOD)
P.box(SMID - 0.0125, SMID + 0.0125, 4.36, 4.79, 0.10, 1.93, WOOD_M)
SHZ = (0.10, 0.55, 1.0, 1.45, 1.90)
for i, z in enumerate(SHZ):
    P.box(SX0 + 0.03, SX1 - 0.03, 4.35, 4.79, z, z + 0.03, WOOD_L if i % 2 == 0 else WOOD)
    for y in (4.42, 4.64):
        P.box(SX0 - 0.006, SX0, y, y + 0.08, z + 0.004, z + 0.026, WOOD_DD)
        P.box(SX1, SX1 + 0.006, y, y + 0.08, z + 0.004, z + 0.026, WOOD_DD)
P.prism(beam2d((SX0 + 0.03, 0.15), (SX1 - 0.03, 1.90), 0.05), 'y', 4.775, 4.79, WOOD_D)
P.prism(beam2d((SX1 - 0.03, 0.15), (SX0 + 0.03, 1.90), 0.05), 'y', 4.76, 4.775, WOOD_D)
finish(P, "Shelf_Open", INTERIOR)

P = Part()
# bottom: crate and toolbox
P.box(-2.82, -2.14, 4.40, 4.74, 0.13, 0.45, WOOD_D)
P.box(-2.825, -2.135, 4.395, 4.745, 0.40, 0.45, WOOD_M)
P.box(-2.825, -2.135, 4.395, 4.745, 0.13, 0.18, WOOD_M)
P.box(-2.56, -2.40, 4.393, 4.40, 0.31, 0.345, DARK)
P.box(-1.95, -1.35, 4.42, 4.70, 0.13, 0.36, GREEN)
P.box(-1.955, -1.345, 4.415, 4.705, 0.36, 0.385, GREEN_D)
P.cyl((-1.78, 4.56, 0.425), (-1.52, 4.56, 0.425), 0.012, STEEL, 8)
P.box(-1.79, -1.77, 4.55, 4.57, 0.385, 0.43, STEEL)
P.box(-1.53, -1.51, 4.55, 4.57, 0.385, 0.43, STEEL)
P.box(-1.84, -1.80, 4.408, 4.415, 0.33, 0.39, TOOL)
P.box(-1.50, -1.46, 4.408, 4.415, 0.33, 0.39, TOOL)
# cans and sheet stack
for i, (x, mt) in enumerate(((-2.74, GREEN), (-2.56, WALL), (-2.38, STEEL_B), (-2.20, WOOD_D))):
    P.cyl((x, 4.58, 0.58), (x, 4.58, 0.74), 0.075, mt, 12)
    P.cyl((x, 4.58, 0.74), (x, 4.58, 0.75), 0.078, TOOL, 12)
for k in range(4):
    P.box(-1.98 + 0.02 * k, -1.30 - 0.03 * k, 4.41, 4.73, 0.58 + 0.03 * k, 0.607 + 0.03 * k,
          (WOOD_L, WOOD, WOOD_M, WOOD_L)[k])
# jars and boxes
for i in range(5):
    x = -2.76 + 0.15 * i
    P.cyl((x, 4.52, 1.03), (x, 4.52, 1.14), 0.045, GLASS, 10)
    P.cyl((x, 4.52, 1.14), (x, 4.52, 1.155), 0.047, GREEN_D if i % 2 == 0 else STEEL_B, 10)
P.box(-1.95, -1.65, 4.45, 4.72, 1.03, 1.21, WOOD_L)
P.box(-1.58, -1.30, 4.42, 4.70, 1.03, 1.17, WOOD_M)
P.box(-1.54, -1.36, 4.46, 4.66, 1.17, 1.25, GREEN_L)
# offcuts and bottles
for i, h in enumerate((0.30, 0.22, 0.34, 0.18, 0.27, 0.24)):
    x = -2.80 + 0.075 * i
    P.box(x, x + 0.045, 4.45, 4.72, 1.48, 1.48 + h, (WOOD, WOOD_L, WOOD_D)[i % 3])
for i in range(3):
    x = -1.85 + 0.16 * i
    P.cyl((x, 4.55, 1.48), (x, 4.55, 1.63), 0.038, WALL, 10)
    P.cyl((x, 4.55, 1.63), (x, 4.55, 1.69), 0.03, GREEN if i != 1 else STEEL_B, 10, 0.012)
# top
P.box(-2.80, -1.95, 4.45, 4.72, 1.93, 2.06, WOOD_D)
P.box(-2.805, -1.945, 4.445, 4.725, 2.03, 2.06, WOOD_M)
P.cyl((-1.80, 4.58, 1.99), (-1.30, 4.58, 1.99), 0.06, WALL_B, 12)
finish(P, "Shelf_Items", INTERIOR)

# --- Lumber rack and ordered raw timber ---------------------------------------------
ARMZ = (0.30, 0.95, 1.60, 2.15)
P = Part()
for x in (-0.6, 0.9, 2.4):
    P.box(x - 0.04, x + 0.04, 4.70, 4.80, 0.0, 2.40, WOOD_D)
    for z in ARMZ:
        P.box(x - 0.03, x + 0.03, 4.20, 4.70, z - 0.07, z, WOOD)
        P.prism([(4.70, z - 0.07), (4.70, z - 0.30), (4.42, z - 0.07)], 'x', x - 0.02, x + 0.02, WOOD_M)
        P.cyl((x - 0.034, 4.66, z - 0.035), (x + 0.034, 4.66, z - 0.035), 0.012, STEEL, 6)
        P.box(x - 0.03, x + 0.03, 4.18, 4.20, z - 0.07, z + 0.04, WOOD_D)
finish(P, "Lumber_Rack", INTERIOR)

rnd = random.Random(11)
P = Part()
ltones = (WOOD, WOOD_L, WOOD_M, WOOD_D)
LEVELS = ((0.30, 0.14, 0.045, 2, 3, True), (0.95, 0.10, 0.024, 4, 4, False),
          (1.60, 0.07, 0.07, 2, 5, True), (2.15, 0.045, 0.02, 3, 6, False))
for (z, w, t, layers, per, stick) in LEVELS:
    zc = z
    for l in range(layers):
        for j in range(per):
            yb = 4.67 - j * (w + 0.01)
            xa = -0.85 + rnd.uniform(0.0, 0.10)
            xb = 2.85 - rnd.uniform(0.0, 0.85)
            P.box(xa, xb, yb - w, yb, zc, zc + t, ltones[rnd.randrange(4)])
        zc += t
        if stick and l < layers - 1:
            for xs in (-0.55, 0.60, 1.75):
                P.box(xs - 0.015, xs + 0.015, 4.67 - per * (w + 0.01) + 0.01, 4.67, zc, zc + 0.018, WOOD_DD)
            zc += 0.018
finish(P, "Lumber_Stock", INTERIOR)

# leaning boards in the front right corner
P = Part()
dvx, dvz = 0.265, 2.3
dl = math.hypot(dvx, dvz)
dvx /= dl
dvz /= dl
for k, (ya, yb, ln) in enumerate(((0.24, 0.44, 2.30), (0.28, 0.50, 2.05), (0.26, 0.40, 1.80), (0.33, 0.47, 1.55))):
    p0 = (2.72 - 0.03 * k, 0.0)
    p1 = (p0[0] + dvx * ln, dvz * ln)
    P.prism(beam2d(p0, p1, 0.026), 'y', ya, yb, ltones[k])
finish(P, "Lumber_LeaningBoards", INTERIOR)

# --- Sawhorses with workpiece -------------------------------------------------------
P = Part()
for y in (2.1, 3.2):
    P.box(0.90, 1.90, y - 0.045, y + 0.045, 0.70, 0.78, WOOD)
    for x0 in (0.97, 1.785):
        for sg in (-1, 1):
            ybt = y + sg * 0.26
            ytp = y + sg * 0.03
            P.prism([(ybt - 0.03, 0.0), (ybt + 0.03, 0.0), (ytp + 0.03, 0.72), (ytp - 0.03, 0.72)],
                    'x', x0, x0 + 0.045, WOOD_M)
        P.box(x0 - 0.02, x0, y - 0.19, y + 0.19, 0.28, 0.35, WOOD_D)
    P.box(0.99, 1.81, y - 0.015, y + 0.015, 0.30, 0.34, WOOD_D)
P.box(1.15, 1.45, 1.85, 3.45, 0.78, 0.81, WOOD_L)
P.box(1.52, 1.66, 1.95, 3.40, 0.78, 0.82, WOOD)
finish(P, "Sawhorses_Workpiece", INTERIOR)

# --- Stool and bucket -----------------------------------------------------------------
P = Part()
cx, cy = -1.85, 3.20
P.cyl((cx, cy, 0.58), (cx, cy, 0.62), 0.16, WOOD, 14)
for k in range(3):
    a = math.radians(90 + 120 * k)
    P.cyl((cx + 0.20 * math.cos(a), cy + 0.20 * math.sin(a), 0.012),
          (cx + 0.08 * math.cos(a), cy + 0.08 * math.sin(a), 0.585), 0.018, WOOD_M, 8)
    P.cyl((cx + 0.08 * math.cos(a), cy + 0.08 * math.sin(a), 0.62),
          (cx + 0.08 * math.cos(a), cy + 0.08 * math.sin(a), 0.624), 0.012, WOOD_DD, 6)
P.cyl((-2.6, 0.62, 0.0), (-2.6, 0.62, 0.28), 0.12, STEEL_B, 12, 0.15)
P.cyl((-2.6, 0.62, 0.28), (-2.6, 0.62, 0.285), 0.155, TOOL, 12, 0.155)
finish(P, "Stool_Bucket", INTERIOR)

# --- Pendant lamp bodies (mesh only, no light objects) ---------------------------------
P = Part()
for ti in TRUSS_I:
    ty = RY[ti]
    for lx in (-2.0, 1.3):
        P.cyl((lx, ty, 2.36), (lx, ty, 2.93), 0.005, RUBBER, 6)
        P.cyl((lx, ty, 2.36), (lx, ty, 2.22), 0.05, GREEN_D, 12, 0.17)
        P.cyl((lx, ty, 2.36), (lx, ty, 2.40), 0.03, STEEL, 8)
        P.cyl((lx, ty, 2.19), (lx, ty, 2.22), 0.035, BULB, 8)
finish(P, "Lamp_Pendants", INTERIOR)

# ---------------------------------------------------------------------------
# Report, save, export
# ---------------------------------------------------------------------------
print("WORKSHOP triangles:", TRIS[0])
if TRIS[0] > 40000:
    print("WARNING: triangle budget exceeded")

try:
    bpy.context.view_layer.update()
except Exception:
    pass

blend_path = os.path.join(OUT, "workshop.blend")
fbx_path = os.path.join(OUT, "workshop.fbx")

bpy.ops.wm.save_as_mainfile(filepath=blend_path, check_existing=False)

try:
    import addon_utils
    addon_utils.enable("io_scene_fbx", default_set=False)
except Exception:
    pass

try:
    bpy.ops.export_scene.fbx(
        filepath=fbx_path,
        check_existing=False,
        use_selection=False,
        object_types={'MESH'},
        apply_unit_scale=True,
        apply_scale_options='FBX_SCALE_UNITS',
        mesh_smooth_type='FACE',
        use_mesh_modifiers=True,
        bake_anim=False,
        add_leaf_bones=False,
        axis_forward='-Z',
        axis_up='Y',
    )
except Exception as ex:
    print("FBX export with options failed, retrying with defaults:", ex)
    bpy.ops.export_scene.fbx(filepath=fbx_path)

print("Saved:", blend_path)
print("Exported:", fbx_path)