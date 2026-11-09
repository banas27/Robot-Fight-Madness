"""Compare saved-Blender re-export with the delivered GLB, allowing float roundoff."""
import json
from pathlib import Path
import struct

project=Path(__file__).resolve().parents[2]
blobs=[(project/p).read_bytes() for p in ('assets/robots/riptide/riptide_v02.glb','qa/art-r01/roundtrip-v02.glb')]
sizes=[struct.unpack_from('<I',b,12)[0] for b in blobs]
docs=[json.loads(b[20:20+s]) for b,s in zip(blobs,sizes)]
bins=[b[28+s:] for b,s in zip(blobs,sizes)]
report={'nodes_identical':docs[0]['nodes']==docs[1]['nodes'],
        'accessors_identical':docs[0]['accessors']==docs[1]['accessors'],
        'materials_identical':docs[0]['materials']==docs[1]['materials'],
        'differences':[]}
dimensions={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}
formats={5126:'f',5123:'H',5125:'I'}
for index,accessor in enumerate(docs[0]['accessors']):
    values=[]
    for doc,binary in zip(docs,bins):
        a=doc['accessors'][index]
        view=doc['bufferViews'][a['bufferView']]
        count=a['count']*dimensions[a['type']]
        offset=view.get('byteOffset',0)+a.get('byteOffset',0)
        values.append(struct.unpack_from('<'+str(count)+formats[a['componentType']],binary,offset))
    error=max(abs(x-y) for x,y in zip(*values))
    if error:
        report['differences'].append({'accessor':index,'max_error':error,'component_type':accessor['componentType']})
report['passed']=all(report[k] for k in ('nodes_identical','accessors_identical','materials_identical')) and all(
    d['component_type']==5126 and d['max_error']<1e-5 for d in report['differences'])
(project/'qa/art-r01/source-roundtrip.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
assert report['passed']
