"""Build Bulldozer v03 using Riptide v02's studio and material palette.

Open riptide_v02.blend in background Blender, then run this script. The original
file serves as a template. All generated outputs have Bulldozer filenames.
"""
import math
from pathlib import Path
import sys

import bmesh
import bpy
from mathutils import Vector

PROJECT = Path(__file__).resolve().parents[2]
VERSION = 'v03'
SOURCE = PROJECT / f'art/source/robots/bulldozer/bulldozer_{VERSION}.blend'
EXPORT = PROJECT / f'assets/robots/bulldozer/bulldozer_{VERSION}.glb'
REVIEW = PROJECT / 'art/review/bulldozer'
for directory in (SOURCE.parent, EXPORT.parent, REVIEW):
    directory.mkdir(parents=True, exist_ok=True)

scene = bpy.context.scene
collection = bpy.data.collections['RIPTIDE_EDITABLE']
for obj in list(collection.objects):
    bpy.data.objects.remove(obj, do_unlink=True)
collection.name = 'BULLDOZER_EDITABLE'
bpy.context.preferences.filepaths.save_version = 0


def blender_coords(point):
    """Construct in Godot coordinates, then convert to Blender's Z-up space."""
    x, y, z = point
    return Vector((x, -z, y))


def recolor(base, name, hex_color, roughness):
    material = bpy.data.materials[base].copy()
    material.name = name
    srgb = [int(hex_color[i:i+2], 16) / 255 for i in (0, 2, 4)]
    linear = tuple(v / 12.92 if v <= .04045 else ((v + .055) / 1.055)**2.4 for v in srgb)
    material.diffuse_color = (*linear, 1)
    shader = material.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*linear, 1)
    shader.inputs['Roughness'].default_value = roughness
    return material


orange = recolor('Armor_Cyan', 'Armor_Orange', 'ff9045', .37)
gunmetal = recolor('Weapon_Steel', 'Drum_Gunmetal', '7e8c97', .37)
graphite = bpy.data.materials['Frame_Graphite']
steel = bpy.data.materials['Weapon_Steel']
rubber = bpy.data.materials['Tire_Rubber']
ivory = bpy.data.materials['Marking_Ivory']
lamp = bpy.data.materials['Status_Ice']
amber = bpy.data.materials['Safety_Amber']


def pivot(name, point=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None)
    collection.objects.link(obj)
    obj.parent = parent
    obj.location = blender_coords(point)
    obj.empty_display_size = .14
    return obj


root = pivot('Robot_Bulldozer')
root['asset_version'] = VERSION
root['forward_godot'] = '-Z'
root['ground_y_godot'] = -.4
chassis = pivot('Chassis', parent=root)


def finish(obj, name, parent, bevel):
    obj.name = name
    if collection not in obj.users_collection:
        for owner in list(obj.users_collection):
            owner.objects.unlink(obj)
        collection.objects.link(obj)
    obj.parent = parent
    obj.location -= parent.location
    if bevel:
        edge = obj.modifiers.new('Edge radius', 'BEVEL')
        edge.width = bevel
        edge.segments = 1 if bevel < .008 else 2
        normals = obj.modifiers.new('Weighted normals', 'WEIGHTED_NORMAL')
        normals.keep_sharp = True
    return obj


def box(name, point, dimensions, material, parent=chassis, bevel=.012):
    bpy.ops.mesh.primitive_cube_add(size=1, location=blender_coords(point))
    obj = bpy.context.object
    x, y, z = dimensions
    obj.scale = (x, z, y)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    return finish(obj, name, parent, bevel)


def cylinder(name, point, radius, depth, material, parent=chassis, axis='Y', segments=24, bevel=.005):
    bpy.ops.mesh.primitive_cylinder_add(vertices=segments, radius=radius, depth=depth,
                                      location=blender_coords(point))
    obj = bpy.context.object
    if axis == 'X':
        obj.rotation_euler.y = math.pi / 2
    elif axis == 'Z':
        obj.rotation_euler.x = math.pi / 2
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for face in obj.data.polygons:
        face.use_smooth = len(face.vertices) == 4 and segments > 8
    obj.data.materials.append(material)
    return finish(obj, name, parent, bevel)


def surface(name, points, faces, materials, parent=chassis, bevel=.012, face_materials=None):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([blender_coords(point) for point in points], [], faces)
    for material in materials:
        mesh.materials.append(material)
    if face_materials:
        for face, index in zip(mesh.polygons, face_materials, strict=True):
            face.material_index = index
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    return finish(obj, name, parent, bevel)


def armor(name, footprint, bottom, top, material, bevel=.016):
    n = len(footprint)
    points = [(x, height, z) for height in (bottom, top) for x, z in footprint]
    faces = [tuple(reversed(range(n))), tuple(range(n, 2*n))]
    faces += [(i, (i+1) % n, (i+1) % n+n, i+n) for i in range(n)]
    return surface(name, points, faces, [material], bevel=bevel)


def marking(name, text, point, size):
    font = bpy.data.curves.new(name, 'FONT')
    font.body = text
    font.size = size
    font.align_x = 'CENTER'
    font.align_y = 'CENTER'
    font.extrude = .0005
    font.resolution_u = 2
    font.materials.append(ivory)
    obj = bpy.data.objects.new(name, font)
    collection.objects.link(obj)
    obj.parent = chassis
    obj.location = blender_coords(point)
    obj.rotation_euler.z = math.pi


box('Recessed drivetrain', (0,.006,.035), (.95,.40,1.45), graphite, bevel=.043)
armor('Armored upper hull', [(-.64,-.76),(.64,-.76),(.72,-.64),(.72,.64),(.61,.76),
                            (-.61,.76),(-.72,.64),(-.72,-.64)], .196,.343,orange, .028)
box('Front plow crossmember', (0,.076,-.72), (.99,.23,.16), graphite, bevel=.023)
box('Rear recovery bumper', (0,-.047,.745), (.94,.18,.16), graphite, bevel=.024)
for x in (-.36,.36):
    box('Rear recovery lug', (x,-.038,.823), (.127,.106,.10), steel, bevel=.023)

for side, label in ((-1,'Port'), (1,'Starboard')):
    shoulder = [(.545,-.73),(.732,-.70),(.806,-.525),(.806,.543),(.731,.698),(.545,.73)]
    armor(f'{label} shoulder armor', [(side*x,z) for x,z in shoulder], .194,.379,orange, .024)
    skirt = [(.745,-.64),(.775,-.632),(.812,-.50),(.812,.50),(.775,.632),(.745,.64)]
    armor(f'{label} wheel guard', [(side*x,z) for x,z in skirt], -.095,.258,graphite, .012)
    box(f'{label} guard rub rail', (side*.814,.006,.014), (.028,.072,.82), steel, bevel=.012)
    for z in (-.45,.46):
        cylinder('Fender captive bolt', (side*.686,.383,z), .023,.013,steel, segments=6, bevel=.003)
    box('Headlight housing', (side*.545,.264,-.752), (.213,.078,.055), graphite)
    box('Ice white position light', (side*.545,.267,-.784), (.153,.027,.016),lamp, bevel=.005)
    box('Amber tail marker', (side*.57,.235,.757), (.128,.036,.028),amber, bevel=.006)

# Two distinct top panels give the robot a legible number and an asymmetric vent bank.
box('Race plate gasket', (-.287,.352,.102), (.40,.035,.81), graphite, bevel=.019)
box('Race plate', (-.287,.374,.10), (.355,.027,.753), orange, bevel=.012)
marking('Number 02', '02', (-.287,.389,.049), .263)
marking('Bulldozer wordmark', 'B U L L D O Z E R', (-.287,.389,.298), .052)
box('Service grille frame', (.231,.369,.107), (.42,.065,.86), graphite, bevel=.024)
box('Grille dark recess', (.231,.404,.136), (.342,.013,.642), rubber, bevel=.006)
for i in range(6):
    slat = box('Raised cooling vane', (.231,.421,-.115+i*.084), (.285,.028,.033), steel, bevel=.005)
    slat.rotation_euler.x = .22
box('Deck warning stripe', (0,.355,-.481), (.88,.018,.084), graphite, bevel=.005)
for i in range(7):
    stripe = box('Slanted warning mark', (-.34+i*.113,.366,-.481), (.052,.005,.065), amber, bevel=.002)
    stripe.rotation_euler.z = -.38

# Wheel hubs sit inside the guards. The tread radius puts the contact patch at Y = -0.40.
for side, letter in ((-1,'L'), (1,'R')):
    for z, end in ((-.433,'F'), (.433,'R')):
        x, y = side*.605, -.105
        name = f'Wheel_{end}{letter}'
        wheel = pivot(name, (x,y,z), root)
        wheel['axis_godot'] = 'X'
        cylinder('Recessed tire', (x,y,z), .281,.218,rubber,wheel,'X',32,.010)
        for i in range(18):
            angle = i * math.tau / 18
            cleat = box('Ribbed tread', (x,y+.285*math.cos(angle),z+.285*math.sin(angle)),
                        (.214,.019,.052),rubber,wheel,.004)
            cleat.rotation_euler.x = angle
        cylinder('Wheel rim', (side*.714,y,z), .175,.015,graphite,wheel,'X',24,.005)
        cylinder('Wheel hub', (side*.725,y,z), .098,.020,steel,wheel,'X',16,.004)
        cylinder('Wheel axle nut', (side*.735,y,z), .046,.016,amber,wheel,'X',6,.003)

drum_y, drum_z = -.021, -1.125
weapon = pivot('WeaponPivot', (0,drum_y,drum_z), root)
weapon['axis_godot'] = 'X'

# The orange forks and their bearing housings stay with the chassis.
bearing_profile = [(.193,-.680),(.314,-.677),(.292,-.808),(.116,-1.154),(.057,-1.218),
                   (-.068,-1.221),(-.132,-1.155),(-.122,-1.076),(.132,-.765)]
for side in (-1,1):
    count = len(bearing_profile)
    points = [(side*x,y,z) for x in (.668,.795) for y,z in bearing_profile]
    faces = [tuple(reversed(range(count))), tuple(range(count,2*count))]
    faces += [(i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count)]
    surface('Stationary drum fork', points, faces, [orange], bevel=.017)
    cylinder('Inner bearing seal', (side*.665,drum_y,drum_z), .089,.016,graphite,axis='X',segments=24)
    cylinder('Outer bearing flange', (side*.795,drum_y,drum_z), .099,.034,steel,axis='X',segments=24)
    cylinder('Fixed bearing cap', (side*.819,drum_y,drum_z), .054,.025,graphite,axis='X',segments=8)


cylinder('Machined steel drum', (0,drum_y,drum_z), .183,1.199,gunmetal,weapon,'X',48,.012)
for side in (-1,1):
    cylinder('Orange drum end ring', (side*.554,drum_y,drum_z), .198,.053,orange,weapon,'X',48,.007)
    cylinder('Steel drum end cap', (side*.606,drum_y,drum_z), .187,.047,steel,weapon,'X',48,.008)
    cylinder('Rotating journal', (side*.636,drum_y,drum_z), .062,.029,graphite,weapon,'X',24,.004)

for x in (-.324,-.108,.108,.324):
    cylinder('Drum separator rib', (x,drum_y,drum_z), .189,.025,steel,weapon,'X',48,.004)


def forged_spike(x, phase, tip_radius):
    """Build a chamfered spike with a dark seat and a bright raked point."""
    c, s = math.cos(phase), math.sin(phase)
    points = []
    for radial, scale, rake in ((.170,1.0,0),(.204,.88,.005),(tip_radius,.075,.021)):
        for i in range(8):
            angle = (i+.5)*math.tau/8
            axial = x+.078*scale*math.cos(angle)
            tangent = rake+.053*scale*math.sin(angle)
            points.append((axial, drum_y+radial*c+tangent*s, drum_z-radial*s+tangent*c))
    faces = [tuple(reversed(range(8))), tuple(range(16,24))]
    for start in (0,8):
        for i in range(8):
            a, b = start+i, start+(i+1)%8
            faces.append((a,b,b+8,a+8))
    surface('Forged drum spike', points, faces, [graphite,steel], weapon, .003,
            [0,1]+[0]*8+[1]*8)


# Three teeth per station, staggered along the axle so the pattern reads while spinning.
for station in range(-2,3):
    for tooth in range(3):
        phase = math.radians(39+station*19) + tooth*math.tau/3
        forged_spike(station*.216, phase, .294 if station==0 else .281)

sys.path.insert(0, str(Path(__file__).resolve().parent))
from export_robot import export_robot

export_robot(root, EXPORT)

camera = scene.camera


def camera_view(position, scale):
    camera.location = blender_coords(position)
    target = blender_coords((0,.01,-.32))
    camera.rotation_euler = (target-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale = scale


views = [('hero',(3.0,2.65,-4.0),3.6),('top',(0,5,-.32),3.25),('rear',(-3,2.2,3.5),3.6)]
camera_view(*views[0][1:])
bpy.ops.object.select_all(action='DESELECT')
root.select_set(True)
bpy.context.view_layer.objects.active = root
scene['asset_notes'] = f'Bulldozer {VERSION}. Transverse spiked drum rotates around local X. Blender +Y forward, Godot -Z forward.'
scene.render.filepath = f'//bulldozer_{VERSION}_hero.png'
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
for name, position, scale in views:
    camera_view(position, scale)
    scene.render.filepath = str(REVIEW/f'bulldozer_{VERSION}_{name}.png')
    bpy.ops.render.render(write_still=True)

print('RFS_ART_BUILD_COMPLETE', EXPORT)
