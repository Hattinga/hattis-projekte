"""FBX reimport check in fresh isolated Blender scenes, with no user object edits."""
import bpy, json
from pathlib import Path
from mathutils import Vector
OUT=Path(P03_PACKAGE_DIR) if 'P03_PACKAGE_DIR' in globals() else Path(__file__).resolve().parents[1]
original=bpy.context.scene
expected={'Hocker01_Raw':(.4,.4,.45),'Hocker01_Finish':(.4,.4,.45),
          'Hocker01_Kit':(.6,.5,.18),'Saege01':(2.4,.8,1.45),'ControlCube_1m':(1,1,1)}
results={}
try:
    for name,dims in expected.items():
        test=bpy.data.scenes.new('P03_FbxCheck_'+name)
        bpy.context.window.scene=test
        bpy.ops.import_scene.fbx(filepath=str(OUT/'exports'/f'{name}.fbx'))
        meshes=[o for o in test.objects if o.type=='MESH']
        points=[o.matrix_world@Vector(c) for o in meshes for c in o.bound_box]
        low=[min(v[i] for v in points) for i in range(3)]
        high=[max(v[i] for v in points) for i in range(3)]
        actual=[high[i]-low[i] for i in range(3)]
        assert all(abs(actual[i]-dims[i])<2e-5 for i in range(3)),(name,actual)
        assert abs(low[2])<2e-5,(name,'floor pivot',low)
        assetroot=next(o for o in test.objects if o.type=='EMPTY' and o.parent is None)
        assert assetroot.location.length<2e-5,(name,'root moved',list(assetroot.location))
        images={node.image for o in meshes for m in o.data.materials if m and m.use_nodes
                for node in m.node_tree.nodes if node.type=='TEX_IMAGE' and node.image}
        missing=[im.filepath for im in images if not im.packed_file and not Path(bpy.path.abspath(im.filepath)).exists()]
        assert not missing,(name,'missing textures',missing)
        results[name]={'dimensions_blender_xyz_m':actual,'rootAtOrigin':True,'bottomAtZero':True,
                       'meshCount':len(meshes),'missingTextures':missing,'status':'passed'}
finally:
    bpy.context.window.scene=original
(OUT/'fbx-roundtrip.json').write_text(json.dumps({'task':'P03-02','date':'2026-11-16',
    'method':'Blender FBX export -> fresh isolated scene import; no Roblox import',
    'status':'passed','assets':results},indent=2),encoding='utf-8')
print(json.dumps(results))
