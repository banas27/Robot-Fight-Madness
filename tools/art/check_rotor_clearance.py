"""Blender geometric check against the actual GLB at 5 degree intervals."""
import bpy
import json
import math
from pathlib import Path
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

project=Path(__file__).resolve().parents[2]
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(project/'assets/robots/riptide/riptide_v02.glb'))
bpy.context.view_layer.update()
rotor=bpy.data.objects['WeaponMesh']
pivot=bpy.data.objects['WeaponPivot'].matrix_world.translation.copy()
static=[]
for obj in bpy.context.scene.objects:
    if obj.type=='MESH' and obj!=rotor:
        verts=[obj.matrix_world @ v.co for v in obj.data.vertices]
        static.append((obj.name,BVHTree.FromPolygons(verts,[tuple(p.vertices) for p in obj.data.polygons],all_triangles=True)))
source=[rotor.matrix_world @ v.co for v in rotor.data.vertices]
faces=[tuple(p.vertices) for p in rotor.data.polygons]
failures=[]
for degrees in range(0,360,5):
    # Blender Z is Godot Y after glTF conversion.
    rotation=Matrix.Rotation(math.radians(degrees),4,'Z')
    verts=[pivot + rotation @ (v-pivot) for v in source]
    tree=BVHTree.FromPolygons(verts,faces,all_triangles=True)
    for name,other in static:
        overlaps=tree.overlap(other)
        if overlaps:
            failures.append({'angle_degrees':degrees,'assembly':name,'intersecting_triangle_pairs':len(overlaps)})
result={'method':'Blender BVH triangle intersection on imported GLB','samples':72,'step_degrees':5,
        'note':'Sampled geometric sweep, not continuous collision or physical weapon validation.',
        'passed':not failures,'intersections':failures}
(project/'qa/art-r01/rotor-clearance.json').write_text(json.dumps(result,indent=2)+'\n')
assert not failures, json.dumps(failures[:10])
print('RFS_ROTOR_CLEARANCE_PASS: 72 sampled poses; no rotor / chassis / wheel intersections')
