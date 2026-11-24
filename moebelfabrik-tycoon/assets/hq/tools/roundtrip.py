"""Re-import every GLB/FBX export in a throw-away scene and compare against the
build stats: size (<1 mm), floor at Z=0, MeshPart count and triangle count.
Writes assets/hq/roundtrip.json. Run inside Blender after the builds.

Note (Blender 5.1): the glTF importer adds empty scenes on every import, so
each import is followed by removing every scene it created. Without this,
repeated checks pile up thousands of scenes and every export slows down."""
import json
from pathlib import Path
import bpy
from mathutils import Vector

HQ = Path(globals().get("__file__", r"C:/Claudeprojecte/repo/hattis-projekte/moebelfabrik-tycoon/assets/hq/tools/roundtrip.py")).resolve().parents[1]


def run(assets):
    src = {a.name: a.stats() for a in assets}
    home = bpy.context.window.scene
    rt = bpy.data.scenes.new("HQ_Roundtrip")
    bpy.context.window.scene = rt
    before_imgs, before_mats = set(bpy.data.images), set(bpy.data.materials)
    keep_scenes = set(bpy.data.scenes)
    results = {}
    try:
        for fmt in ("glb", "fbx"):
            for name, st in src.items():
                before = set(bpy.data.objects)
                f = str(HQ / "exports" / f"{name}.{fmt}")
                if fmt == "glb":
                    bpy.ops.import_scene.gltf(filepath=f)
                else:
                    bpy.ops.import_scene.fbx(filepath=f, axis_forward="-Z", axis_up="Y", global_scale=1.0)
                new = [o for o in bpy.data.objects if o not in before]
                bpy.context.view_layer.update()
                mn, mx, tris, meshes = Vector((1e9,) * 3), Vector((-1e9,) * 3), 0, 0
                for o in new:
                    if o.type != "MESH":
                        continue
                    meshes += 1
                    tris += sum(len(p.vertices) - 2 for p in o.data.polygons)
                    for v in o.data.vertices:
                        w = o.matrix_world @ v.co
                        mn, mx = Vector(map(min, mn, w)), Vector(map(max, mx, w))
                size = [round(mx[i] - mn[i], 4) for i in range(3)]
                dev = max(abs(size[i] - st["bounds_m"]["size"][i]) for i in range(3))
                ok = dev < 1e-3 and abs(mn.z) < 1e-3 and meshes == st["mesh_parts"] and tris == st["tris"]
                results[f"{name}.{fmt}"] = {"ok": ok, "size_m": size, "dev_m": round(dev, 6),
                                            "floor_z": round(mn.z, 4), "mesh_parts": meshes, "tris": tris}
                for o in new:
                    bpy.data.objects.remove(o, do_unlink=True)
                extra = [sc for sc in bpy.data.scenes if sc not in keep_scenes and sc != rt]
                if extra:
                    bpy.data.batch_remove(extra)
    finally:
        bpy.context.window.scene = home
        bpy.data.scenes.remove(rt)
        # drop everything the importers created: meshes first (they hold the
        # materials), then materials and images that did not exist before
        bpy.data.batch_remove([me for me in bpy.data.meshes if me.users == 0])
        bpy.data.batch_remove([m for m in bpy.data.materials if m not in before_mats and m.users == 0])
        bpy.data.batch_remove([im for im in bpy.data.images if im not in before_imgs])
    (HQ / "roundtrip.json").write_text(json.dumps(results, indent=1), encoding="utf-8")
    return results
