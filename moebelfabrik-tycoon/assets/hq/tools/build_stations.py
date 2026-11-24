"""HQ stations: Saege01, Montagebank01, Finishplatz01, Packtisch01 and the
straight conveyor Band01 (1.0 m and 0.30 m).

Contract (docs/design/DIMENSIONS.md, P01-05):
  * station hull 2.40 x 1.45 x 0.80 m (Blender X x Z x Y), root bottom centre
  * three pads 0.70 x 0.60 m, centres X = -0.80 / 0 / +0.80, top Z = 0.90
  * free goods space above every pad up to Z = 1.45: no fixed geometry there
  * input at -X, process at 0, output at +X (P03-05 convention), operator +Y
  * conveyor: 0.70 m usable width, belt top Z = 0.90
Family look: shared steel frame, dark control strip with orientation-free pad
icons and blank label fields, name board behind the input pad, status lamp
on the back-right post. Moving parts are separate groups (Blade, Turntable,
Fan, StatusLamp) so Studio can animate or recolour them.
Run inside Blender:  exec(open(<this file>).read())
"""
import sys, importlib, math, random
from pathlib import Path
import bpy, bmesh
from mathutils import Vector, Matrix

TOOLS = Path(globals().get("__file__", r"C:/Claudeprojecte/repo/hattis-projekte/moebelfabrik-tycoon/assets/hq/tools/build_stations.py")).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))
import hqlib, hqdecal
importlib.reload(hqlib)
importlib.reload(hqdecal)
from hqlib import Asset
from hqdecal import decal_rect, decal_poly, icon_flow, icon_saw, icon_hammer, icon_drop, icon_box, R

ZP = .90                       # pad top
PADS = (("In", -.80), ("Process", 0.0), ("Out", .80))
PW, PD = .70, .60              # pad footprint
LX, LY = 1.13, .33             # leg centres
TOPF = .86                     # top of the steel frame
SY = .38                       # face of the control strip (2 cm recessed: buttons stay inside 0.40)


# ------------------------------------------------------------- family parts
def frame(a, shelf=True, shelf_mat="WoodBench", shelf_gap=None):
    for sx in (-1, 1):
        for sy in (-1, 1):
            a.box((.06, .06, TOPF - .03), (sx * LX, sy * LY, .03 + (TOPF - .03) / 2), "SteelDark", bevel=.004, segs=2)
            a.cyl(.03, .03, (sx * LX, sy * LY, .015), "Black", segs=12, bevel=.004)       # levelling foot
    for sy in (-1, 1):
        a.box((2 * LX - .06, .04, .04), (0, sy * LY, .14), "SteelDark", bevel=.003, segs=1)
        a.box((2 * LX + .06, .05, .06), (0, sy * LY, TOPF - .03), "SteelDark", bevel=.003, segs=2)
    for sx in (-1, 1):
        a.box((.04, 2 * LY - .06, .04), (sx * LX, 0, .14), "SteelDark", bevel=.003, segs=1)
        a.box((.06, 2 * LY - .06, .06), (sx * LX, 0, TOPF - .03), "SteelDark", bevel=.003, segs=2)
    if shelf:
        spans = [(-LX + .03, LX - .03)] if shelf_gap is None else [(-LX + .03, shelf_gap[0]), (shelf_gap[1], LX - .03)]
        for x0, x1 in spans:
            a.box_mm((x0, -LY + .02, .16), (x1, LY - .02, .178), shelf_mat, bevel=.002, segs=1, grain=0)


def control_strip(a, process_icon, gap=None):
    """Dark strip under the front edge: per pad an icon and a blank label
    field (SurfaceGui anchor). Operator looks at +Y, so +X is on the left."""
    x0, x1 = (-1.18, 1.18) if gap is None else gap
    a.box_mm((x0, .34, .735), (x1, SY, .855), "SteelDark", bevel=.004, segs=2)
    for key, xc in PADS:
        c = Vector((xc, SY, .795))
        if key == "Process":
            process_icon(a, "+Y", c + Vector((.17, 0, 0)))
        else:
            icon_flow(a, "+Y", c + Vector((.17, 0, 0)), key.lower())
        decal_rect(a, "+Y", c + Vector((-.04, 0, 0)), .24, .062, "WallWhite", t=.0015)
        a.marker(f"Label_{key}", (xc - .04, SY + .0015, .795), rot=(90, 0, 180))


def name_board(a, xc=-.80, z0=TOPF, posts=True):
    """Machine name board behind the input pad, facing the operator."""
    if posts:
        for dx in (-.17, .17):
            a.box_mm((xc + dx - .0125, -.3925, z0), (xc + dx + .0125, -.3675, 1.42), "SteelDark", bevel=.002, segs=1)
            a.box_mm((xc + dx - .02, -.37, z0 - .03), (xc + dx + .02, -.345, z0), "SteelDark", bevel=.002, segs=1)
    a.box_mm((xc - .21, -.40, 1.30), (xc + .21, -.37, 1.43), "SteelDark", bevel=.004, segs=2)
    decal_rect(a, "+Y", (xc, -.37, 1.365), .39, .10, "WallWhite", t=.0015)
    a.marker("Label_Name", (xc, -.3685, 1.365), rot=(90, 0, 180))


def status_lamp(a, x=1.16, y=-.37, z0=TOPF, post=True):
    """Signal beacon. Group StatusLamp is one MeshPart: Studio sets its
    Color/Material (Neon) for idle / running / blocked."""
    if post:
        a.box_mm((x - .0125, y - .0125, z0 - .03), (x + .0125, y + .0125, 1.305), "SteelDark", bevel=.002, segs=1)
        a.box_mm((x - .02, y + .0125, z0 - .03), (x + .02, -.355, z0), "SteelDark", bevel=.002, segs=1)
    a.cyl(.03, .02, (x, y, 1.315), "Black", segs=16, bevel=.004)
    a.cyl(.026, .085, (x, y, 1.3675), "WallWhite", segs=16, group="StatusLamp")
    a.cyl(.03, .02, (x, y, 1.42), "Black", segs=16, bevel=.006)
    a.marker("StatusLamp", (x, y, 1.3675))


def roller_bed(a, xc, rollers=7):
    """Roller bed occupying one pad: roller tops at ZP."""
    r = .025
    for sy in (-1, 1):
        y0, y1 = (.302, .335) if sy > 0 else (-.335, -.302)
        a.box_mm((xc - .36, y0, .84), (xc + .36, y1, .893), "SteelDark", bevel=.002, segs=1)
        # orange end caps mark where the pad begins and ends
        for ex in (-1, 1):
            a.box_mm((xc + ex * .36 - (.012 if ex > 0 else 0), y0 - .001, .84), (xc + ex * .36 + (0 if ex > 0 else .012), y1 + .001, .894),
                     "SafetyOrange", bevel=.001, segs=1)
    step = (PW - .10) / (rollers - 1)
    for i in range(rollers):
        x = xc - (PW - .10) / 2 + i * step
        a.cyl(r, .60, (x, 0, ZP - r), "BareSteel", axis="Y", segs=12, bevel=.002)
        for sy in (-1, 1):
            a.cyl(.007, .012, (x, sy * .3015, ZP - r), "Black", axis="Y", segs=6)
    for ex in (-1, 1):
        a.box_mm((xc + ex * .33 - .015, -.30, .80), (xc + ex * .33 + .015, .30, .84), "SteelDark", bevel=.002, segs=1)


def mat_pad(a, xc, z_top=ZP, outline=False, t=.003):
    a.box_mm((xc - PW / 2, -PD / 2, z_top - t), (xc + PW / 2, PD / 2, z_top), "Black", bevel=.0015, segs=1)
    if outline:
        w, h = .012, .0006
        for sy in (-1, 1):
            a.box_mm((xc - PW / 2 + .008, sy * (PD / 2 - .008) - w / 2, z_top), (xc + PW / 2 - .008, sy * (PD / 2 - .008) + w / 2, z_top + h),
                     "SafetyOrange", bevel=0)
        for sx in (-1, 1):
            a.box_mm((xc + sx * (PW / 2 - .008) - w / 2, -PD / 2 + .008, z_top), (xc + sx * (PW / 2 - .008) + w / 2, PD / 2 - .008, z_top + h),
                     "SafetyOrange", bevel=0)


def corner_marks(a, xc, z, arm=.06, w=.012, gap=.006):
    """Orange L-marks just outside the pad corners (never inside the pad)."""
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = xc + sx * (PW / 2 + gap + w / 2), sy * (PD / 2 + gap + w / 2)
            a.box((w, arm, .0008), (cx, cy - sy * (arm / 2 - w / 2), z + .0004), "SafetyOrange", bevel=0)
            a.box((arm, w, .0008), (cx - sx * (arm / 2 - w / 2), cy, z + .0004), "SafetyOrange", bevel=0)


def butcher_top(a, x0, x1, y0, y1, z0, z1, stave=.045, mat="WoodBench"):
    """Laminated top: one slab, glue lines are UV breaks every `stave` m."""
    import build_goods  # noqa: F401  (only for uv_staves)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    sx, sy, sz = x1 - x0, y1 - y0, z1 - z0
    for v in bm.verts:
        v.co = Vector((v.co.x * sx, v.co.y * sy, v.co.z * sz))
    cuts = []
    y = -sy / 2 + stave
    while y < sy / 2 - .01:
        cuts.append(y)
        y += stave
    for c in cuts:
        bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces), plane_co=(0, c, 0), plane_no=(0, 1, 0))
    bm.normal_update()
    edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0) > R(10)]
    bmesh.ops.bevel(bm, geom=edges, offset=.004, offset_type="OFFSET", segments=2, profile=.5, affect="EDGES", clamp_overlap=True)
    rng = random.Random(int(x0 * 1000) + 5)
    build_goods.uv_staves(bm, cuts, [(rng.random(), rng.random()) for _ in range(len(cuts) + 1)])
    a.add_bm(bm, mat, Matrix.Translation(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)), uv=False)


def toothed_disc(r_root, r_tip, teeth):
    pts = []
    for i in range(teeth):
        a0 = 2 * math.pi * i / teeth
        a1 = a0 + 2 * math.pi / teeth * .7
        pts += [(r_root * math.cos(a0), r_root * math.sin(a0)), (r_tip * math.cos(a1), r_tip * math.sin(a1))]
    return pts


# ------------------------------------------------------------------- Säge
def build_saw(col, name="Saege01"):
    a = Asset(name, col, seed=21)
    frame(a, shelf_gap=(-.40, .40), shelf_mat="SteelDark")
    control_strip(a, icon_saw)
    name_board(a)
    status_lamp(a)
    roller_bed(a, -.80)
    roller_bed(a, .80)
    # process table: steel plate, pad = its top, corner marks outside the pad
    a.box_mm((-.40, -.40, .865), (.40, .36, ZP), "BareSteel", bevel=.003, segs=2)
    corner_marks(a, 0, ZP)
    a.box_mm((-.20, -.356, ZP), (.20, -.344, ZP + .0008), "Black", bevel=0)             # blade slot (behind pad)
    # blade (0.40 m) at the back strip, rises 0.10 m above the table; group Blade spins
    bc = Vector((0, -.35, .80))
    m = Matrix.Translation(bc + Vector((0, .0015, 0))) @ Matrix.Rotation(R(90), 4, "X")
    a.poly_extrude(toothed_disc(.19, .20, 48), 0, .003, "BareSteel", matrix=m, group="Blade")
    a.cyl(.045, .012, tuple(bc), "BareSteel", axis="Y", segs=16, group="Blade")
    a.marker("BladeAxis", tuple(bc), rot=(90, 0, 0))
    # guard: orange hood band + clear polycarbonate side plates, all behind the pad
    band = [(.233 * math.cos(R(28 + 124 * i / 18)), .233 * math.sin(R(28 + 124 * i / 18))) for i in range(19)]
    band += [(.213 * math.cos(R(28 + 124 * i / 18)), .213 * math.sin(R(28 + 124 * i / 18))) for i in range(18, -1, -1)]
    m = Matrix.Translation(bc + Vector((0, .028, 0))) @ Matrix.Rotation(R(90), 4, "X")
    a.poly_extrude(band, 0, .056, "SafetyOrange", matrix=m, bevel=.003)
    # D-shaped plates, counter-clockwise: bottom-right, arc over the top, bottom-left
    dplate = [(.225 * math.cos(R(d)), .225 * math.sin(R(d))) for d in range(30, 151, 8)]
    dplate = [(dplate[0][0], .108)] + dplate + [(dplate[-1][0], .108)]
    for dy in (.0255, -.0285):
        m = Matrix.Translation(bc + Vector((0, dy + .003, 0))) @ Matrix.Rotation(R(90), 4, "X")
        a.poly_extrude(dplate, 0, .003, "ClearGuard", matrix=m)
    # guard bracket behind the blade, down to the table
    a.box_mm((-.012, -.398, ZP), (.012, -.381, 1.045), "SteelDark", bevel=.002, segs=1)
    a.box_mm((-.012, -.381, 1.02), (.012, -.373, 1.045), "SteelDark", bevel=.002, segs=1)
    # machine cabinet under the table
    a.box_mm((-.39, -.39, .178), (.39, .33, .865), "SteelGreen", bevel=.008, segs=2)
    a.box_mm((-.30, .33, .26), (.30, .336, .70), "SteelGreen", bevel=.003, segs=1)        # door
    for i in range(5):
        a.box_mm((-.20, .336, .56 - i * .03), (.20, .3375, .572 - i * .03), "Black", bevel=0)  # vents
    a.box_mm((.22, .336, .38), (.24, .352, .50), "BareSteel", bevel=.004, segs=2)          # door handle
    # E-stop + selector on the control strip (operator's right of the label)
    a.box_mm((-.245, SY, .765), (-.185, SY + .004, .825), "SafetyOrange", bevel=.002, segs=1)
    a.cyl(.02, .016, (-.215, SY + .012, .795), "SignalRed", axis="Y", segs=16, bevel=.005)
    a.cyl(.012, .016, (-.30, SY + .008, .795), "Black", axis="Y", segs=12, bevel=.003)
    a.box_mm((-.303, SY + .016, .785), (-.297, SY + .019, .812), "WallWhite", bevel=0)
    # dust bin on the left shelf with hose to the cabinet
    a.cyl(.15, .42, (-.78, -.02, .178 + .21), "SteelGreen", segs=24, bevel=.006)
    a.cyl(.155, .03, (-.78, -.02, .178 + .43), "SteelDark", segs=24, bevel=.006)
    a.tube_path([(-.78, -.02, .64), (-.78, -.05, .70), (-.62, -.20, .74), (-.39, -.24, .74)], .04, "Black", segs=12)
    # toolbox on the right shelf
    a.box_mm((.62, -.12, .178), (.98, .10, .32), "SafetyOrange", bevel=.008, segs=2)
    a.box_mm((.62, -.123, .30), (.98, .103, .305), "SteelDark", bevel=0)
    a.tube_path([(.74, -.01, .32), (.74, -.01, .35), (.86, -.01, .35), (.86, -.01, .32)], .008, "Black", segs=8)
    for key, xc in PADS:
        a.marker(f"Pad_{key}", (xc, 0, ZP))
    return a


# ----------------------------------------------------------- Montagebank
def build_bench(col, name="Montagebank01"):
    a = Asset(name, col, seed=22)
    frame(a, shelf_gap=(-.38, .38))
    butcher_top(a, -1.20, 1.20, -.37, .40, .857, ZP - .003)
    control_strip(a, icon_hammer)
    for key, xc in PADS:
        mat_pad(a, xc, outline=(key == "Process"))
        a.marker(f"Pad_{key}", (xc, 0, ZP))
    # tool wall: two uprights, plywood board, hung tools (all in the back strip)
    for x in (-1.16, 1.16):
        a.box_mm((x - .0125, -.3925, TOPF - .03), (x + .0125, -.3675, 1.305), "SteelDark", bevel=.002, segs=1)
    a.box_mm((-1.14, -.40, .93), (1.14, -.3925, 1.29), "WoodBench", bevel=.002, segs=1, grain=0)
    a.box_mm((-1.15, -.3925, 1.29), (1.15, -.37, 1.305), "SteelDark", bevel=.002, segs=1)    # top rail
    name_board(a, posts=False)
    status_lamp(a, x=1.16, post=False)
    yb = -.3925
    peg = lambda x, z: a.cyl(.004, .03, (x, yb + .015, z), "BareSteel", axis="Y", segs=6)
    # hammer
    a.box_mm((-.335, yb, .95), (-.31, yb + .022, 1.21), "WoodBench", bevel=.003, segs=1, grain=2)
    a.box_mm((-.38, yb, 1.20), (-.265, yb + .03, 1.235), "BareSteel", bevel=.004, segs=2)
    peg(-.345, 1.18), peg(-.30, 1.18)
    # rubber mallet
    a.box_mm((-.165, yb, .97), (-.14, yb + .022, 1.18), "WoodBench", bevel=.003, segs=1, grain=2)
    a.cyl(.032, .12, (-.1525, yb + .034, 1.20), "Black", axis="X", segs=16, bevel=.006)
    peg(-.175, 1.16), peg(-.13, 1.16)
    # two F-clamps (orange jaws)
    for x in (.05, .17):
        a.box_mm((x - .006, yb, .96), (x + .006, yb + .008, 1.26), "BareSteel", bevel=.001, segs=1)
        a.box_mm((x - .006, yb, 1.22), (x + .07, yb + .022, 1.255), "SafetyOrange", bevel=.003, segs=1)
        a.box_mm((x - .006, yb, 1.03), (x + .06, yb + .022, 1.06), "SafetyOrange", bevel=.003, segs=1)
        a.cyl(.012, .07, (x + .045, yb + .011, .99), "Black", axis="Z", segs=10, bevel=.003)
        peg(x - .015, 1.23)
    # try square
    a.box_mm((.33, yb, 1.00), (.35, yb + .016, 1.16), "WoodBench", bevel=.002, segs=1, grain=2)
    a.box_mm((.35, yb + .004, 1.14), (.50, yb + .007, 1.16), "BareSteel", bevel=0)
    peg(.34, 1.17)
    # screwdrivers
    for x in (.62, .67):
        a.cyl(.011, .09, (x, yb + .015, 1.17), "SafetyOrange", segs=8, bevel=.003)
        a.cyl(.003, .12, (x, yb + .015, 1.065), "BareSteel", segs=6)
    a.box_mm((.58, yb, 1.215), (.71, yb + .03, 1.225), "SteelDark", bevel=0)
    # glue shelf with bottles
    a.box_mm((.85, yb, 1.05), (1.10, -.33, 1.065), "WoodBench", bevel=.002, segs=1, grain=0)
    for x in (.89, .95):
        a.cyl(.022, .09, (x, -.355, 1.11), "WallWhite", segs=12, bevel=.004)
        a.cyl(.008, .03, (x, -.355, 1.17), "SafetyOrange", segs=8, r2=.003)
    a.box_mm((1.0, -.385, 1.065), (1.08, -.335, 1.11), "SteelGreen", bevel=.004, segs=1)   # screw box
    # drawer cabinet under the process pad
    a.box_mm((-.37, -.33, .19), (.37, .33, .84), "SteelGreen", bevel=.008, segs=2)
    for i, (z0, z1) in enumerate(((.535, .715), (.365, .52), (.21, .35))):   # all below the control strip
        a.box_mm((-.34, .33, z0), (.34, .336, z1), "SteelGreen", bevel=.003, segs=1)
        zc = (z0 + z1) / 2 + .035
        a.box_mm((-.10, .336, zc - .008), (.10, .352, zc + .008), "SafetyOrange", bevel=.004, segs=1)
    # stacked empty kit trays on the left shelf (narrative: carriers come back)
    for i in range(3):
        a.box_mm((-1.05, -.25, .178 + i * .032), (-.45, .25, .178 + i * .032 + .03), "SteelDark", bevel=.003, segs=1)
    # parts bins on the right shelf
    for i, x in enumerate((.50, .70, .90)):
        a.box_mm((x, -.10, .178), (x + .17, .14, .30), "SafetyOrange" if i == 1 else "SteelGreen", bevel=.006, segs=2)
    return a


# ------------------------------------------------------------- Finishplatz
def build_finish(col, name="Finishplatz01"):
    a = Asset(name, col, seed=23)
    frame(a, shelf_gap=(-.38, .38), shelf_mat="SteelDark")
    control_strip(a, icon_drop)
    name_board(a)
    status_lamp(a)
    # stainless catch tray over the whole top with a low lip
    a.box_mm((-1.18, -.37, .835), (1.18, .36, .86), "BareSteel", bevel=.003, segs=1)
    for sy, (y0, y1) in ((1, (.345, .36)), (-1, (-.37, -.355))):
        a.box_mm((-1.18, y0, .86), (1.18, y1, .885), "BareSteel", bevel=.002, segs=1)
    for sx in (-1, 1):
        a.box_mm((sx * 1.18 - (.015 if sx > 0 else 0), -.355, .86), (sx * 1.18 + (0 if sx > 0 else .015), .345, .885), "BareSteel", bevel=.002, segs=1)
    # drying grates on In/Out
    for key, xc in (("In", -.80), ("Out", .80)):
        for i in range(11):
            x = xc - .33 + i * .066
            a.box_mm((x - .006, -.30, ZP - .022), (x + .006, .30, ZP), "SteelDark", bevel=.0015, segs=1)
        for yy in (-.24, .24):
            a.box_mm((xc - .34, yy - .008, .86), (xc + .34, yy + .008, ZP - .022), "SteelDark", bevel=0)
        a.marker(f"Pad_{key}", (xc, 0, ZP))
    # turntable (group Turntable rotates around its marker)
    a.cyl(.05, .017, (0, 0, .8685), "BareSteel", segs=16)
    a.cyl(.29, .023, (0, 0, ZP - .0115), "SteelDark", segs=40, bevel=.004, bsegs=2, group="Turntable")
    for i in range(4):          # rotation marks: r 0.26..0.29, outside every stool foot (max r 0.255)
        ang = R(45 + 90 * i)
        a.box((.03, .009, .0007), (.275 * math.cos(ang), .275 * math.sin(ang), ZP + .00035), "SafetyOrange",
              bevel=0, rot=(0, 0, 45 + 90 * i), group="Turntable")
    a.marker("Pad_Process", (0, 0, ZP))
    a.marker("TurntableAxis", (0, 0, ZP))
    # spray booth filter wall behind the process pad
    for x in (-.40, .40):
        a.box_mm((x - .02, -.40, .885), (x + .02, -.335, 1.44), "SteelGreen", bevel=.004, segs=1)
    a.box_mm((-.42, -.40, 1.36), (.42, -.335, 1.44), "SteelGreen", bevel=.005, segs=2)
    a.box_mm((-.38, -.395, .885), (.38, -.385, 1.36), "WallWhite", bevel=0)                 # filter mat
    for i in range(7):
        z = .93 + i * .05
        if 1.12 < z < 1.30:
            continue
        a.box_mm((-.38, -.385, z), (.38, -.378, z + .012), "SteelGreen", bevel=0)           # grille
    a.cyl(.105, .006, (0, -.381, 1.21), "Black", axis="Y", segs=28)
    for i in range(5):
        ang = 72 * i
        a.box((.075, .004, .03), (.042 * math.cos(R(ang)), -.374, 1.21 + .042 * math.sin(R(ang))), "BareSteel",
              bevel=0, rot=(20, -ang, 0), group="Fan")
    a.cyl(.02, .012, (0, -.372, 1.21), "BareSteel", axis="Y", segs=12, group="Fan")
    a.marker("FanAxis", (0, -.372, 1.21), rot=(90, 0, 0))
    # spray gun hanging at the right of the booth + hose
    gx = .48
    a.box_mm((gx - .015, -.39, 1.06), (gx + .015, -.36, 1.16), "SafetyOrange", bevel=.006, segs=1)
    a.cyl(.03, .07, (gx, -.37, 1.20), "BareSteel", segs=12, bevel=.006)
    a.cyl(.006, .04, (gx - .03, -.375, 1.15), "BareSteel", axis="X", segs=8)
    a.box_mm((gx - .01, -.385, .99), (gx + .01, -.365, 1.065), "Black", bevel=.003, segs=1)
    a.tube_path([(gx, -.375, .99), (gx + .02, -.38, .93), (gx + .10, -.385, .90), (gx + .14, -.39, .86)], .007, "Black", segs=8)
    # finish cans on a shelf behind the Out pad
    a.box_mm((.70, -.40, 1.05), (1.10, -.33, 1.065), "SteelDark", bevel=.002, segs=1)
    for x in (.77, .88, .99):
        a.cyl(.04, .10, (x, -.359, 1.115), "BareSteel", segs=16, bevel=.004)
        a.cyl(.0405, .045, (x, -.359, 1.11), "SafetyOrange", segs=16)
        a.cyl(.036, .006, (x, -.359, 1.168), "Black", segs=16)
    # cabinet under the turntable + buckets on the shelf
    a.box_mm((-.37, -.33, .19), (.37, .33, .835), "SteelGreen", bevel=.008, segs=2)
    a.box_mm((-.33, .33, .25), (.33, .336, .78), "SteelGreen", bevel=.003, segs=1)
    for i in range(4):
        a.box_mm((-.18, .336, .66 - i * .03), (.18, .3375, .672 - i * .03), "Black", bevel=0)
    a.box_mm((.22, .336, .40), (.24, .352, .52), "BareSteel", bevel=.004, segs=2)
    for x, c in ((-.85, "SafetyOrange"), (-.60, "WallWhite"), (.65, "WallWhite")):
        a.cyl(.11, .20, (x, 0, .178 + .10), c, segs=20, r2=.12, bevel=.006)
        a.cyl(.113, .012, (x, 0, .178 + .20), "Black", segs=20)
    return a


# --------------------------------------------------------------- Packtisch
def build_pack(col, name="Packtisch01"):
    a = Asset(name, col, seed=24)
    frame(a, shelf_gap=None, shelf_mat="SteelDark")
    control_strip(a, icon_box)
    # laminated top over In + Process, edge band; Out is a roller bed
    a.box_mm((-1.198, -.37, .867), (.415, .398, ZP - .003), "WallWhite", bevel=.003, segs=2)
    a.box_mm((-1.20, -.372, .875), (.417, .40, .889), "SteelDark", bevel=.001, segs=1)     # edge band
    mat_pad(a, -.80)
    mat_pad(a, 0, outline=True)
    roller_bed(a, .80)
    for key, xc in PADS:
        a.marker(f"Pad_{key}", (xc, 0, ZP))
    name_board(a, posts=False)
    status_lamp(a)
    # back rail system: uprights, kraft roll, tape rolls, tape gun
    for x in (-1.16, .44):
        a.box_mm((x - .0125, -.3925, TOPF - .03), (x + .0125, -.3675, 1.43), "SteelDark", bevel=.002, segs=1)
    # (name board hangs on the two uprights' cross rail)
    a.box_mm((-1.16, -.3925, 1.285), (.44, -.3725, 1.30), "SteelDark", bevel=.002, segs=1)
    for x in (-1.10, -.50):
        a.box_mm((x - .01, -.3925, .98), (x + .01, -.33, 1.00), "SteelDark", bevel=.002, segs=1)
    a.cyl(.006, .64, (-.80, -.355, 1.03), "BareSteel", axis="X", segs=8)
    a.cyl(.042, .56, (-.80, -.355, 1.03), "Cardboard", axis="X", segs=20, bevel=.004)
    a.box_mm((-1.08, -.398, .905), (-.52, -.39, 1.0), "Cardboard", bevel=0, grain=0)       # paper tail
    a.cyl(.004, .42, (-.15, -.355, 1.20), "BareSteel", axis="X", segs=6)
    for x in (-.30, -.20, -.10):
        a.cyl(.045, .048, (x, -.355, 1.20), "SafetyOrange", axis="X", segs=20, bevel=.004)
        a.cyl(.03, .05, (x, -.355, 1.20), "Cardboard", axis="X", segs=12)
    for x in (-.36, .06):
        a.box_mm((x - .006, -.3925, 1.19), (x + .006, -.355, 1.21), "SteelDark", bevel=0)
    # tape gun on the rail hook
    a.box_mm((.12, -.385, 1.06), (.30, -.355, 1.10), "SafetyOrange", bevel=.008, segs=2)
    a.cyl(.05, .035, (.24, -.37, 1.14), "Cardboard", axis="Y", segs=20, bevel=.003)
    a.box_mm((.13, -.38, .99), (.16, -.36, 1.065), "Black", bevel=.006, segs=1)
    a.box_mm((.15, -.3925, 1.10), (.17, -.37, 1.19), "SteelDark", bevel=0)
    # flat carton blanks stacked on the shelf + a box of tape rolls
    rng = random.Random(9)
    for i in range(9):
        dx, dy = rng.uniform(-.008, .008), rng.uniform(-.006, .006)
        a.box_mm((-1.02 + dx, -.27 + dy, .178 + i * .009), (-.08 + dx, .25 + dy, .178 + i * .009 + .008), "Cardboard",
                 bevel=.0015, segs=1, grain=0)
    a.box_mm((.25, -.15, .178), (.55, .15, .40), "Cardboard", bevel=.005, segs=2, grain=2)
    a.box_mm((.25, -.0225, .40), (.55, .0225, .4015), "SafetyOrange", bevel=0)
    return a


# --------------------------------------------------------------------- Band
def build_belt(col, name, L, motor=True):
    """Straight conveyor module, length L along X, flow +X. Belt top Z=0.90,
    usable width 0.70 m, side profiles outside the usable width."""
    a = Asset(name, col, seed=25)
    hx = L / 2
    r = .035
    zc = ZP - r
    # belt loop: stadium profile in XZ, extruded across Y (rubber, ribs across)
    prof = [(hx - r + r * math.cos(R(t)), zc + r * math.sin(R(t))) for t in range(-90, 91, 15)]
    prof += [(-hx + r + r * math.cos(R(t)), zc + r * math.sin(R(t))) for t in range(90, 271, 15)]
    m = Matrix.Translation((0, .35, 0)) @ Matrix.Rotation(R(90), 4, "X")
    a.poly_extrude(prof, 0, .70, "BeltRubber", matrix=m, grain=0)
    # drums: axle ends visible in the profiles
    for sx in (-1, 1):
        a.cyl(.012, .80, (sx * (hx - r), 0, zc), "BareSteel", axis="Y", segs=10)
    # aluminium side profiles with T-slots, orange connector caps
    for sy in (-1, 1):
        y0, y1 = (.356, .394) if sy > 0 else (-.394, -.356)
        a.box_mm((-hx + .012, y0, .79), (hx - .012, y1, .912), "BareSteel", bevel=.003, segs=1)
        yo = y1 if sy > 0 else y0
        for z in (.82, .875):                                         # T-slot lines
            a.box_mm((-hx + .02, min(yo, yo + sy * .0008), z), (hx - .02, max(yo, yo + sy * .0008), z + .008), "Black", bevel=0)
        for sx in (-1, 1):
            a.box_mm((sx * hx - (.012 if sx > 0 else 0), y0 - .002, .785), (sx * hx + (0 if sx > 0 else .012), y1 + .002, .916),
                     "SafetyOrange", bevel=.002, segs=1)
        # flow chevrons (+X) on the outer face
        nrm = "+Y" if sy > 0 else "-Y"
        rot = 90 if sy > 0 else -90
        n_ch = max(1, int(L / .35))
        for i in range(n_ch):
            x = -hx + L * (i + .5) / n_ch
            ch = [(-.012, -.018), (.0, -.018), (.018, 0), (.0, .018), (-.012, .018), (.006, 0)]
            hqdecal.decal_poly(a, nrm, (x, yo, .8505), ch, "SafetyOrange", t=.0015, rot=0 if sy < 0 else 180)
    # legs and bracing
    leg_x = [0.0] if L < .6 else [-hx + .10, hx - .10]
    for x in leg_x:
        for sy in (-1, 1):
            a.box_mm((x - .025, sy * .345 - .025, .03), (x + .025, sy * .345 + .025, .79), "SteelDark", bevel=.003, segs=1)
            a.cyl(.028, .03, (x, sy * .345, .015), "Black", segs=12, bevel=.004)
        a.box_mm((x - .02, -.32, .30), (x + .02, .32, .34), "SteelDark", bevel=.002, segs=1)
    if len(leg_x) == 2:
        for sy in (-1, 1):
            a.box_mm((leg_x[0], sy * .345 - .02, .30), (leg_x[1], sy * .345 + .02, .34), "SteelDark", bevel=.002, segs=1)
    # gear motor under the outfeed drum
    if motor:
        mx = hx - .16
        a.box_mm((mx - .07, -.12, .66), (mx + .07, .06, .79), "SteelGreen", bevel=.008, segs=2)
        a.cyl(.055, .20, (mx, .14, .72), "SteelGreen", axis="Y", segs=20, bevel=.006)
        a.cyl(.057, .02, (mx, .25, .72), "SteelDark", axis="Y", segs=20, bevel=.004)
        for i in range(6):
            a.box((.004, .16, .012), (mx + .052 * math.sin(R(60 * i)), .14, .72 + .052 * math.cos(R(60 * i))),
                  "SteelGreen", bevel=0, rot=(0, 60 * i, 0))                                # cooling fins
    a.marker("In", (-hx, 0, ZP))
    a.marker("Out", (hx, 0, ZP))
    a.marker("Buffer", (0, 0, ZP))
    return a


def build_all(export=True):
    col = hqlib.clear_collection("HQ_Stations")
    hqlib._MATS.clear()
    assets = [build_saw(col), build_bench(col), build_finish(col), build_pack(col),
              build_belt(col, "Band01_1m", 1.0), build_belt(col, "Band01_030", .30, motor=False)]
    places = [(0, 3, 0), (0, 4.5, 0), (0, 6, 0), (0, 7.5, 0), (2.2, 9, 0), (3.3, 9, 0)]
    for a, p in zip(assets, places):
        a.finish(location=p)
    if export:
        out = hqlib.HQ / "exports"
        for a in assets:
            hqlib.export_asset(a, out)
        hqlib.write_manifest(hqlib.HQ / "manifest-stations.json", assets)
    return assets


if __name__ == "__main__":
    ASSETS = build_all(export=globals().get("HQ_EXPORT", False))
    for a in ASSETS:
        s = a.stats()
        print(f"{a.name:16s} tris={s['tris']:5d} parts={s['mesh_parts']:2d} size={s['bounds_m']['size']} min={s['bounds_m']['min']}")
