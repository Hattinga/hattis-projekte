"""Neutral views of the current P03-02 scene. Own asset visibility/camera restored."""
import bpy, json
from pathlib import Path
from mathutils import Vector
OUT=Path(P03_PACKAGE_DIR) if 'P03_PACKAGE_DIR' in globals() else Path(__file__).resolve().parents[1]
scene=bpy.context.scene
assert scene.get('package')=='P03-02 v0.1 technical prototype'
camera=scene.camera
roots={n:next(o for o in scene.objects if o.type=='EMPTY' and o.name.split('.')[0]==n)
       for n in ['Hocker01_Raw','Hocker01_Finish','Hocker01_Kit','Saege01','ControlCube_1m']}
previous={o:o.hide_render for o in scene.objects}
cam_matrix=camera.matrix_world.copy();ortho=camera.data.ortho_scale
resolution=(scene.render.resolution_x,scene.render.resolution_y)
rendered=[]
scene.render.resolution_x=1100;scene.render.resolution_y=800
if hasattr(scene,'eevee') and hasattr(scene.eevee,'taa_render_samples'):scene.eevee.taa_render_samples=32

def render(name, position, target, scale, show=None, cutaway=False):
    if 'P03_RENDER_ONLY' in globals() and name!=P03_RENDER_ONLY:return
    for o,state in previous.items():o.hide_render=state
    if show:
        for rootname,r in roots.items():
            if rootname not in show:
                for o in r.children_recursive:o.hide_render=True
    if cutaway:
        for o in roots['Saege01'].children:
            if o.name.startswith(('MotorHousing','Vent','SwitchBox','StopButton','StartButton','MotorMount')):
                o.hide_render=True
    camera.location=position
    camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale=scale
    scene.render.filepath=str(OUT/'renders'/f'{name}.png')
    bpy.ops.render.render(write_still=True)
    rendered.append(name)
    print('Rendered '+name,flush=True)

try:
    render('overview-final',(3.6,4.9,3),(0,.3,.6),3.8)
    render('stool-joint',(-1.22,1.66,.76),(-.8,1.05,.34),.57,['Hocker01_Raw'])
    render('kit-three-quarter',(1.15,1.85,.90),(.55,1.05,.05),.83,['Hocker01_Kit'])
    render('saw-front',(0,4,1.1),(0,-.18,.72),2.8,['Saege01'])
    render('saw-side',(3.7,-.18,.74),(0,-.18,.74),2.8,['Saege01'])
    render('saw-top',(0,-.18,4),(0,-.18,.74),2.85,['Saege01'])
    render('saw-blade-cutaway',(1.1,1.8,.95),(0,-.18,.66),1.16,['Saege01'],True)
finally:
    for o,state in previous.items():o.hide_render=state
    camera.matrix_world=cam_matrix;camera.data.ortho_scale=ortho
    scene.render.resolution_x,scene.render.resolution_y=resolution
print(json.dumps({'renders':len(rendered),'files':rendered,'directory':str(OUT/'renders')}))
