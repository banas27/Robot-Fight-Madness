"""Validate a review GLB and optionally compare the two arena scenes in Godot.
Defaults to Riptide. Use --robot bulldozer to validate Bulldozer.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess

PROJECT = Path(__file__).resolve().parents[2]
QA = PROJECT / 'qa/art-r01'
ASSET_CONTRACTS = {
    'riptide': ('v03', .73, -.08, .43, (0,.04,-.87), 'Y'),
    'bulldozer': ('v04', .605, -.105, .433, (0,-.021,-1.125), 'X'),
}

def validate_glb(robot):
    version, axle_x, axle_y, axle_z, weapon_position, weapon_axis = ASSET_CONTRACTS[robot]
    path = PROJECT / f'assets/robots/{robot}/{robot}_{version}.glb'
    blob = path.read_bytes()
    magic, glb_version, length = struct.unpack_from('<4sII', blob)
    assert magic == b'glTF' and glb_version == 2 and length == len(blob)
    json_length, kind = struct.unpack_from('<II', blob, 12)
    assert kind == 0x4E4F534A
    doc = json.loads(blob[20:20 + json_length])
    binary = blob[28 + json_length:]
    assert not doc.get('images') and not doc.get('cameras') and not doc.get('skins')
    assert all('uri' not in b for b in doc['buffers'])
    assert len(doc['meshes']) == 6
    assert len(doc['materials']) <= 8 and len(blob) < 5_000_000
    triangles = sum(doc['accessors'][p['indices']]['count']//3
                    for mesh in doc['meshes'] for p in mesh['primitives'])
    assert triangles < 28_000, triangles
    root = f'Robot_{robot.title()}'
    expected = {root: (0,0,0), 'Chassis': (0,0,0),
                'Wheel_FL': (-axle_x,axle_y,-axle_z), 'Wheel_FR': (axle_x,axle_y,-axle_z),
                'Wheel_RL': (-axle_x,axle_y,axle_z), 'Wheel_RR': (axle_x,axle_y,axle_z),
                'WeaponPivot': weapon_position}
    nodes = {node['name']: node for node in doc['nodes']}
    assert len(nodes) == len(doc['nodes'])
    assert nodes['WeaponPivot']['extras']['axis_godot'] == weapon_axis
    for name, position in expected.items():
        n = nodes[name]
        assert all(abs(a-b)<.00001 for a,b in zip(n.get('translation',[0,0,0]),position)), name
    for n in nodes.values():
        assert 'matrix' not in n
        assert n.get('rotation',[0,0,0,1]) == [0,0,0,1], n
        assert n.get('scale',[1,1,1]) == [1,1,1], n

    bounds = {}
    def visit(index, parent=(0,0,0)):
        node = doc['nodes'][index]
        pos = tuple(a+b for a,b in zip(parent,node.get('translation',[0,0,0])))
        if 'mesh' in node:
            points = []
            for primitive in doc['meshes'][node['mesh']]['primitives']:
                accessor = doc['accessors'][primitive['attributes']['POSITION']]
                view = doc['bufferViews'][accessor['bufferView']]
                assert accessor['type']=='VEC3' and accessor['componentType']==5126
                offset = view.get('byteOffset',0) + accessor.get('byteOffset',0)
                for i in range(accessor['count']):
                    v = struct.unpack_from('<fff',binary,offset+i*view.get('byteStride',12))
                    assert all(math.isfinite(x) for x in v)
                    points.append(tuple(a+b for a,b in zip(v,pos)))
            bounds[node['name']] = {'min':[min(v[i] for v in points) for i in range(3)],
                                    'max':[max(v[i] for v in points) for i in range(3)]}
        for child in node.get('children',[]):
            visit(child,pos)
    for index in doc['scenes'][doc.get('scene',0)]['nodes']:
        visit(index)
    low = [min(b['min'][i] for b in bounds.values()) for i in range(3)]
    high = [max(b['max'][i] for b in bounds.values()) for i in range(3)]
    assert -.405 <= low[1] <= -.395, low
    assert high[1] < .46 and high[0]-low[0] < 1.85
    assert nodes[root]['extras']['asset_version'] == version
    manifest = {'id':robot,'version':version,'status':'visual_review',
                'style':'stylized industrial','source':f'art/source/robots/{robot}/{path.stem}.blend',
                'runtime':path.relative_to(PROJECT).as_posix(),'units':'meters',
                'up':'+Y','forward':'-Z','ground_y':-.4,'runtime_scale':1.0,
                'triangle_count':triangles,'mesh_count':len(doc['meshes']),
                'materials':[m['name'] for m in doc['materials']],
                'surface_count':sum(len(m['primitives']) for m in doc['meshes']),
                'bytes':len(blob),'sha256':hashlib.sha256(blob).hexdigest(),
                'bounds':{'min':low,'max':high,'size':[b-a for a,b in zip(low,high)]},
                'assembly_bounds':bounds,'pivot_positions':expected,
                'rotation_axes':{k:(weapon_axis if k=='WeaponPivot' else 'X') for k in expected if k.startswith(('Wheel','Weapon'))},
                'collision':'runtime compound fit in scripts/combat/collision_fit.gd',
                'textures':[],'blender_version':'5.1.2','godot_validated':'4.7.2'}
    (path.parent/'asset.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(f'GLB PASS: {triangles:,} triangles; {len(doc["materials"])} materials; {len(blob):,} bytes')
    return manifest

def combat_check(godot):
    comparisons = []
    for seed in (1,7,10):
        reports = []
        for label,scene in [('baseline','res://scenes/arena.tscn'),('art','res://scenes/review/arena_art_review.tscn')]:
            report = QA/f'{label}-seed-{seed}.json'
            result = subprocess.run([godot,'--headless','--path',str(PROJECT),'--fixed-fps','60',scene,
                                     '--','--autostop',f'--seed={seed}',f'--report={report}'],capture_output=True,text=True,timeout=45)
            (QA/f'{label}-seed-{seed}.log').write_text(result.stdout+result.stderr)
            assert result.returncode==0 and 'ERROR:' not in result.stdout+result.stderr, result.stdout+result.stderr
            data=json.loads(report.read_text())
            assert data['events'] and data['winner'] in ('RIPTIDE','BULLDOZER','DRAW')
            assert 0 < data['fight_duration'] <= 22.1 and data['max_arena_extent_ratio'] < 1.08
            reports.append(data)
        assert reports[0]==reports[1], f'Cosmetic adapter changed report, seed {seed}'
        comparisons.append({'seed':seed,'reports_identical':True,'winner':reports[0]['winner'],
                            'duration':reports[0]['duration'],'hits':reports[0]['hits']})
        print(f'COMBAT PASS seed={seed}: original and art reports identical')
    (QA/'regression-results.json').write_text(json.dumps(comparisons,indent=2)+'\n')

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--robot', choices=ASSET_CONTRACTS, default='riptide')
    parser.add_argument('--asset-only', action='store_true', help='Validate the GLB and refresh its manifest')
    parser.add_argument('--godot')
    args=parser.parse_args()
    validate_glb(args.robot)
    if args.asset_only:
        return
    hashes=json.loads((QA/'original-file-hashes.json').read_text(encoding='utf-8-sig'))
    for entry in hashes:
        # R02 intentionally changed the entry scene, viewport and shared HUD.
        if entry['Path'] in ('project.godot', 'scripts/hud.gd'):
            continue
        assert hashlib.sha256((PROJECT/entry['Path']).read_bytes()).hexdigest().upper()==entry['SHA256'], entry['Path']
    print('SOURCE PASS: six legacy arena, robot and launcher files match the original hashes')
    if args.godot:
        imported=subprocess.run([args.godot,'--headless','--editor','--path',str(PROJECT),'--import'],
                                capture_output=True,text=True,timeout=60)
        (QA/'godot-import.log').write_text(imported.stdout+imported.stderr)
        assert imported.returncode==0 and 'ERROR:' not in imported.stdout+imported.stderr, imported.stdout+imported.stderr
        combat_check(args.godot)

if __name__=='__main__':
    main()
