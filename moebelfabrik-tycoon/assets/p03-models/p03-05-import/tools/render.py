"""One comparison image after annotation repair; camera/render settings restored."""
import bpy
from pathlib import Path
from mathutils import Vector
OUT = Path(P03_PACKAGE_DIR) if 'P03_PACKAGE_DIR' in globals() else Path(__file__).resolve().parents[1]
scene = bpy.context.scene
assert scene.get('package') == 'P03-05 import preparation v0.1'
camera = scene.camera
matrix, scale = camera.matrix_world.copy(), camera.data.ortho_scale
previous = (scene.render.resolution_x, scene.render.resolution_y, scene.render.filepath)
try:
    scene.render.resolution_x, scene.render.resolution_y = 1100, 800
    camera.location = (3.6, 4.9, 3)
    camera.rotation_euler = (Vector((0, .3, .6))-camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera.data.ortho_scale = 3.8
    scene.render.filepath = str(OUT/'renders'/'overview-import.png')
    bpy.ops.render.render(write_still=True)
finally:
    camera.matrix_world, camera.data.ortho_scale = matrix, scale
    scene.render.resolution_x, scene.render.resolution_y, scene.render.filepath = previous
print('Rendered ' + str(OUT/'renders'/'overview-import.png'))
