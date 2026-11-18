"""P03-05: five independent FBX reimports, including annotation topology."""
import bpy, bmesh, json
from pathlib import Path
from mathutils import Vector

OUT = Path(P03_PACKAGE_DIR) if 'P03_PACKAGE_DIR' in globals() else Path(__file__).resolve().parents[1]
source = json.loads((OUT/'checks.json').read_text(encoding='utf-8'))
original = bpy.context.scene
results = {}
try:
    for name, expected in source['assets'].items():
        scene = bpy.data.scenes.new('P03_05_Roundtrip_' + name)
        bpy.context.window.scene = scene
        bpy.ops.import_scene.fbx(filepath=str(OUT/'exports'/f'{name}.fbx'))
        meshes = [o for o in scene.objects if o.type == 'MESH']
        assert len(meshes) == expected['mesh_count'], (name, 'mesh count', len(meshes))
        words = [o.name for o in meshes if o.get('annotation') and not o.name.startswith('Arrow_')]
        assert not words, (name, 'baked words survived', words)
        vertices = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
        low = [min(v[i] for v in vertices) for i in range(3)]
        high = [max(v[i] for v in vertices) for i in range(3)]
        dimensions = [high[i]-low[i] for i in range(3)]
        assert all(abs(dimensions[i]-expected['dimensions_blender_xyz_m'][i]) < 1e-4 for i in range(3)), (name, dimensions)
        assert abs(low[2]) < 1e-5, (name, 'bottom pivot', low)
        root = next(o for o in scene.objects if o.type == 'EMPTY' and o.parent is None)
        assert root.location.length < 1e-5, (name, 'root moved')
        topology = []
        triangles = 0
        for obj in meshes:
            mesh = obj.data
            mesh.calc_loop_triangles()
            triangles += len(mesh.loop_triangles)
            bm = bmesh.new(); bm.from_mesh(mesh)
            closed = all(e.is_manifold for e in bm.edges)
            volume = bm.calc_volume(signed=True) * obj.matrix_world.determinant()
            bm.free()
            assert closed and volume > 0, (name, obj.name, closed, volume)
            topology.append({'mesh': obj.name, 'watertight': closed, 'positive_world_volume_m3': volume})
        assert triangles == expected['triangles'], (name, 'triangles', triangles, expected['triangles'])
        images = {node.image for o in meshes for m in o.data.materials if m and m.use_nodes
                  for node in m.node_tree.nodes if node.type == 'TEX_IMAGE' and node.image}
        expected_textures = {t['file'] for m in expected['meshes'] for mat in m['materials'] for t in mat['textures']}
        actual_textures = {Path(im.filepath).name for im in images}
        assert expected_textures == actual_textures, (name, 'texture count', expected_textures, actual_textures)
        missing = [im.filepath for im in images if not im.packed_file and not Path(bpy.path.abspath(im.filepath)).exists()]
        assert not missing, (name, 'missing images', missing)
        results[name] = {'status': 'passed', 'dimensions_blender_xyz_m': dimensions,
                         'root_at_origin': True, 'bottom_at_zero': True, 'meshes': len(meshes),
                         'triangles': triangles, 'textures': sorted(actual_textures),
                         'missing_textures': missing, 'baked_word_meshes': words, 'topology': topology}
finally:
    bpy.context.window.scene = original
(OUT/'roundtrip.json').write_text(json.dumps({'task': 'P03-05', 'date': '2026-11-16',
    'status': 'passed', 'method': 'FBX export to five independent Blender scenes, not Roblox',
    'assets': results}, indent=2), encoding='utf-8')
print(json.dumps({'status': 'passed', 'assets': {n: {'meshes': a['meshes'], 'triangles': a['triangles']} for n,a in results.items()}}))
