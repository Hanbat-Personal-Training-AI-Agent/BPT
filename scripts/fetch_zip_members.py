"""List or extract members of a remote zip over HTTP range requests (no full download).
usage: python3 -I fetch_zip_members.py <url> <outdir> [member-regex]   (no regex = list members)"""
import io, sys, zipfile, urllib.request
class HTTPFile:
    def __init__(s, url):
        s.url=url; s.pos=0
        r=urllib.request.urlopen(urllib.request.Request(url,method='HEAD')); s.size=int(r.headers['Content-Length'])
    def seekable(s): return True
    def readable(s): return True
    def tell(s): return s.pos
    def seek(s,o,w=0):
        s.pos={0:o,1:s.pos+o,2:s.size+o}[w]; return s.pos
    def read(s,n=-1):
        if n<0: n=s.size-s.pos
        if n==0 or s.pos>=s.size: return b''
        e=min(s.size,s.pos+n)-1
        d=urllib.request.urlopen(urllib.request.Request(s.url,headers={'Range':f'bytes={s.pos}-{e}'})).read()
        s.pos+=len(d); return d
url, out = sys.argv[1], sys.argv[2]
z=zipfile.ZipFile(HTTPFile(url))
names=z.namelist()
if len(sys.argv)==3:
    for i in z.infolist(): print(i.filename, i.file_size)
else:
    import re
    for n in names:
        if re.search(sys.argv[3], n): z.extract(n, out); print('got', n)
