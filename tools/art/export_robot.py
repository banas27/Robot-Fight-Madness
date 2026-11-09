"""Export edits from an open/saved .blend without rebuilding or saving over it.
blender --background path/to/source.blend --python tools/art/export_robot.py -- 
    --root Robot_Riptide --output assets/robots/riptide/riptide_v02.glb
Root children are rigid assemblies, with editable meshes directly beneath them.
"""
import argparse
import bpy
import json
from pathlib import Path
import struct
import sys

def export_robot(root, output):
    output=Path(output).resolve()
    output.parent.mkdir(parents=True,exist_ok=True)
    source_scene=bpy.context.scene
    bpy.context.view_layer.update()
    depsgraph=bpy.context.evaluated_depsgraph_get()
    temp=bpy.data.scenes.new('GLB_EXPORT_TEMP')
    export_root=bpy.data.objects.new(root.name+'_EXPORT',None)
    temp.collection.objects.link(export_root)
    for key in root.keys():
        export_root[key]=root[key]
    copies=[]
    try:
        for assembly in root.children:
            ep=bpy.data.objects.new(assembly.name,None)
            temp.collection.objects.link(ep)
            ep.parent=export_root
            ep.matrix_basis=assembly.matrix_basis.copy()
            for key in assembly.keys():
                ep[key]=assembly[key]
            meshes=[]
            for src in assembly.children:
                if src.type not in ('MESH','FONT'):
                    continue
                mesh=bpy.data.meshes.new_from_object(src.evaluated_get(depsgraph),depsgraph=depsgraph)
                obj=bpy.data.objects.new(src.name+'_export',mesh)
                temp.collection.objects.link(obj)
                obj.matrix_world=src.matrix_world.copy()
                meshes.append(obj)
            if not meshes:
                raise ValueError(f'Empty export assembly: {assembly.name}')
            copies.append((assembly.name,ep,meshes))
        bpy.context.window.scene=temp
        bpy.context.view_layer.update()
        for name,ep,meshes in copies:
            bpy.ops.object.select_all(action='DESELECT')
            for obj in meshes:
                obj.select_set(True)
            bpy.context.view_layer.objects.active=meshes[0]
            bpy.ops.object.join()
            obj=meshes[0]
            obj.name={'WeaponPivot':'WeaponMesh','Chassis':'ChassisMesh'}.get(name,name+'_Mesh')
            obj.data.transform(ep.matrix_world.inverted() @ obj.matrix_world)
            obj.parent=ep
            obj.matrix_basis.identity()
            tri=obj.modifiers.new('Export triangulation','TRIANGULATE')
            bpy.ops.object.modifier_apply(modifier=tri.name)
        bpy.ops.export_scene.gltf(filepath=str(output),export_format='GLB',use_active_scene=True,
            export_yup=True,export_apply=True,export_animations=False,export_cameras=False,
            export_lights=False,export_extras=True)
        # Remove temporary Blender name suffixes; binary mesh data stays untouched.
        blob=output.read_bytes()
        size,kind=struct.unpack_from('<II',blob,12)
        doc=json.loads(blob[20:20+size])
        for node in doc.get('nodes',[]):
            node['name']=node.get('name','').replace('_EXPORT','').split('.')[0]
        payload=json.dumps(doc,separators=(',',':')).encode()
        payload+=b' '*((-len(payload))%4)
        tail=blob[20+size:]
        output.write_bytes(struct.pack('<4sII',b'glTF',2,20+len(payload)+len(tail))+
                           struct.pack('<II',len(payload),kind)+payload+tail)
    finally:
        bpy.context.window.scene=source_scene
        for obj in list(temp.objects):
            bpy.data.objects.remove(obj,do_unlink=True)
        bpy.data.scenes.remove(temp)

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--root',required=True)
    parser.add_argument('--output',required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    export_robot(bpy.data.objects[args.root],args.output)
    print('RFS_EXPORT_COMPLETE',args.output)
