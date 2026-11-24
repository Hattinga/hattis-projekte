"""Face decals for the HQ series: raised ink/label plates, arrows, pictograms.
Language-neutral shapes only; words are SurfaceGui text in Roblox (EN/DE)."""
import math
import bmesh
from mathutils import Vector, Matrix

R = lambda d: math.radians(d)


def face_frame(normal):
    """(right, up) as seen by a viewer looking at a face with this normal."""
    return {
        "+Y": (Vector((-1, 0, 0)), Vector((0, 0, 1))),
        "-Y": (Vector((1, 0, 0)), Vector((0, 0, 1))),
        "+X": (Vector((0, 1, 0)), Vector((0, 0, 1))),
        "-X": (Vector((0, -1, 0)), Vector((0, 0, 1))),
        "+Z": (Vector((1, 0, 0)), Vector((0, 1, 0))),
    }[normal]


def face_matrix(normal, center):
    right, up = face_frame(normal)
    n = right.cross(up)
    m = Matrix((
        (right.x, up.x, n.x, center[0]),
        (right.y, up.y, n.y, center[1]),
        (right.z, up.z, n.z, center[2]),
        (0, 0, 0, 1)))
    return m


def decal_rect(a, normal, center, w, h, mat, t=.002, rot=0.0, off=(0, 0)):
    """Thin raised plate lying on a face. w/h in face-local right/up."""
    m = face_matrix(normal, center) @ Matrix.Translation((off[0], off[1], 0)) @ Matrix.Rotation(R(rot), 4, "Z")
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * w, v.co.y * h, (v.co.z + .5) * t))
    a.add_bm(bm, mat, m, grain=0)


def decal_poly(a, normal, center, pts, mat, t=.002, off=(0, 0), scale=1.0, rot=0.0):
    m = (face_matrix(normal, center) @ Matrix.Translation((off[0], off[1], 0)) @ Matrix.Rotation(R(rot), 4, "Z")
         @ Matrix.Scale(scale, 4))
    a.poly_extrude(pts, 0, t / scale, mat, matrix=m)


def arrow_pts(w=.034, head=.024, shaft_w=.012, shaft=.044):
    """Up arrow outline, base centre at origin, counter-clockwise."""
    s, hw = shaft_w / 2, w / 2
    return [(-s, 0), (s, 0), (s, shaft), (hw, shaft), (0, shaft + head), (-hw, shaft), (-s, shaft)]


def stool_pictogram(a, normal, center, size=.16, mat="Black", t=.002):
    """Language-neutral stool symbol inside a frame, `size` = frame edge."""
    k = size / .16
    f = .006 * k
    for (w, h, ox, oy) in ((size, f, 0, size / 2 - f / 2), (size, f, 0, -size / 2 + f / 2),
                           (f, size, size / 2 - f / 2, 0), (f, size, -size / 2 + f / 2, 0)):
        decal_rect(a, normal, center, w, h, mat, t, off=(ox, oy))
    # stool seen in 3/4: seat slab, three visible legs, front + side rail
    seat = [(-.055, .008), (.035, .008), (.06, .033), (.06, .045), (-.03, .045), (-.055, .02)]
    legs = [[(-.052, -.062), (-.040, -.062), (-.040, .008), (-.052, .008)],
            [(.023, -.062), (.035, -.062), (.035, .008), (.023, .008)],
            [(.050, -.040), (.060, -.040), (.060, .033), (.050, .033)]]
    rails = [[(-.040, -.022), (.023, -.022), (.023, -.012), (-.040, -.012)],
             [(.035, -.022), (.050, -.007), (.050, .002), (.035, -.013)]]
    for poly in [seat] + legs + rails:
        decal_poly(a, normal, center, [(x, y + .006) for x, y in poly], mat, t, scale=k)


def this_way_up(a, normal, center, mat="Black", t=.002, k=1.0):
    for dx in (-.022 * k, .022 * k):
        decal_poly(a, normal, center, arrow_pts(), mat, t, off=(dx, -.032 * k), scale=k)
    decal_rect(a, normal, center, .074 * k, .008 * k, mat, t, off=(0, -.042 * k))




# ------------------------------------------------------- station icons
# All icons fit a 0.08 m square centred on `center` (face-local units).
def _circle(r, n, cx=0.0, cy=0.0, a0=0.0):
    return [(cx + r * math.cos(a0 + 2 * math.pi * i / n), cy + r * math.sin(a0 + 2 * math.pi * i / n)) for i in range(n)]


def icon_flow(a, normal, center, kind, mat="SafetyOrange", t=.0015):
    """Orientation-free pad icons: 'in' = arrow down onto a bar (place here),
    'out' = arrow up off a bar (take from here). Works for mirrored rows."""
    arrow = arrow_pts(w=.034, head=.02, shaft_w=.011, shaft=.03)
    decal_rect(a, normal, center, .056, .008, mat, t, off=(0, -.03))
    if kind == "in":
        decal_poly(a, normal, center, arrow, mat, t, off=(0, .026), rot=180)
    else:
        decal_poly(a, normal, center, arrow, mat, t, off=(0, -.02))


def icon_saw(a, normal, center, mat="SafetyOrange", t=.0015):
    pts = []
    n = 14
    for i in range(n):
        a0 = 2 * math.pi * i / n
        a1 = a0 + 2 * math.pi / n * .55
        pts += [(.024 * math.cos(a0), .024 * math.sin(a0)), (.036 * math.cos(a1), .036 * math.sin(a1))]
    decal_poly(a, normal, center, pts, mat, t)


def icon_hammer(a, normal, center, mat="SafetyOrange", t=.0015):
    # handle tilted 30 deg, head centred on its upper end and perpendicular to it
    decal_rect(a, normal, center, .011, .06, mat, t, off=(-.004, -.01), rot=-30)
    decal_rect(a, normal, center, .048, .017, mat, t, off=(.011, .016), rot=-30)


def icon_drop(a, normal, center, mat="SafetyOrange", t=.0015):
    pts = [(.022 * math.cos(math.radians(d)), -.01 + .022 * math.sin(math.radians(d))) for d in range(-20, 201, 20)]
    pts.append((0, .036))
    decal_poly(a, normal, center, pts, mat, t)


def icon_box(a, normal, center, mat="SafetyOrange", t=.0015):
    decal_rect(a, normal, center, .05, .038, mat, t, off=(0, -.012))
    decal_poly(a, normal, center, [(-.025, .01), (-.002, .01), (-.012, .03), (-.034, .026)], mat, t)
    decal_poly(a, normal, center, [(.002, .01), (.025, .01), (.034, .026), (.012, .03)], mat, t)
