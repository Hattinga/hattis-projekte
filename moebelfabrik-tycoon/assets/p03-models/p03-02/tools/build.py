"""P03-02 technical art sample, metres/Z-up. Run inside Blender 5.1.

Project-specific convention overrides generic stud/centre conventions:
Blender (X,Y,Z) -> Roblox (X,Z,-Y), front +Y; root at bottom centre.
No user objects are removed. A fresh isolated scene is created on every run.
"""
import bpy, bmesh, math, json, os
from mathutils import Vector
from pathlib import Path
import numpy as np

OUT = Path(P03_PACKAGE_DIR) if 'P03_PACKAGE_DIR' in globals() else Path(__file__).resolve().parents[1]
OUT.mkdir(parents=True, exist_ok=True)
(OUT/'exports').mkdir(exist_ok=True)
(OUT/'textures').mkdir(exist_ok=True)
(OUT/'renders').mkdir(exist_ok=True)
scene = bpy.data.scenes.new('P03_02_Models_v01')
bpy.context.window.scene = scene
scene.unit_settings.system='METRIC'
scene.unit_settings.scale_length=1.0
try: scene.render.engine='BLENDER_EEVEE'
except TypeError: scene.render.engine='CYCLES'
scene.render.resolution_x=1440
scene.render.resolution_y=1000
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.world=bpy.data.worlds.new('P03_NeutralWorld')
scene.world.use_nodes=True
worldbg=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND')
worldbg.inputs['Color'].default_value=(.35,.39,.42,1)
worldbg.inputs['Strength'].default_value=.5
scene.view_settings.view_transform='AgX'
assets={}
materials={}

def linear(hexcode):
    vals=[int(hexcode[i:i+2],16)/255 for i in (0,2,4)]
    return tuple(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in vals)+(1,)

def material(name, color, rough=.5, metal=0):
    m=bpy.data.materials.new('P03_'+name)
    m.use_nodes=True
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value=linear(color)
    p.inputs['Roughness'].default_value=rough
    p.inputs['Metallic'].default_value=metal
    m.diffuse_color=linear(color)
    materials[name]=m
    return m

for args in [('WoodRaw','C59664',.68,0),('WoodFinish','B8824E',.3,0),
             ('MachineSteel','34383C',.34,.7),('BrushedSteel','9BA5A6',.32,.75),
             ('MutedGreen','788678',.42,.18),('SafetyOrange','D88B3D',.46,.12),
             ('Black','1C2528',.48,.2),('Label','EEE7D5',.72,0),
             ('Red','A94437',.38,.15),('Ground','DDDFD9',.85,0),
             ('Carrier','536361',.52,.22)]: material(*args)

# A real image texture, shared at a fixed physical grain scale; FBX exports PNGs.
res=512
xx=np.arange(res)[None,:]/res
yy=np.arange(res)[:,None]/res
rng=np.random.default_rng(4102)
grain=(.48*np.sin(yy*136 + .9*np.sin(xx*8)+.24*np.sin(xx*21))
       +.22*np.sin(yy*378+.5*np.sin(xx*17)) + .13*rng.standard_normal((res,res)))
for slot, color in [('WoodRaw','C59664'),('WoodFinish','B8824E')]:
    image=bpy.data.images.new('P03_'+slot+'_grain',width=res,height=res)
    base=np.array(linear(color)[:3])
    pixels=np.ones((res,res,4),dtype=np.float32)
    pixels[:,:,:3]=np.clip(base[None,None,:]*(1+grain[:,:,None]*.095),0,1)
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw=str(OUT/'textures'/f'{slot}.png')
    image.file_format='PNG'
    image.save()
    m=materials[slot]
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    texture=m.node_tree.nodes.new('ShaderNodeTexImage')
    texture.image=image
    texture.extension='REPEAT'
    m.node_tree.links.new(texture.outputs['Color'],p.inputs['Base Color'])

def root(name, location):
    o=bpy.data.objects.new(name,None)
    scene.collection.objects.link(o)
    o.location=location
    o['units']='metres'; o['front']='+Y'; o['roblox_map']='X,Z,-Y'
    o['pivot']='bottom centre'; o['art_status']='Codex technical prototype; pending Fable/art review'
    assets[name]=o
    return o

def add_obj(name, mesh, parent, mat):
    o=bpy.data.objects.new(name,mesh)
    scene.collection.objects.link(o)
    if parent: o.parent=parent
    if mat: o.data.materials.append(materials[mat])
    return o

def box(name, size, pos, parent=None, mat='MachineSteel', bevel=0, grain_axis=None):
    sx,sy,sz=[s/2 for s in size]
    verts=[(-sx,-sy,-sz),(-sx,-sy,sz),(-sx,sy,-sz),(-sx,sy,sz),
           (sx,-sy,-sz),(sx,-sy,sz),(sx,sy,-sz),(sx,sy,sz)]
    faces=[(0,4,6,2),(1,3,7,5),(0,1,5,4),(2,6,7,3),(0,2,3,1),(4,5,7,6)]
    mesh=bpy.data.meshes.new(name+'_Mesh')
    mesh.from_pydata(verts,[],[tuple(reversed(f)) for f in faces]); mesh.update()
    o=add_obj(name+'__'+(mat or 'Helper'),mesh,parent,mat); o.location=pos
    uv=mesh.uv_layers.new(name='UVMap')
    for poly in mesh.polygons:
        normalaxis=max(range(3),key=lambda a:abs(poly.normal[a]))
        axes=[a for a in range(3) if a!=normalaxis]
        along=grain_axis if grain_axis in axes else axes[0]
        across=next(a for a in axes if a!=along)
        for li in poly.loop_indices:
            co=mesh.vertices[mesh.loops[li].vertex_index].co
            uv.data[li].uv=(co[along]/.4,co[across]/.14)
    if bevel:
        mod=o.modifiers.new('Small machined edge','BEVEL'); mod.width=bevel; mod.segments=2
    return o

def cylinder(name, radius, depth, pos, parent, mat='BrushedSteel', axis='Z', vertices=20):
    mesh=bpy.data.meshes.new(name+'_Mesh')
    bm=bmesh.new()
    bmesh.ops.create_cone(bm,cap_ends=True,cap_tris=False,segments=vertices,
                          radius1=radius,radius2=radius,depth=depth)
    bm.to_mesh(mesh); bm.free()
    o=add_obj(name+'__'+(mat or 'Helper'),mesh,parent,mat); o.location=pos
    if axis=='Y': o.rotation_euler[0]=math.pi/2
    if axis=='X': o.rotation_euler[1]=math.pi/2
    return o

def text(name, body, pos, size, parent, mat='Black', front=False):
    curve=bpy.data.curves.new(name+'_Font','FONT')
    curve.body=body;curve.size=size;curve.align_x='CENTER';curve.align_y='CENTER'
    curve.extrude=0
    o=add_obj(name,curve,parent,mat);o.location=pos;o['annotation']=True
    if front: o.rotation_euler=(math.pi/2,0,math.pi)
    else: o.rotation_euler[2]=math.pi
    return o

def marker(name,pos,parent):
    o=bpy.data.objects.new(name,None);scene.collection.objects.link(o)
    o.parent=parent;o.location=pos;o.empty_display_type='ARROWS';o.empty_display_size=.04
    return o

def stool(name, location, wood):
    r=root(name,location)
    legs={}
    seat=box('Seat',( .4,.4,.025),(0,0,.4375),r,wood,.001,0)
    seat['wood_part']='Seat';seat['grain_axis']='X'
    for i,(x,y) in enumerate([(-.1625,-.1625),(-.1625,.1625),(.1625,-.1625),(.1625,.1625)],1):
        leg=box(f'Leg_{i}',(.035,.035,.425),(x,y,.2125),r,wood,.001,2)
        leg['wood_part']=f'Leg_{i}';leg['grain_axis']='Z'
        legs[(x,y)]=leg
        # Visible flush screw heads replace a small drilled recess at the seat top.
        cutter=cylinder('SeatRecess',.005,.008,(x,y,.45),r,None)
        mod=seat.modifiers.new('Counterbore','BOOLEAN');mod.operation='DIFFERENCE';mod.object=cutter
        bpy.context.view_layer.objects.active=seat
        bpy.ops.object.modifier_apply(modifier=mod.name)
        cutter.hide_render=True;cutter.hide_set(True);cutter['helper']=True
        cylinder(f'SeatScrew_{i}',.0048,.0018,(x,y,.449),r,'MachineSteel')
        box(f'ScrewSlot_{i}',(.006,.0012,.00015),(x,y,.44990),r,'Black')
    for i,y in enumerate([-.1625,.1625],1):
        part=box(f'RailX_{i}',(.29,.02,.06),(0,y,.33),r,wood,.0008,0)
        part['wood_part']=f'RailX_{i}';part['grain_axis']='X'
    for i,x in enumerate([-.1625,.1625],1):
        part=box(f'RailY_{i}',(.02,.29,.06),(x,0,.33),r,wood,.0008,1)
        part['wood_part']=f'RailY_{i}';part['grain_axis']='Y'
    # Counterbored side heads are flush with each leg, not merely inside the seat hull.
    for sign in [-1,1]:
        for axis,others,height in [('X',[-.1625,.1625],.315),('Y',[-.1625,.1625],.345)]:
            for other in others:
                pos=(sign*.18,other,height) if axis=='X' else (other,sign*.18,height)
                leg=legs[(sign*.1625,other)] if axis=='X' else legs[(other,sign*.1625)]
                cutter=cylinder('RailRecess',.0052,.008,pos,r,None,axis,16)
                mod=leg.modifiers.new('Counterbore','BOOLEAN');mod.operation='DIFFERENCE';mod.object=cutter
                bpy.context.view_layer.objects.active=leg;bpy.ops.object.modifier_apply(modifier=mod.name)
                cutter.hide_render=True;cutter.hide_set(True);cutter['helper']=True
                cap=(sign*.1795,other,height) if axis=='X' else (other,sign*.1795,height)
                cylinder('Rail'+axis+'Screw',.005,.001,cap,r,'MachineSteel',axis,16)
    box('StagePlaque',(.13,.001,.029),(0,.1732,.331),r,'Label',.001)
    text('Stage','ROH' if wood=='WoodRaw' else 'FERTIG',(0,.1738,.331),.020,r,front=True)
    marker('Att_Carry',(0,0,.33),r)
    return r

raw=stool('Hocker01_Raw',(-.8,1.05,0),'WoodRaw')
finished=stool('Hocker01_Finish',(-.21,1.05,0),'WoodFinish')
kit=root('Hocker01_Kit',(.55,1.05,0))
box('CarrierFloor',(.60,.50,.01),(0,0,.005),kit,'Carrier',.002)
for y in [-.245,.245]: box('CarrierRimX',(.58,.01,.02),(0,y,.02),kit,'Carrier',.001)
for x in [-.295,.295]:
    box('CarrierRimY',(.01,.50,.02),(x,0,.02),kit,'Carrier',.001)
    # Open U handles: preserve the full 0.58 x 0.48 usable floor.
    for y in [-.17,.17]: box('HandleUpright',(.01,.018,.15),(x,y,.105),kit,'Carrier',.002)
    box('HandleTop',(.01,.35,.018),(x,0,.171),kit,'Carrier',.002)
parts=[('Seat',(.4,.4,.025),(-.085,0,.0225),0)]
for i,x in enumerate([.1475,.1875,.2275,.2675],1):
    parts.append((f'Leg_{i}',(.035,.425,.035),(x,0,.0275),1))
for i,y in enumerate([.105,.035,-.035,-.105],1):
    parts.append((f'Rail_{i}',(.29,.06,.02),(-.08,y,.045),0))
for name,sz,pos,axis in parts:
    o=box(name,sz,pos,kit,'WoodRaw',.0008,axis)
    o['wood_part']=name;o['grain_axis']='XYZ'[axis]
box('KitBadge',(.13,.001,.021),(0,.2495,.018),kit,'Label')
text('KitStage','9 TEILE',(0,.25,.018),.013,kit,front=True)

saw=root('Saege01',(0,-.18,0))
box('MainTable',(2.4,.8,.08),(0,0,.84),saw,'MachineSteel',.006)
for i,x in enumerate([-.8,0,.8]):
    box(f'Platen_{i}',(.70,.60,.02),(x,0,.89),saw,'BrushedSteel',.002)
    marker(['Att_Input','Att_Process','Att_Output'][i],(x,0,.90),saw)
    text(f'FlowLabel_{i}',['EIN','PROZESS','AUS'][i],(x,.348,.88005),.041,saw,'Label')
    # Flat direction arrow on front lip, outside the free cargo prisms.
    mesh=bpy.data.meshes.new('FlowArrow')
    mesh.from_pydata([(x+.21,.33,.8801),(x+.21,.365,.8801),(x+.27,.3475,.8801)],[],[(0,2,1)])
    arrow=add_obj(f'Arrow_{i}',mesh,saw,'SafetyOrange');arrow['annotation']=True
    for dx in [-.30,.30]:
        for yy in [-.25,.25]: cylinder('PlatenBolt',.006,.001,(x+dx,yy,.8995),saw,'MachineSteel','Z',12)
for x in [-1.1,1.1]:
    for y in [-.35,.35]:
        box('Leg',(.10,.10,.80),(x,y,.40),saw,'MutedGreen',.005)
        box('FootPad',(.12,.10,.025),(x,y,.0125),saw,'Black',.003)
for y in [-.35,.35]: box('LongBrace',(2.10,.06,.06),(0,y,.25),saw,'MachineSteel',.003)
for x in [-1.1,1.1]: box('EndBrace',(.06,.60,.06),(x,0,.25),saw,'MachineSteel',.003)
box('MotorHousing',(.50,.40,.45),(0,0,.575),saw,'MutedGreen',.012)
for x in [-.185,.185]:
    box('MotorMount',(.045,.40,.06),(x,0,.77),saw,'MachineSteel',.003)
for x in np.linspace(-.17,.17,10):
    box('Vent',(.012,.002,.13),(float(x),.201,.55),saw,'Black',.002)
box('SwitchBox',(.16,.05,.13),(.16,.226,.71),saw,'MachineSteel',.005)
cylinder('StopButton',.028,.025,(.16,.263,.72),saw,'Red','Y')
box('StartButton',(.025,.015,.025),(.11,.263,.682),saw,'SafetyOrange',.003)
# Hidden blade is a separate moving part in the parked handover configuration.
blade=cylinder('Moving_Blade',.15,.005,(0,0,.62),saw,'BrushedSteel','Y',48)
cylinder('Base_BladeSpindle',.018,.36,(0,0,.62),saw,'MachineSteel','Y',20)
for y in [-.16,.16]:
    box('BladeBearingSupport',(.075,.035,.18),(0,y,.71),saw,'MachineSteel',.003)
    cylinder('BladeBearing',.031,.042,(0,y,.62),saw,'BrushedSteel','Y',20)
marker('Att_BladePivot',(0,0,.62),saw)
box('RearRail',(2.2,.08,.04),(0,-.35,.92),saw,'MachineSteel',.003)
for x in [-.13,.13]: box('GuardGuide',(.035,.045,.05),(x,-.35,.925),saw,'MachineSteel',.002)
box('Moving_ParkedGuard',(.38,.08,.45),(0,-.35,1.175),saw,'SafetyOrange',.012)
box('GuardStripe',(.31,.002,.026),(0,-.3085,1.19),saw,'Black',.001)
marker('Att_GuardPivot',(0,-.35,.95),saw)
box('StatusSupport',(.045,.05,.15),(.75,-.35,.975),saw,'MachineSteel',.003)
box('StatusPlate',(.40,.04,.40),(.75,-.35,1.25),saw,'MutedGreen',.008)
box('StatusBadge',(.34,.002,.09),(.75,-.3285,1.34),saw,'Label',.002)
text('StatusText','SAEGE 01',(.75,-.3269,1.34),.045,saw,front=True)
text('StatusParked','FREI',(.75,-.3269,1.22),.054,saw,'Label',front=True)
# Shape cue in addition to colour: engraved stop rectangle + four safety corner screws.
box('StatusSymbol',(.055,.001,.055),(.75,-.3269,1.12),saw,'SafetyOrange',.003)
for x in [.59,.91]:
    for z in [1.09,1.41]: cylinder('StatusFastener',.007,.002,(x,-.328,z),saw,'BrushedSteel','Y',12)

control=root('ControlCube_1m',(2.7,0,0))
box('ControlCube',(1,1,1),(0,0,.5),control,'Label')
control.hide_render=True
for o in control.children: o.hide_render=True

# Presentation uses a separate collection and never exports its floor/lights/text.
stage=box('PreviewFloor',(200,200,.02),(0,0,-.012),None,'Ground')
for name,pos,power,size in [('Key',(1,4,5),850,4),('Fill',(-3,2,3),500,3),('Rim',(2,-3,4),700,3)]:
    data=bpy.data.lights.new('P03_'+name,'AREA');data.energy=power;data.shape='DISK';data.size=size
    o=bpy.data.objects.new('P03_'+name,data);scene.collection.objects.link(o);o.location=pos
    o.rotation_euler=(Vector((0,0,.6))-o.location).to_track_quat('-Z','Y').to_euler()
camdata=bpy.data.cameras.new('P03_Camera');cam=bpy.data.objects.new('P03_Camera',camdata)
scene.collection.objects.link(cam);scene.camera=cam
cam.location=(3.6,4.9,3.0);aim=Vector((0,.3,.6))
cam.rotation_euler=(aim-cam.location).to_track_quat('-Z','Y').to_euler();camdata.type='ORTHO';camdata.ortho_scale=3.8
scene['package']='P03-02 v0.1 technical prototype'
scene['active_cut']='Not designed: parked handover mode only'
scene['art_approval']=False
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'p03-02-models-v01.blend'))
print(json.dumps({'scene':scene.name,'assets':list(assets),'objects':len(scene.objects),'file':bpy.data.filepath}))
