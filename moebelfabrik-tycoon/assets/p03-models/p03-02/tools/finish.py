"""Verify local P03-02 sample and export its isolated roots, never user assets."""
import bpy, bmesh, math, os, json
from pathlib import Path
from mathutils import Vector
import numpy as np
OUT=Path(P03_PACKAGE_DIR) if 'P03_PACKAGE_DIR' in globals() else Path(__file__).resolve().parents[1]
scene=bpy.context.scene
assert scene.get('package')=='P03-02 v0.1 technical prototype'
for o in scene.objects:
    if o.name.startswith('ScrewSlot_'): o.location.z=.44990

# Correct linear image storage before PNG's display transform, including existing build.
res=512
xx=np.arange(res)[None,:]/res; yy=np.arange(res)[:,None]/res
grain=(.48*np.sin(yy*136+.9*np.sin(xx*8)+.24*np.sin(xx*21))
       +.22*np.sin(yy*378+.5*np.sin(xx*17))+.13*np.random.default_rng(4102).standard_normal((res,res)))
for slot,color in [('WoodRaw','C59664'),('WoodFinish','B8824E')]:
    base=np.array([int(color[i:i+2],16)/255 for i in (0,2,4)])
    base=np.where(base<=.04045,base/12.92,((base+.055)/1.055)**2.4)
    image=next(n.image for m in bpy.data.materials if m.name.startswith('P03_'+slot)
               for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image.name.startswith('P03_'+slot)
               and any(o for o in scene.objects if o.type=='MESH' and m in list(o.data.materials)))
    pixels=np.ones((res,res,4),dtype=np.float32)
    pixels[:,:,:3]=np.clip(base[None,None,:]*(1+grain[:,:,None]*.095),0,1)
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw=str(OUT/'textures'/f'{slot}.png');image.save()

roots={n:next(o for o in scene.objects if o.type=='EMPTY' and o.name.split('.')[0]==n)
       for n in ['Hocker01_Raw','Hocker01_Finish','Hocker01_Kit','Saege01','ControlCube_1m']}

def descendants(root):
    result=[]
    for o in root.children:
        result.append(o);result.extend(descendants(o))
    return result

# Convert only this scene's own text labels for reliable FBX geometry.
for o in list(scene.objects):
    if o.type=='FONT':
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True);bpy.context.view_layer.objects.active=o
        bpy.ops.object.convert(target='MESH')
bpy.context.view_layer.update()
dg=bpy.context.evaluated_depsgraph_get()

def bbox(obj,root):
    ev=obj.evaluated_get(dg)
    mesh=ev.to_mesh()
    mat=root.matrix_world.inverted()@obj.matrix_world
    coords=[mat@v.co for v in mesh.vertices]
    ev.to_mesh_clear()
    return ([min(v[i] for v in coords) for i in range(3)],
            [max(v[i] for v in coords) for i in range(3)])

checks=[]
def check(name,ok,detail):
    checks.append({'name':name,'passed':bool(ok),'detail':detail})
    assert ok, name+': '+str(detail)

expected={'Hocker01_Raw':(.4,.4,.45),'Hocker01_Finish':(.4,.4,.45),
          'Hocker01_Kit':(.6,.5,.18),'Saege01':(2.4,.8,1.45),'ControlCube_1m':(1,1,1)}
report={}
for name,root in roots.items():
    meshes=[o for o in descendants(root) if o.type=='MESH' and not o.get('helper')]
    boxes=[bbox(o,root) for o in meshes]
    low=[min(b[0][i] for b in boxes) for i in range(3)]
    high=[max(b[1][i] for b in boxes) for i in range(3)]
    dim=[high[i]-low[i] for i in range(3)]
    check(name+' dimensions',all(abs(dim[i]-expected[name][i])<2e-5 for i in range(3)),dim)
    check(name+' bottom pivot',abs(low[2])<2e-5,low)
    tris=0
    for o in meshes:
        ev=o.evaluated_get(dg);m=ev.to_mesh();m.calc_loop_triangles();tris+=len(m.loop_triangles)
        if not o.get('annotation'):
            bm=bmesh.new();bm.from_mesh(m)
            closed=all(e.is_manifold for e in bm.edges)
            volume=bm.calc_volume(signed=True)
            check(o.name+' closed outward normals',closed and volume>0,{'closed':closed,'signedVolume':volume})
            bm.free()
        elif o.name.startswith('Arrow_'):
            check(o.name+' upward face',all(p.normal.z>.99 for p in m.polygons),[list(p.normal) for p in m.polygons])
        ev.to_mesh_clear()
    report[name]={'bounds_blender_m':{'min':low,'max':high},'dimensions_blender_xyz_m':dim,
                  'dimensions_roblox_xyz_m':[dim[0],dim[2],dim[1]],'triangles':tris,'meshes':len(meshes),
                  'pivot':'bottom centre','front_blender':'+Y'}
    if name.startswith('Hocker01'):
        wood=[o for o in meshes if o.get('wood_part')]
        check(name+' nine wood parts',len(wood)==9,[o.get('wood_part') for o in wood])
    if name in ['Hocker01_Raw','Hocker01_Finish']:
        wood={o.get('wood_part'):bbox(o,root) for o in meshes if o.get('wood_part')}
        # Nominal join planes still meet after small subtractive edge chamfers.
        check(name+' seat contact',all(abs(wood[f'Leg_{i}'][1][2]-wood['Seat'][0][2])<2e-5 for i in range(1,5)),.425)
        check(name+' rail length',all(abs(wood[f'RailX_{i}'][1][0]-wood[f'RailX_{i}'][0][0]-.29)<2e-5 for i in [1,2]),.29)
        for o in meshes:
            if o.name.startswith('RailXScrew') or o.name.startswith('RailYScrew'):
                axis=0 if o.name.startswith('RailXScrew') else 1
                lo,hi=bbox(o,root)
                check(o.name+' cap flush with leg',abs(max(abs(lo[axis]),abs(hi[axis]))-.18)<2e-5,[lo[axis],hi[axis]])

saw=roots['Saege01']
meshes=[o for o in descendants(saw) if o.type=='MESH' and not o.get('helper')]
collisions=[]
for x in [-.8,0,.8]:
    plow=[x-.35,-.30,.90]; phigh=[x+.35,.30,1.45]
    for o in meshes:
        lo,hi=bbox(o,saw)
        overlap=[min(hi[i],phigh[i])-max(lo[i],plow[i]) for i in range(3)]
        if all(v>2e-5 for v in overlap): collisions.append(o.name)
check('Three transfer prisms empty',len(collisions)==0,collisions)
for name,x in [('Att_Input',-.8),('Att_Process',0),('Att_Output',.8)]:
    marker=next(o for o in saw.children if o.name.split('.')[0]==name)
    check(name+' position',all(abs(marker.location[i]-[x,0,.90][i])<1e-6 for i in range(3)),list(marker.location))
blade=next(o for o in saw.children if o.name.startswith('Moving_Blade'))
check('Parked blade below tabletop',bbox(blade,saw)[1][2]<.80,bbox(blade,saw)[1])
guard=next(o for o in saw.children if o.name.startswith('Moving_ParkedGuard'))
guardbox=bbox(guard,saw)
check('Guard behind all cargo volumes',guardbox[1][1]<=-.31+2e-5,guardbox)

# FBX meter values remain unscaled. Per-root export is translated to root origin.
for name,root in roots.items():
    old=root.location.copy();root.location=(0,0,0)
    bpy.ops.object.select_all(action='DESELECT')
    root.select_set(True)
    for o in descendants(root):
        if not o.get('helper'):
            o.hide_set(False);o.select_set(True)
    bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.fbx(filepath=str(OUT/'exports'/f'{name}.fbx'),use_selection=True,
        object_types={'MESH','EMPTY'},apply_unit_scale=False,apply_scale_options='FBX_SCALE_NONE',
        axis_forward='-Z',axis_up='Y',global_scale=1.0,use_mesh_modifiers=True,
        mesh_smooth_type='FACE',use_custom_props=True,add_leaf_bones=False,bake_anim=False,
        path_mode='COPY',embed_textures=True)
    root.location=old

summary={'task':'P03-02','date':'2026-11-16','status':'local-technical-model-prototype',
    'artApproved':False,'studioImported':False,'scene':scene.name,'blender':bpy.app.version_string,
    'unit':'metres','robloxAxes':'X,Z,-Y','scaleOnImport':25/7,
    'checks':checks,'assets':report,'activeCutMode':'not designed; parked handover only',
    'originalScenePreserved':'Scene','backup':'before-p03-02.blend'}
(OUT/'checks.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
images={n.image for o in scene.objects if o.type=='MESH' for m in o.data.materials if m and m.use_nodes
        for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image}
for image in images:
    image.filepath='//textures/'+Path(bpy.path.abspath(image.filepath)).name
    if not image.packed_file: image.pack()
# Deliver only the current model scene and its dependencies. Preserve every live user scene.
bpy.data.libraries.write(str(OUT/'p03-02-models-v01.blend'),{scene},path_remap='RELATIVE_ALL')
print(json.dumps({'checksPassed':len(checks),'assets':report,'exports':list(roots)},ensure_ascii=False))
