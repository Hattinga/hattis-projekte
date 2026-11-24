"""One-shot rebuild of the HQ batch inside Blender 5.1:
build goods + stations -> export FBX/GLB + manifests -> roundtrip check ->
documentation renders -> save hq-assets-v1.blend.

Textures are generated beforehand with a normal Python:
    python assets/hq/tools/textures.py
Then in Blender (Scripting tab or MCP):
    exec(open(r"<repo>/assets/hq/tools/run_all.py").read(), {"__file__": r"<repo>/assets/hq/tools/run_all.py"})
Only the collections HQ_Goods / HQ_Stations / HQ_Preview are (re)created;
other scenes and objects in the open file stay untouched.
"""
import sys, importlib
from pathlib import Path
import bpy

TOOLS = Path(globals().get("__file__", r"C:/Claudeprojecte/repo/hattis-projekte/moebelfabrik-tycoon/assets/hq/tools/run_all.py")).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))


def _run(file, **extra):
    p = str(TOOLS / file)
    g = {"__file__": p, "__name__": "__main__", **extra}
    exec(compile(open(p, encoding="utf-8").read(), p, "exec"), g)
    return g


for im in bpy.data.images:                     # pick up regenerated maps
    if im.filepath and "assets" in im.filepath.replace("\\", "/") and "hq" in im.filepath.lower():
        im.reload()
assets = _run("build_goods.py", HQ_EXPORT=True)["ASSETS"] + _run("build_stations.py", HQ_EXPORT=True)["ASSETS"]
import roundtrip
importlib.reload(roundtrip)
res = roundtrip.run(assets)
failed = [k for k, v in res.items() if not v["ok"]]
print(f"roundtrip: {len(res)} imports, {len(failed)} failed {failed}")
if not globals().get("HQ_SKIP_RENDER"):
    _run("render.py")
bpy.ops.wm.save_as_mainfile(filepath=str(TOOLS.parent / "hq-assets-v1.blend"), relative_remap=True, copy=True)
print("saved", TOOLS.parent / "hq-assets-v1.blend")
