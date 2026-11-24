"""Preview stage for HQ renders: ground, 3-point light, camera helpers.
Lives in its own collection 'HQ_Preview' and is never exported."""
import math
from pathlib import Path
import bpy
from mathutils import Vector

COL = "HQ_Preview"


def stage(ground_size=30, ground_hex="8E9296"):
    import hqlib
    col = hqlib.clear_collection(COL)
    me = bpy.data.meshes.new("HQ_Ground")
    s = ground_size / 2
    me.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    gm = bpy.data.materials.get("HQ_PreviewGround") or bpy.data.materials.new("HQ_PreviewGround")
    gm.use_nodes = True
    b = next(n for n in gm.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = hqlib.lin(ground_hex)
    b.inputs["Roughness"].default_value = .9
    me.materials.append(gm)
    g = bpy.data.objects.new("HQ_Ground", me)
    g.location.z = -.0005
    col.objects.link(g)

    def light(name, kind, energy, loc, rot, size=None, color=(1, 1, 1)):
        ld = bpy.data.lights.new(name, kind)
        ld.energy = energy
        ld.color = color
        if size and kind == "AREA":
            ld.size = size
        if kind == "SUN":
            ld.angle = math.radians(3)
        ob = bpy.data.objects.new(name, ld)
        ob.location = loc
        ob.rotation_euler = [math.radians(a) for a in rot]
        col.objects.link(ob)
        return ob
    light("HQ_Key", "SUN", 3.2, (4, -4, 6), (48, 0, 38), color=(1, .97, .92))
    light("HQ_Fill", "AREA", 260, (-4, -3, 3), (65, 0, -55), size=4, color=(.88, .93, 1))
    light("HQ_Rim", "AREA", 220, (0, 5, 3.5), (-60, 0, 180), size=3)
    cam = bpy.data.cameras.new("HQ_Cam")
    cam.lens = 50
    cob = bpy.data.objects.new("HQ_Cam", cam)
    col.objects.link(cob)
    bpy.context.scene.camera = cob
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y = 1600, 1000
    try:
        sc.eevee.use_shadows = True
    except AttributeError:
        pass
    return cob


def aim(cam, target, direction, distance, lens=50):
    target = Vector(target)
    d = Vector(direction).normalized()
    cam.location = target + d * distance
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens


def render(path):
    sc = bpy.context.scene
    sc.render.image_settings.file_format = "PNG"
    sc.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
