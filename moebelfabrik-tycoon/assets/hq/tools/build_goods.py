"""HQ goods: Hocker01 raw/finish, open kit on tray, wood bundle, carton.

All dimensions follow docs/design/DIMENSIONS.md (P01-03). Blender metres,
Z up, front +Y; Roblox Z = -Blender Y (pack layout values converted).
Run inside Blender:  exec(open(<this file>).read())
"""
import sys, importlib, math, random
from pathlib import Path
import bpy, bmesh
from mathutils import Vector, Matrix

TOOLS = Path(globals().get("__file__", r"C:/Claudeprojecte/repo/hattis-projekte/moebelfabrik-tycoon/assets/hq/tools/build_goods.py")).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))
import hqlib
importlib.reload(hqlib)
from hqlib import Asset, TILE_M

R = lambda d: math.radians(d)


import hqdecal
importlib.reload(hqdecal)
from hqdecal import face_frame, face_matrix, decal_rect, decal_poly, arrow_pts, stool_pictogram, this_way_up


# -------------------------------------------------------------- stool parts
LEG_C = .1625           # leg centre lines
LEG = .035
SEAT_Z0, SEAT_Z1 = .425, .450
RAIL_Z0, RAIL_Z1 = .30, .36
RAIL_C = .165           # rail centre line: 5 mm reveal to leg face (0.18)
RAIL_T = .02
TAPER = .007            # inner faces of the leg move out by 7 mm at the foot


def leg_piece(length=SEAT_Z0, taper=TAPER, bevel=.002):
    """Leg in its own frame: outer faces at +x/+y, foot at z=0, head at z=length.
    Inner faces (-x, -y) taper from the rail bottom to the foot."""
    h = LEG / 2
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * LEG, v.co.y * LEG, (v.co.z + .5) * length))
    # ring at taper start
    bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                           plane_co=(0, 0, RAIL_Z0 * length / SEAT_Z0), plane_no=(0, 0, 1))
    for v in bm.verts:
        if v.co.z < 1e-6:
            if v.co.x < 0:
                v.co.x += taper
            if v.co.y < 0:
                v.co.y += taper
    bm.normal_update()
    edges = [e for e in bm.edges if e.calc_face_angle(0) > R(10)]
    bmesh.ops.bevel(bm, geom=edges, offset=bevel, offset_type="OFFSET", segments=2, profile=.5,
                    affect="EDGES", clamp_overlap=True)
    return bm


def seat_piece(size=.40, thick=.025, staves=3, bevel=.004):
    """Seat glued from `staves` boards: geometry is one slab, the glue lines
    are UV discontinuities (grain shifts per stave) -> no extra parts."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size, v.co.y * size, v.co.z * thick))
    cuts = [-size / 2 + size * i / staves for i in range(1, staves)]
    for c in cuts:
        bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                               plane_co=(0, c, 0), plane_no=(0, 1, 0))
    bm.normal_update()
    edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0) > R(10)]
    bmesh.ops.bevel(bm, geom=edges, offset=bevel, offset_type="OFFSET", segments=3, profile=.5,
                    affect="EDGES", clamp_overlap=True)
    return bm, cuts


def uv_staves(bm, cuts, offsets, grain=0):
    uv = bm.loops.layers.uv.verify()
    bm.normal_update()
    edges = [-1e9] + cuts + [1e9]
    for f in bm.faces:
        cy = f.calc_center_median().y
        band = next(i for i in range(len(edges) - 1) if edges[i] <= cy < edges[i + 1])
        off = offsets[band]
        n = f.normal
        a = max(range(3), key=lambda i: abs(n[i]))
        if a != grain:
            ui, vi = grain, 3 - a - grain
        else:
            ui, vi = [i for i in range(3) if i != a]
        for l in f.loops:
            co = l.vert.co
            l[uv].uv = (co[ui] / TILE_M + off[0], co[vi] / TILE_M + off[1])


def build_stool(col, name, wood, label=True):
    a = Asset(name, col, seed=7)          # same seed -> raw/finish share grain
    rng = random.Random(42)
    # seat ------------------------------------------------------------
    top = SEAT_Z1 - .0004                    # tenon ends stand 0.4 mm proud, envelope stays 0.450
    bm, cuts = seat_piece(thick=top - SEAT_Z0)
    uv_staves(bm, cuts, [(rng.random(), rng.random()) for _ in range(3)])
    a.add_bm(bm, wood, Matrix.Translation((0, 0, (SEAT_Z0 + top) / 2)), uv=False)
    # through-tenons: end-grain squares (grain=2 -> rings on the top face)
    for sx in (-1, 1):
        for sy in (-1, 1):
            a.box((.022, .022, .0012), (sx * LEG_C, sy * LEG_C, SEAT_Z1 - .0006), wood,
                  bevel=.0005, segs=1, grain=2)
    # legs ------------------------------------------------------------
    for i, (sx, sy, rz) in enumerate(((1, 1, 0), (-1, 1, 90), (-1, -1, 180), (1, -1, 270))):
        m = Matrix.Translation((sx * LEG_C, sy * LEG_C, 0)) @ Matrix.Rotation(R(rz), 4, "Z")
        a.add_bm(leg_piece(), wood, m, grain=2, uv_off=(rng.random(), rng.random()))
        # dowel ends on both outer faces, at rail height
        for face_axis in ("x", "y"):
            for z in (.316, .344):
                if face_axis == "x":
                    loc = (sx * (LEG_C + LEG / 2), sy * RAIL_C, z)
                    a.cyl(.0042, .0016, loc, wood, axis="X", segs=8)
                else:
                    loc = (sx * RAIL_C, sy * (LEG_C + LEG / 2), z)
                    a.cyl(.0042, .0016, loc, wood, axis="Y", segs=8)
    # rails (Zargen): between leg inner faces, 0.29 long --------------
    inner = LEG_C - LEG / 2
    zc = (RAIL_Z0 + RAIL_Z1) / 2
    for sy in (-1, 1):
        a.box((2 * inner, RAIL_T, RAIL_Z1 - RAIL_Z0), (0, sy * RAIL_C, zc), wood,
              bevel=.0015, segs=2, grain=0, uv_off=(rng.random(), rng.random()))
    for sx in (-1, 1):
        a.box((RAIL_T, 2 * inner, RAIL_Z1 - RAIL_Z0), (sx * RAIL_C, 0, zc), wood,
              bevel=.0015, segs=2, grain=1, uv_off=(rng.random(), rng.random()))
    # stage label: small paper tag on the front rail (text = SurfaceGui)
    if label:
        y = RAIL_C + RAIL_T / 2
        a.box((.085, .0012, .034), (0, y + .0006, zc), "WallWhite", bevel=0)
        a.marker("Label", (0, y + .0012, zc), rot=(90, 0, 0))
    a.marker("Grip", (0, 0, RAIL_Z1))
    return a


def build_kit(col, name="Hocker01_Kit"):
    """Open kit: steel tray + 9 parts in the exact pack layout (P01-03)."""
    a = Asset(name, col, seed=11)
    rng = random.Random(43)
    wood = "WoodRaw"
    # tray -------------------------------------------------------------
    a.box((.60, .50, .01), (0, 0, .005), "SteelDark", bevel=.003, segs=2)
    for sx in (-1, 1):
        a.box((.01, .50, .03), (sx * .295, 0, .015), "SteelDark", bevel=.002, segs=2)
    a.box((.58, .01, .03), (0, -.245, .015), "SteelDark", bevel=.002, segs=2)
    a.box((.58, .0088, .03), (0, .2444, .015), "SteelDark", bevel=.002, segs=2)   # front rim carries the sticker
    # open handles on the short ends, up to 0.18 m, outside the usable 0.58x0.48 plan
    for sx in (-1, 1):
        x = sx * .2945
        r = .005
        path = [(x, -.15, .03), (x, -.15, .15), (x, -.13, .174), (x, .13, .174), (x, .15, .15), (x, .15, .03)]
        a.tube_path(path, r, "SafetyOrange", segs=10)
        a.tube_path([(x, -.145, .15), (x, -.129, .169)], r * .9, "SafetyOrange", segs=8)
    # parts (Roblox Z -> Blender -Y; all Y ranges below already converted)
    # seat: X -0.285..+0.115, depth -0.20..0.20, Z 0.01..0.035
    bm, cuts = seat_piece()
    uv_staves(bm, cuts, [(rng.random(), rng.random()) for _ in range(3)])
    a.add_bm(bm, wood, Matrix.Translation((-.085, 0, .0225)), uv=False)
    # four legs lying along Y, X lower edges .130/.170/.210/.250, Z 0.01..0.045
    for x0 in (.130, .170, .210, .250):
        m = (Matrix.Translation((x0 + LEG / 2, .2125, .01 + LEG / 2)) @ Matrix.Rotation(R(90), 4, "X")
             @ Matrix.Translation((0, 0, 0)))
        bm = leg_piece()
        # leg frame: z along the leg (0..0.425); centre it on its own cross-section
        bm.transform(Matrix.Translation((0, 0, 0)))
        a.add_bm(bm, wood, m, grain=2, uv_off=(rng.random(), rng.random()))
    # four rails lying flat: X -0.225..+0.065, Y centres +-0.105/0.035, Z 0.035..0.055
    for yc in (.105, .035, -.035, -.105):
        a.box((.29, .06, .02), (-.08, yc, .045), wood, bevel=.0015, segs=2, grain=0,
              uv_off=(rng.random(), rng.random()))
    # label sticker on the front rim
    a.box((.09, .0012, .022), (.12, .2494, .015), "WallWhite", bevel=0)
    a.marker("Label", (.12, .25, .015), rot=(90, 0, 0))
    for sx in (-1, 1):
        a.marker(f"Grip{'R' if sx > 0 else 'L'}", (sx * .295, 0, .174))
    return a


def build_bundle(col, name="Holzpaket01"):
    """Rough boards strapped into one bundle: 0.60 x 0.45 x 0.15 m outer."""
    a = Asset(name, col, seed=13)
    rng = random.Random(44)
    wood = "WoodRaw"
    # skids under the bundle (two battens across)
    for sx in (-1, 1):
        a.box((.05, .43, .01), (sx * .24, 0, .005), wood, bevel=.0015, segs=1, grain=1)
    # board layers inside 0.58 x 0.43 x 0.13 (z 0.01..0.14)
    layers = [(.034, [.140, .140, .140]), (.032, [.10, .10, .10, .10]), (.032, [.14, .14, .14]),
              (.032, [.20, .21])]
    z = .01
    for li, (t, widths) in enumerate(layers):
        gap = (.43 - sum(widths)) / (len(widths) - 1) if len(widths) > 1 else 0
        y = -.215
        for w in widths:
            L = .58 - rng.uniform(0, .012)
            dx = rng.uniform(-.004, .004)
            dy = rng.uniform(-.0015, .0015)
            rot = (0, 0, rng.uniform(-.35, .35))
            a.box((L, w - .002, t - .0015), (dx, y + w / 2 + dy, z + t / 2), wood,
                  bevel=.0018, segs=1, grain=0, rot=rot, uv_off=(rng.random(), rng.random()))
            y += w + gap
        z += t
    top = z  # ~0.14
    # cardboard edge protectors along the four long edges (L profile, 3 mm)
    # cardboard edge protectors only where the straps cross the edges
    p, leg, pl = .003, .035, .07
    for px in (-.13, .13):
        for sy in (-1, 1):
            for zz, sz in ((top, 1), (.01, -1)):
                a.box((pl, leg, p), (px, sy * (.215 - leg / 2 + .001), zz + sz * p / 2), "Cardboard",
                      bevel=.001, segs=1, grain=0)
                a.box((pl, p, leg), (px, sy * (.215 + p / 2), zz - sz * leg / 2), "Cardboard",
                      bevel=.001, segs=1, grain=0)
    # two PET straps around protectors, 16 mm wide, with steel seals
    st, sw = .0018, .016
    yo = .215 + p + st / 2
    zt, zb = top + p + st / 2, .01 - p - st / 2
    for sx in (-1, 1):
        x = sx * .13
        a.box((sw, 2 * yo + st, st), (x, 0, zt), "SafetyOrange", bevel=.0005, segs=1)
        a.box((sw, 2 * yo + st, st), (x, 0, zb), "SafetyOrange", bevel=.0005, segs=1)
        for sy in (-1, 1):
            a.box((sw, st, zt - zb + st), (x, sy * yo, (zt + zb) / 2), "SafetyOrange", bevel=.0005, segs=1)
    # symbol tag on the front: seat / leg / rail shapes, language-neutral
    zc = .075
    yfront = .215 + .0005
    a.box((.11, .0012, .06), (-.05, yfront + .0006, zc), "WallWhite", bevel=0)
    for (w, h, ox) in ((.022, .022, -.088), (.007, .036, -.065), (.03, .008, -.04)):
        a.box((w, .0012, h), (ox, yfront + .0018, zc + .008), "SafetyOrange", bevel=0)
    a.marker("Label", (-.01, yfront + .0012, zc - .012), rot=(90, 0, 0))
    return a


def build_carton(col, name="Hockerkarton01"):
    """0.46 x 0.46 x 0.51 m carton, wall 10 mm, orange factory tape, ink print."""
    a = Asset(name, col, seed=17)
    W, H = .46, .51
    a.box((W - .004, W - .004, H - .002), (0, 0, (H - .002) / 2), "Cardboard", bevel=.004, segs=2, grain=2)
    # flap seam: shallow groove simulated by two slightly raised flap edges
    for sy in (-1, 1):
        a.box((W - .02, .002, .0015), (0, sy * .0035, H - .002 + .0004), "Cardboard", bevel=0, grain=0)
    # tape along the seam, over the top and 70 mm down both X faces
    tw, tt = .048, .0012
    a.box((W - .002, tw, tt), (0, 0, H - .002 + tt / 2), "SafetyOrange", bevel=.0004, segs=1)
    for sx in (-1, 1):
        a.box((tt, tw, .07), (sx * ((W - .004) / 2 + tt / 2), 0, H - .002 - .035), "SafetyOrange",
              bevel=.0004, segs=1)
    hw = (W - .004) / 2
    # print: pictogram on all four sides, arrows on front/back, labels front + top
    for nrm, c in (("+Y", (0, hw, 0)), ("-Y", (0, -hw, 0)), ("+X", (hw, 0, 0)), ("-X", (-hw, 0, 0))):
        right, up = face_frame(nrm)
        base = Vector(c) + Vector((0, 0, .29))
        stool_pictogram(a, nrm, base - right * .1, size=.15, t=.0015)
        if nrm in ("+Y", "-Y"):
            this_way_up(a, nrm, base + right * .12 + up * .08, t=.0015)
    # white label fields (text by SurfaceGui; markers give the anchor frame)
    lw, lh = .17, .085
    fc = Vector((0, hw, .12))
    decal_rect(a, "+Y", fc, lw, lh, "WallWhite", t=.0012, off=(.07, 0))
    a.marker("Label_Front", tuple(fc + Vector((-.07, .0012, 0))), rot=(90, 0, 180))
    tc = Vector((0, -.14, H - .002))
    decal_rect(a, "+Z", tc, lw, lh, "WallWhite", t=.0012)
    a.marker("Label_Top", tuple(tc + Vector((0, 0, .0012))))
    return a


def build_all(export=True):
    col = hqlib.clear_collection("HQ_Goods")
    hqlib._MATS.clear()
    assets = [
        build_stool(col, "Hocker01_Raw", "WoodRaw"),
        build_stool(col, "Hocker01_Finish", "WoodFinish"),
        build_kit(col),
        build_bundle(col),
        build_carton(col),
    ]
    xs = [0, .7, 1.5, 2.4, 3.2]
    for a, x in zip(assets, xs):
        a.finish(location=(x, 0, 0))
    if export:
        out = hqlib.HQ / "exports"
        for a in assets:
            hqlib.export_asset(a, out)
        hqlib.write_manifest(hqlib.HQ / "manifest-goods.json", assets)
    return assets


if __name__ == "__main__":
    hqlib.new_scene("HQ_Assets")
    ASSETS = build_all(export=globals().get("HQ_EXPORT", False))
    for a in ASSETS:
        s = a.stats()
        print(f"{a.name:18s} tris={s['tris']:5d} parts={s['mesh_parts']} size={s['bounds_m']['size']}")
