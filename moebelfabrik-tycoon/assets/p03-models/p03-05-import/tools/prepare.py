"""P03-05: repair only imported scene copies for volume-safe FBX; no Roblox access.

Blender metres, Z up/+Y front; Roblox mapping (X,Y,Z)->(X,Z,-Y).
Default source is the checked P03-02 package in the same project. Override
P03_SOURCE_PATH and P03_PACKAGE_DIR explicitly to run from another location.
"""
import bpy, bmesh, json, hashlib, shutil
from pathlib import Path
from mathutils import Vector

OUT = Path(P03_PACKAGE_DIR) if 'P03_PACKAGE_DIR' in globals() else Path(__file__).resolve().parents[1]
for folder in ['', 'tools', 'exports', 'textures', 'renders']:
    (OUT / folder).mkdir(parents=True, exist_ok=True)
if 'P03_SOURCE_PATH' in globals():
    SOURCE = Path(P03_SOURCE_PATH)
else:
    SOURCE = next(p / 'assets/p03-models/p03-02/p03-02-models-v01.blend'
                  for p in OUT.parents
                  if (p / 'assets/p03-models/p03-02/p03-02-models-v01.blend').exists())

original = bpy.context.scene
backup = OUT / 'before-p03-05.blend'
if not backup.exists():
    bpy.data.libraries.write(str(backup), {original}, path_remap='RELATIVE_ALL')
if globals().get('P03_REUSE_SCENE') and original.get('package') == 'P03-05 import preparation v0.1':
    scene = original
else:
    with bpy.data.libraries.load(str(SOURCE), link=False) as (src, dst):
        dst.scenes = [src.scenes[0]]
    scene = dst.scenes[0]
    assert not any(o in original.objects.values() for o in scene.objects), 'Source objects shared'
    scene.name = 'P03_05_ImportPrep_v01'
    scene['package'] = 'P03-05 import preparation v0.1'
    bpy.context.window.scene = scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
ASSETS = ['Hocker01_Raw', 'Hocker01_Finish', 'Hocker01_Kit', 'Saege01', 'ControlCube_1m']
roots = {n: next(o for o in scene.objects if o.type == 'EMPTY' and o.name.split('.')[0] == n)
         for n in ASSETS}
expected = {'Hocker01_Raw': (.4, .4, .45), 'Hocker01_Finish': (.4, .4, .45),
            'Hocker01_Kit': (.6, .5, .18), 'Saege01': (2.4, .8, 1.45),
            'ControlCube_1m': (1, 1, 1)}
checks, repairs = [], []
labels = {name: [] for name in ASSETS}

def check(name, passed, detail=None):
    checks.append({'name': name, 'passed': bool(passed), 'detail': detail})
    assert passed, f'{name}: {detail}'

def descendants(root):
    return list(root.children_recursive)

def export_meshes(root):
    return [o for o in descendants(root) if o.type == 'MESH' and not o.get('helper')]

def evaluated_mesh(obj):
    ev = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = bpy.data.meshes.new_from_object(ev, depsgraph=bpy.context.evaluated_depsgraph_get())
    return mesh

# Words become real localizable Roblox labels, never baked text geometry.
LABEL_SPECS = {
    ('Hocker01_Raw', 'Stage'): ('stool.raw', 'ROH', .020, (.13, .029)),
    ('Hocker01_Finish', 'Stage'): ('stool.finished', 'FERTIG', .020, (.13, .029)),
    ('Hocker01_Kit', 'KitStage'): ('kit.parts', '9 TEILE', .013, (.13, .021)),
    ('Saege01', 'FlowLabel_0'): ('saw.input', 'EIN', .041, (.36, .064)),
    ('Saege01', 'FlowLabel_1'): ('saw.process', 'PROZESS', .041, (.36, .064)),
    ('Saege01', 'FlowLabel_2'): ('saw.output', 'AUS', .041, (.36, .064)),
    ('Saege01', 'StatusText'): ('saw.name', 'SAEGE 01', .045, (.34, .09)),
    ('Saege01', 'StatusParked'): ('saw.status', 'FREI', .054, (.34, .10)),
}
for asset_name, root in roots.items():
    for obj in list(export_meshes(root)):
        if not obj.get('annotation') or obj.name.startswith('Arrow_'):
            continue
        spec = LABEL_SPECS[(asset_name, obj.name.split('.')[0])]
        semantic_key, source_text, font_height, area = spec
        frame = root.matrix_world.inverted() @ obj.matrix_world
        low = [min(v.co[i] for v in obj.data.vertices) for i in range(3)]
        high = [max(v.co[i] for v in obj.data.vertices) for i in range(3)]
        centre = Vector([(low[i]+high[i])/2 for i in range(3)])
        foreground = obj.data.materials[0]
        principal = next(n for n in foreground.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        labels[asset_name].append({'key': semantic_key, 'source_text_reference': source_text,
            'source_object': obj.name, 'anchor_root_blender_m': list(frame.translation),
            'glyph_centre_root_blender_m': list(frame @ centre),
            'frame_root_blender': [list(row) for row in frame],
            'right_root_blender': list(frame.col[0].to_3d().normalized()),
            'up_root_blender': list(frame.col[1].to_3d().normalized()),
            'normal_root_blender': list(frame.col[2].to_3d().normalized()),
            'source_glyph_bounds_plane_m': {'min': low[:2], 'max': high[:2]},
            'physical_font_height_m': font_height, 'surface_area_width_height_m': list(area),
            'foreground_base_color_linear': list(principal.inputs['Base Color'].default_value),
            'text_alignment': 'centre / centre', 'plane_offset_m': .00005})
        # Keep source words hidden as editable helpers in this private scene only;
        # selection/export excludes every helper, so no word mesh enters the FBX.
        obj['helper'] = True
        obj['localizable_label_key'] = semantic_key
        obj.hide_render = True
        obj.hide_set(True)
check('Eight localized text anchors recorded', sum(len(v) for v in labels.values()) == 8,
      {n: [v['key'] for v in items] for n, items in labels.items()})
check('No baked word mesh exported', all(not o.get('annotation') or o.name.startswith('Arrow_')
      for r in roots.values() for o in export_meshes(r)))

# Remaining arrow annotations receive only an inward skin; no bounds inflation.
for root in roots.values():
    for obj in export_meshes(root):
        if not obj.get('annotation') or obj.get('import_volume_repaired'):
            continue
        solidify = obj.modifiers.new('P03_ImportAnnotationThickness', 'SOLIDIFY')
        solidify.thickness = .0001
        solidify.offset = -1.0
        solidify.use_even_offset = True
        mesh = evaluated_mesh(obj)
        obj.modifiers.remove(solidify)
        obj.data = mesh
        bm = bmesh.new(); bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        if bm.calc_volume(signed=True) < 0:
            bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
        bm.to_mesh(mesh); bm.free(); mesh.update()
        obj['import_volume_repaired'] = True
        repairs.append({'object': obj.name, 'thickness_m': .0001, 'offset': 'inward'})

bpy.context.view_layer.update()

images = {node.image for root in roots.values() for obj in export_meshes(root)
          for mat in obj.data.materials if mat and mat.use_nodes
          for node in mat.node_tree.nodes if node.type == 'TEX_IMAGE' and node.image}
for image in images:
    filename = Path(image.filepath).name
    source_image = SOURCE.parent / 'textures' / filename
    check('Texture source ' + filename, source_image.exists(), str(source_image))
    shutil.copyfile(source_image, OUT / 'textures' / filename)
    image.filepath = str(OUT / 'textures' / filename)
    if not image.packed_file:
        image.pack()

def mesh_info(obj, root):
    mesh = evaluated_mesh(obj)
    mesh.calc_loop_triangles()
    mat = root.matrix_world.inverted() @ obj.matrix_world
    vertices = [mat @ v.co for v in mesh.vertices]
    low = [min(v[i] for v in vertices) for i in range(3)]
    high = [max(v[i] for v in vertices) for i in range(3)]
    bm = bmesh.new(); bm.from_mesh(mesh)
    closed = all(e.is_manifold for e in bm.edges)
    volume = bm.calc_volume(signed=True)
    check(obj.name + ' watertight positive volume including annotations', closed and volume > 0,
          {'closed': closed, 'signed_volume_m3': volume, 'annotation': bool(obj.get('annotation'))})
    bm.free()
    triangles = len(mesh.loop_triangles)
    check(obj.name + ' under per-mesh 20000 triangle limit', triangles <= 20000, triangles)
    materials = []
    for material in mesh.materials:
        if not material:
            continue
        principal = next((n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        textures = [{'file': Path(n.image.filepath).name, 'color_space': n.image.colorspace_settings.name}
                    for n in material.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image]
        materials.append({'name': material.name, 'canonical': material.name.split('.')[0],
                          'base_color_linear': list(principal.inputs['Base Color'].default_value) if principal else None,
                          'roughness': float(principal.inputs['Roughness'].default_value) if principal else None,
                          'metallic': float(principal.inputs['Metallic'].default_value) if principal else None,
                          'textures': textures})
    result = {'name': obj.name, 'canonical': obj.name.split('.')[0],
              'annotation': bool(obj.get('annotation')), 'triangles': triangles,
              'bounds_root_blender_m': {'min': low, 'max': high},
              'root_matrix': [list(row) for row in mat], 'materials': materials,
              'watertight': closed, 'signed_volume_m3': volume}
    bpy.data.meshes.remove(mesh)
    return result

assets = {}
for name, root in roots.items():
    info = [mesh_info(obj, root) for obj in export_meshes(root)]
    low = [min(m['bounds_root_blender_m']['min'][i] for m in info) for i in range(3)]
    high = [max(m['bounds_root_blender_m']['max'][i] for m in info) for i in range(3)]
    dims = [high[i] - low[i] for i in range(3)]
    check(name + ' exact overall bounds', all(abs(dims[i] - expected[name][i]) < 1e-4 for i in range(3)), dims)
    check(name + ' bottom pivot', abs(low[2]) < 1e-5, low)
    markers = {o.name.split('.')[0]: list(o.matrix_local.translation)
               for o in descendants(root) if o.type == 'EMPTY' and o.name.startswith('Att_')}
    assets[name] = {'root_name': root.name, 'pivot': 'bottom-centre', 'export_scale': 1.0,
                    'dimensions_blender_xyz_m': dims, 'dimensions_roblox_xyz_m': [dims[0], dims[2], dims[1]],
                    'bounds_root_blender_m': {'min': low, 'max': high},
                    'meshes': info, 'mesh_count': len(info), 'triangles': sum(m['triangles'] for m in info),
                    'markers_blender_m': markers,
                    'orientation': {'front': '+Y in Blender -> -Z in Roblox',
                                    'flow': '-X -> +X for saw',
                                    'features': (['Saw status sign is +X and -Y/back of root',
                                                  'Saw input -X; output +X, front control switch +Y']
                                                 if name == 'Saege01' else
                                                 ['Kit blank stage plate faces Blender +Y',
                                                  'Kit legs occupy +X side; seat offset -X']
                                                 if name == 'Hocker01_Kit' else
                                                 ['Stool blank stage plate faces Blender +Y',
                                                  'X rail screw height .315m, Y rail screw height .345m']
                                                 if name.startswith('Hocker01') else
                                                 ['Symmetric size calibration cube; orientation not observable'])}}

saw = assets['Saege01']
for x in [-.8, 0, .8]:
    low, high = [x-.35, -.30, .90], [x+.35, .30, 1.45]
    collisions = []
    for mesh in saw['meshes']:
        bounds = mesh['bounds_root_blender_m']
        overlaps = [min(high[i], bounds['max'][i])-max(low[i], bounds['min'][i]) for i in range(3)]
        if all(d > 2e-5 for d in overlaps):
            collisions.append(mesh['name'])
    check(f'Free transfer prism at {x}', not collisions, collisions)

for name, root in roots.items():
    before = root.location.copy()
    root.location = (0, 0, 0)
    bpy.ops.object.select_all(action='DESELECT')
    root.select_set(True)
    for obj in descendants(root):
        if not obj.get('helper'):
            obj.hide_set(False); obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    try:
        bpy.ops.export_scene.fbx(filepath=str(OUT/'exports'/f'{name}.fbx'), use_selection=True,
            object_types={'MESH', 'EMPTY'}, apply_unit_scale=False, apply_scale_options='FBX_SCALE_NONE',
            axis_forward='-Z', axis_up='Y', global_scale=1.0, use_mesh_modifiers=True,
            mesh_smooth_type='FACE', use_custom_props=True, add_leaf_bones=False, bake_anim=False,
            path_mode='COPY', embed_textures=True)
    finally:
        root.location = before

for image in images:
    image.filepath = '//textures/' + Path(image.filepath).name
    if not image.packed_file:
        image.pack()
bpy.data.libraries.write(str(OUT/'p03-05-import-v01.blend'), {scene}, path_remap='RELATIVE_ALL')
summary = {'task': 'P03-05', 'date': '2026-11-16', 'status': 'local-import-prepared-no-upload',
           'source': str(SOURCE), 'source_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
           'blender': bpy.app.version_string, 'scene': scene.name, 'unit': 'metres',
           'roblox_axes': 'X,Z,-Y', 'studs_per_metre_after_import': 25/7,
           'format': 'FBX with embedded textures; no baked language-specific words',
           'labels': labels, 'repairs': repairs, 'checks': checks,
           'assets': assets, 'studio_imported': False, 'art_approved': False}
(OUT/'checks.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
(OUT/'labels.json').write_text(json.dumps({'task': 'P03-05', 'unit': 'metres, Blender Z-up',
    'mapping': 'Blender (X,Y,Z) -> Roblox (X,Z,-Y)', 'studs_per_metre': 25/7,
    'word_geometry_in_fbx': False, 'labels': labels}, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({'checks': len(checks), 'repairs': len(repairs),
                  'assets': {n: {'meshes': a['mesh_count'], 'triangles': a['triangles']} for n,a in assets.items()}}))
