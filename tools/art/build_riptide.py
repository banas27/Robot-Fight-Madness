"""Build editable Riptide v02, export six rigid assemblies, render review stills.
Run with Blender --background --factory-startup --python tools/art/build_riptide.py
Only writes this asset's versioned outputs. No changes to R01 simulation files.
"""
import bpy
import json
import math
from pathlib import Path
from mathutils import Vector

PROJECT = Path(__file__).resolve().parents[2]
VERSION = 'v02'
SOURCE = PROJECT / f'art/source/robots/riptide/riptide_{VERSION}.blend'
EXPORT = PROJECT / f'assets/robots/riptide/riptide_{VERSION}.glb'
REVIEW = PROJECT / 'art/review/riptide'
for path in (SOURCE.parent, EXPORT.parent, REVIEW):
    path.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for unused in list(bpy.data.materials):
    if unused.users == 0:
        bpy.data.materials.remove(unused)
bpy.context.preferences.filepaths.save_version = 0
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
scene.render.engine = 'CYCLES'
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.render.resolution_x = 1500
scene.render.resolution_y = 1200
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.view_settings.view_transform = 'AgX'
scene.view_settings.exposure = -0.8
scene.world.color = (0.15, 0.15, 0.15)
scene.render.film_transparent = False

def g(v):
    return Vector((v[0], -v[2], v[1]))

def material(name, color, metallic, roughness, emission=0):
    rgb = [int(color[i:i+2], 16) / 255 for i in (0, 2, 4)]
    lin = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055)**2.4 for v in rgb]
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*lin, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*lin, 1)
    p.inputs['Metallic'].default_value = metallic
    p.inputs['Roughness'].default_value = roughness
    if emission:
        p.inputs['Emission Color'].default_value = (*lin, 1)
        p.inputs['Emission Strength'].default_value = emission
    return m

cyan = material('Armor_Cyan', '39d8e7', .25, .36)
dark = material('Frame_Graphite', '202d38', .65, .36)
rubber = material('Tire_Rubber', '10151a', .0, .82)
steel = material('Weapon_Steel', 'a5b7c4', .88, .27)
pale = material('Marking_Ivory', 'eaf2ec', .1, .45)
orange = material('Safety_Amber', 'e6a348', .45, .37)
lamp = material('Status_Ice', 'b4f8ff', .1, .3, 1.2)

asset_collection = bpy.data.collections.new('RIPTIDE_EDITABLE')
scene.collection.children.link(asset_collection)
studio = bpy.data.collections.new('STUDIO_NOT_EXPORTED')
scene.collection.children.link(studio)

def move_collection(obj, coll):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    coll.objects.link(obj)

def empty(name, at=(0,0,0), parent=None):
    o = bpy.data.objects.new(name, None)
    asset_collection.objects.link(o)
    o.location = g(at)
    o.empty_display_type = 'PLAIN_AXES'
    o.empty_display_size = .15
    if parent:
        o.parent = parent
    return o

root = empty('Robot_Riptide')
root['asset_version'] = VERSION
root['forward_godot'] = '-Z'
root['ground_y_godot'] = -.4
chassis = empty('Chassis', parent=root)
assemblies = [chassis]

def finish(o, name, mat, parent, bevel=0):
    o.name = name
    move_collection(o, asset_collection)
    o.data.materials.append(mat)
    if parent:
        # Locations provided to helpers are in asset space, not parent space.
        o.parent = parent
        o.location -= parent.location
    if bevel:
        mod = o.modifiers.new('Machined edge radius', 'BEVEL')
        mod.width = bevel
        mod.segments = 1 if ('tread' in name or 'stud' in name) else 2
        mod = o.modifiers.new('Weighted corner normals', 'WEIGHTED_NORMAL')
        mod.keep_sharp = True
    return o

def box(name, at, size, mat, parent=chassis, bevel=.012):
    bpy.ops.mesh.primitive_cube_add(size=1, location=g(at))
    o = bpy.context.object
    o.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o, name, mat, parent, bevel)

def cyl(name, at, radius, depth, mat, parent=chassis, axis='Y', verts=32, bevel=.006):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=g(at))
    o = bpy.context.object
    if axis == 'X':
        o.rotation_euler.y = math.pi / 2
    elif axis == 'Z':
        o.rotation_euler.x = math.pi / 2
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for p in o.data.polygons:
        p.use_smooth = len(p.vertices) == 4
    return finish(o, name, mat, parent, bevel)

def prism(name, footprint, bottom, top, mat, parent=chassis, bevel=.012):
    n = len(footprint)
    lows = [bottom]*n if isinstance(bottom, (float,int)) else bottom
    highs = [top]*n if isinstance(top, (float,int)) else top
    verts = [g((x,h,z)) for hs in (lows,highs) for (x,z),h in zip(footprint,hs)]
    faces = [tuple(reversed(range(n))), tuple(range(n,n*2))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    o = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(o)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    o.select_set(False)
    return finish(o,name,mat,parent,bevel)

def label(name, text, at, size, mat=pale, parent=chassis):
    font = bpy.data.curves.new(name, 'FONT')
    font.body = text
    font.size = size
    font.align_x = 'CENTER'
    font.align_y = 'CENTER'
    font.extrude = .0005
    font.resolution_u = 2
    o = bpy.data.objects.new(name,font)
    asset_collection.objects.link(o)
    o.location = g(at)
    o.rotation_euler.z = math.pi
    o.parent = parent
    o.location -= parent.location
    font.materials.append(mat)
    return o

# Raised prow leaves a physical gap over the rotor's complete swept envelope.
prism('Undercut structural hull', [(-.49,-.64),(.49,-.64),(.60,-.20),(.60,.48),(.45,.68),(-.45,.68),(-.60,.48),(-.60,-.20)],
      .205, .29, dark)
box('Recessed rear drivetrain',(0,.015,.30),(1.02,.33,.70),dark,bevel=.035)
for side in (-1,1):
    pts = [(side*x,z) for x,z in [(.12,-.59),(.47,-.62),(.59,-.15),(.57,.47),(.40,.65),(.20,.54),(.20,-.12)]]
    prism(('Port' if side<0 else 'Starboard')+' swept armor', pts,
          .28, [.36+z*.04 for _,z in pts], cyan, bevel=.018)
    box('Armor seam rail', (side*.53,.21,.24), (.035,.035,.53), steel, bevel=.005)
    for z in (.30,.43,.56):
        box('Rear cooling slot', (side*.35,.379,z), (.17,.013,.031), dark, bevel=.004)
    for x,z,y in [(side*.48,-.20,.361),(side*.48,.36,.384),(side*.35,.56,.392)]:
        cyl('Captive armor bolt',(x,y,z),.022,.012,steel,verts=6,bevel=.002)
    # Front position lamps and small inset protection bezels.
    box('Headlamp bezel',(side*.43,.275,-.624),(.16,.058,.038),dark,bevel=.01)
    box('Headlamp lens',(side*.43,.278,-.646),(.105,.022,.010),lamp,bevel=.005)
    box('Side skid rail',(side*.59,-.04,.12),(.07,.10,.42),steel,bevel=.025)

prism('Central service cover',[(-.16,-.35),(.16,-.35),(.19,.46),(.12,.61),(-.12,.61),(-.19,.46)],.30,.423,dark,bevel=.02)
box('Identification panel',(0,.432,.25),(.30,.013,.40),cyan,bevel=.018)
label('Race number','01',(0,.442,.27),.225)
label('RIPTIDE wordmark','R I P T I D E',(0,.433,-.18),.060)
for i in range(4):
    box('Service spine intake',(0,.436,-.02+i*.043),(.24,.012,.016),rubber,bevel=.004)
box('Rear bumper',(0,-.01,.67),(.80,.16,.10),dark,bevel=.04)
for x in (-.26,.26):
    box('Rear amber marker',(x,.11,.725),(.10,.03,.016),orange,bevel=.006)
box('Rear recovery handle',(0,.30,.64),(.20,.065,.08),steel,bevel=.02)
box('Handle dark center',(0,.33,.64),(.11,.03,.055),rubber,bevel=.008)

# Axle centers are empties with identity rotation and scale in the GLB.
for side,letter in [(-1,'L'),(1,'R')]:
    for z,where in [(-.43,'F'),(.43,'R')]:
        x=side*.73
        name=f'Wheel_{where}{letter}'
        pivot=empty(name,(x,-.08,z),root)
        pivot['axis_godot']='X'
        assemblies.append(pivot)
        cyl(name+' tire',(x,-.08,z),.307,.22,rubber,pivot,'X',32,.015)
        for k in range(20):
            theta=k*math.tau/20
            lug=box(name+' tread',(x,-.08+.308*math.cos(theta),z+.308*math.sin(theta)),(.224,.025,.049),rubber,pivot,.005)
            lug.rotation_euler.x=-theta
        outer=x+side*.116
        cyl(name+' rim',(outer,-.08,z),.225,.018,dark,pivot,'X',32,.008)
        cyl(name+' hub',(outer+side*.015,-.08,z),.107,.025,steel,pivot,'X',24,.006)
        cyl(name+' axle nut',(outer+side*.033,-.08,z),.043,.027,orange,pivot,'X',6,.002)
        for k in range(6):
            t=k*math.tau/6
            yy=-.08+.158*math.cos(t)
            zz=z+.158*math.sin(t)
            cyl(name+' rim stud',(outer+side*.012,yy,zz),.020,.012,steel,pivot,'X',6,.002)
        # A single pale sidewall index makes rotation easy to inspect.
        box(name+' sidewall index',(outer+side*.012,.183,z),(.010,.035,.044),pale,pivot,.003)
        cyl(name+' stationary axle',(side*.615,-.08,z),.075,.10,steel,chassis,'X',16,.005)

weapon=empty('WeaponPivot',(0,.04,-.87),root)
weapon['axis_godot']='Y'
assemblies.append(weapon)

def saw_blade():
    # Each tooth sweeps out from its gullet to a short, steep cutting face.
    tooth_profile = [(0, .482), (.16, .486), (.37, .519), (.74, .598), (.89, .588), (.97, .510)]
    tooth_count = 24
    samples = [((tooth + offset) * math.tau / tooth_count, radius)
               for tooth in range(tooth_count) for offset, radius in tooth_profile]
    count = len(samples)
    rings = (.090, .281, .395, None)
    vertices = []
    for ring in rings:
        for angle, tip_radius in samples:
            radius = tip_radius if ring is None else ring
            vertices.append(g((radius * math.cos(angle), .123, -.87 - radius * math.sin(angle))))
    faces = []
    for band in range(len(rings) - 1):
        for i in range(count):
            # Six evenly spaced slots through the plate expose the dark space below.
            if band == 1 and 5 <= i % (4 * len(tooth_profile)) < 15:
                continue
            next_i = (i + 1) % count
            faces.append((band * count + i, (band + 1) * count + i,
                          (band + 1) * count + next_i, band * count + next_i))
    mesh = bpy.data.meshes.new('Saw plate profile')
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    plate = bpy.data.objects.new('24-tooth saw plate', mesh)
    asset_collection.objects.link(plate)
    finish(plate, plate.name, steel, weapon, bevel=.004)
    plate.modifiers['Machined edge radius'].segments = 1
    thickness = plate.modifiers.new('Saw plate thickness', 'SOLIDIFY')
    thickness.thickness = .035
    thickness.offset = -1
    plate.modifiers.move(len(plate.modifiers) - 1, 0)

saw_blade()
cyl('Saw backing flange',(0,.068,-.87),.245,.049,dark,weapon,verts=48,bevel=.008)
cyl('Cyan saw hub',(0,.132,-.87),.215,.033,cyan,weapon,verts=48,bevel=.006)
for i in range(6):
    angle = i * math.tau / 6
    cyl('Saw hub fastener',(.172 * math.cos(angle),.152,-.87 - .172 * math.sin(angle)),
        .016,.013,dark,weapon,verts=6,bevel=.002)
cyl('Rotor center socket',(0,.173,-.87),.125,.069,dark,weapon,verts=32)
cyl('Rotor spindle cap',(0,.214,-.87),.071,.020,orange,weapon,verts=12,bevel=.004)
# The stationary bridge stays above the rotating hub and blade.
box('Raised bearing support',(0,.30,-.68),(.18,.10,.40),dark,bevel=.024)
cyl('Fixed bearing housing',(0,.275,-.87),.10,.055,steel,verts=32)
box('Spindle service stripe',(0,.355,-.66),(.055,.012,.24),cyan,bevel=.006)

# A compact studio is saved in the .blend but excluded from the runtime GLB.
floor_mat=material('Studio_Floor_NOT_EXPORTED','17252e',.10,.63)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.404))
floor=bpy.context.object
floor.name='Studio ground'
floor.data.materials.append(floor_mat)
move_collection(floor,studio)

def track(o,at):
    o.rotation_euler=(g(at)-o.location).to_track_quat('-Z','Y').to_euler()

def light(name,at,power,size,color):
    data=bpy.data.lights.new(name,'AREA')
    data.energy=power
    data.shape='DISK'
    data.size=size
    data.color=color
    o=bpy.data.objects.new(name,data)
    studio.objects.link(o)
    o.location=g(at)
    track(o,(0,0,-.25))

light('Large soft key',(1.5,5,-3),650,4.0,(.82,.94,1))
light('Warm rim',(-3,3,2),850,3,(1,.79,.54))
light('Cool frontal fill',(-3,1.6,-3),350,3,(.55,.83,1))
camera_data=bpy.data.cameras.new('Review Camera')
camera=bpy.data.objects.new('Review Camera',camera_data)
studio.objects.link(camera)
scene.camera=camera
camera_data.type='ORTHO'
camera_data.ortho_scale=3.50
camera.location=g((3.0,2.65,-4.0))
track(camera,(0,.02,-.32))

# Export evaluated copies; source modifiers and objects remain editable.
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from export_robot import export_robot
export_robot(root,EXPORT)

# Save useful Blender opening state, with the robot selected and studio collapsed.
bpy.ops.object.select_all(action='DESELECT')
root.select_set(True)
bpy.context.view_layer.objects.active=root
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_distance=4.0
            area.spaces.active.region_3d.view_location=g((0,0,-.3))
            area.spaces.active.region_3d.view_rotation=camera.rotation_euler.to_quaternion()
            area.spaces.active.shading.type='MATERIAL'
scene['asset_notes']=f'Riptide {VERSION}. Stylized industrial with a horizontal circular saw. Studio excluded from GLB. Units meters. Forward +Y Blender / -Z Godot.'
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))

views=[(f'riptide_{VERSION}_hero',(3.0,2.65,-4.0),3.5),
       (f'riptide_{VERSION}_top',(0,5,-.32),3.1),
       (f'riptide_{VERSION}_rear',(-3,2.2,3.5),3.5)]
for name,position,scale in views:
    camera.location=g(position)
    track(camera,(0,.02,-.32))
    camera_data.ortho_scale=scale
    scene.render.filepath=str(REVIEW/(name+'.png'))
    bpy.ops.render.render(write_still=True)

print('RFS_ART_BUILD_COMPLETE',str(EXPORT))
