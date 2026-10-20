"""Write <run_dir>/manifest.json: command, code commit, host, sha256 of the given inputs and of every file in run_dir.

usage: manifest.py RUN_DIR --commit SHA --cmd "..." [--note "..."] --inputs FILE_OR_DIR ...
Directories in --inputs are hashed per file (sorted relative paths); Fit3D inputs are hashed, never copied.
"""
import argparse, datetime, hashlib, json, os, socket


def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''): h.update(b)
    return h.hexdigest()


def tree(p, skip=()):
    if os.path.isfile(p): return {os.path.basename(p): sha(p)}
    out = {}
    for d, _, fs in os.walk(p):
        for f in sorted(fs):
            q = os.path.join(d, f); r = os.path.relpath(q, p)
            if r not in skip: out[r] = sha(q)
    return dict(sorted(out.items()))


def main():
    p = argparse.ArgumentParser(); p.add_argument('run_dir'); p.add_argument('--commit', required=True)
    p.add_argument('--cmd', required=True); p.add_argument('--note', default='')
    p.add_argument('--inputs', nargs='*', default=[])
    a = p.parse_args()
    m = dict(created=datetime.datetime.now().astimezone().isoformat(timespec='seconds'), host=socket.gethostname(),
             code_commit=a.commit, command=a.cmd, note=a.note,
             inputs={os.path.abspath(i): tree(i) for i in a.inputs},
             outputs=tree(a.run_dir, skip=('manifest.json',)))
    json.dump(m, open(os.path.join(a.run_dir, 'manifest.json'), 'w'), indent=1)
    print(a.run_dir, len(m['outputs']), 'outputs')


if __name__ == '__main__':
    main()
