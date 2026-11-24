"""Documentation renders for the HQ batch. Run inside Blender after
build_goods.py and build_stations.py (same session). Writes assets/hq/renders/."""
import sys, importlib, math
from pathlib import Path
import bpy

TOOLS = Path(globals().get("__file__", r"C:/Claudeprojecte/repo/hattis-projekte/moebelfabrik-tycoon/assets/hq/tools/render.py")).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))
import preview
importlib.reload(preview)

OUT = TOOLS.parent / "renders"
OUT.mkdir(exist_ok=True)


NAMES = ("Hocker01_Raw", "Hocker01_Finish", "Hocker01_Kit", "Holzpaket01", "Hockerkarton01",
         "Saege01", "Montagebank01", "Finishplatz01", "Packtisch01", "Band01_1m", "Band01_030")


def roots():
    """Asset root empties carry the asset name exactly."""
    return {n: bpy.data.objects[n] for n in NAMES}


def put(r, name, loc, rz=0):
    r[name].location = loc
    r[name].rotation_euler = (0, 0, math.radians(rz))


def main(samples=64):
    sc = bpy.context.scene
    cam = preview.stage(ground_size=40)
    try:
        sc.eevee.taa_render_samples = samples
    except AttributeError:
        pass
    r = roots()
    ZP = .90
    # --- hall layout: row A faces +Y, row B faces -Y across a 1.2 m aisle
    put(r, "Saege01", (-1.4, -1.0, 0))
    put(r, "Band01_030", (-.05, -1.0, 0))
    put(r, "Montagebank01", (1.3, -1.0, 0))
    put(r, "Finishplatz01", (1.3, 1.0, 0), 180)
    put(r, "Packtisch01", (-1.4, 1.0, 0), 180)
    put(r, "Band01_1m", (4.2, -1.0, 0))
    put(r, "Holzpaket01", (-2.2, -1.0, ZP))
    put(r, "Hocker01_Kit", (-.6, -1.0, ZP))
    put(r, "Hocker01_Raw", (2.1, -1.0, ZP))
    put(r, "Hocker01_Finish", (1.3, 1.0, ZP), 20)
    put(r, "Hockerkarton01", (-2.2, 1.0, ZP))
    preview.aim(cam, (.2, 0, .55), (-.55, .62, .62), 8.4, lens=35)
    preview.render(OUT / "line-overview.png")
    preview.aim(cam, (.2, 0, .55), (.62, -.9, .55), 8.2, lens=35)
    preview.render(OUT / "line-overview-b.png")
    # --- station close-ups (front three-quarter)
    for name, (x, y, rz) in {"Saege01": (-1.4, -1.0, 0), "Montagebank01": (1.3, -1.0, 0)}.items():
        preview.aim(cam, (x, y, .8), (.45, 1, .55), 3.9, lens=40)
        preview.render(OUT / f"station-{name}.png")
    for name, (x, y) in {"Finishplatz01": (1.3, 1.0), "Packtisch01": (-1.4, 1.0)}.items():
        preview.aim(cam, (x, y, .8), (-.45, -1, .55), 3.9, lens=40)
        preview.render(OUT / f"station-{name}.png")
    # --- goods line-up on the floor
    for i, n in enumerate(("Holzpaket01", "Hocker01_Kit", "Hocker01_Raw", "Hocker01_Finish", "Hockerkarton01")):
        put(r, n, (8 + i * .75, 4, 0), 0)
    preview.aim(cam, (9.85, 4, .2), (.25, -1, .55), 4.9, lens=50)
    preview.render(OUT / "goods-lineup.png")
    preview.aim(cam, (9.5 + .75 * 2.5, 4, .25), (.5, -1, .65), 1.25, lens=50)
    preview.render(OUT / "goods-stools.png")


if __name__ == "__main__":
    main()
