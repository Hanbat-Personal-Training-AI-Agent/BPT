import sys, collections
from coremltools.proto import Model_pb2
def ops(p):
    m = Model_pb2.Model(); m.ParseFromString(open(p,'rb').read())
    out=[]
    for fn in m.mlProgram.functions.values():
        for blk in fn.block_specializations.values():
            for op in blk.operations:
                shp=[]
                for o in op.outputs:
                    t=o.type.tensorType; shp.append(tuple(d.constant.size for d in t.dimensions))
                out.append((op.type, tuple(shp)))
    return out, m.specificationVersion
a,va=ops(sys.argv[1]); b,vb=ops(sys.argv[2])
print('ops', len(a), len(b), 'spec', va, vb)
print('identical op type+output-shape sequence:', a==b)
print('types', collections.Counter(t for t,_ in a)==collections.Counter(t for t,_ in b))
if a!=b:
    print([ (i,x,y) for i,(x,y) in enumerate(zip(a,b)) if x!=y][:5])
