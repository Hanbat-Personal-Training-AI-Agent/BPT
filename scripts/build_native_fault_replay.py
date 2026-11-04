#!/usr/bin/env python3
"""Build only PoseReplay under the shared lock and freeze source/binary provenance.

Does not run inference. Its JSON is embedded as buildManifest in --fault-binding.
"""
from __future__ import annotations
import argparse
import fcntl
import hashlib
import json
import pathlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]


def digest(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def sources(root: pathlib.Path) -> dict[str, str]:
    paths = list((root / 'ios/CalibrationEngineKit/Sources/PoseReplay').glob('*.swift'))
    paths.append(root / 'ios/CalibrationEngineKit/Package.swift')
    return {str(p.resolve().relative_to(root.resolve())): digest(p) for p in sorted(paths)}


def command(*args: str) -> str:
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scratch-path', type=pathlib.Path, required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('output exists; choose a new manifest path')
    # Protect all local heavy work; waiting is visible and consumes no model resources.
    with open('/tmp/bpt-heavy.lock', 'a') as lock:
        print('Waiting for /tmp/bpt-heavy.lock', flush=True)
        fcntl.flock(lock, fcntl.LOCK_EX)
        if shutil.disk_usage(ROOT).free < 1024**3:
            parser.error('less than 1 GiB free; preserve the storage floor')
        candidate = command('git', 'rev-parse', 'HEAD')
        before = sources(ROOT)
        for path, sha in before.items():
            committed = subprocess.check_output(['git', 'show', f'{candidate}:{path}'], cwd=ROOT)
            if hashlib.sha256(committed).hexdigest() != sha:
                parser.error(f'source differs from candidate commit: {path}')
        cmd = ['swift', 'build', '--package-path', 'ios/CalibrationEngineKit',
               '--scratch-path', str(args.scratch_path.resolve()), '-c', 'release',
               '--product', 'pose-replay', '--jobs', '2']
        subprocess.run(cmd, cwd=ROOT, check=True)
        after = sources(ROOT)
        if before != after or command('git', 'rev-parse', 'HEAD') != candidate:
            parser.error('source or candidate changed during build; discard this binary')
        bin_dir = command('swift', 'build', '--package-path', 'ios/CalibrationEngineKit',
                          '--scratch-path', str(args.scratch_path.resolve()), '-c', 'release',
                          '--show-bin-path')
        binary = pathlib.Path(bin_dir) / 'pose-replay'
        manifest = {'contract': 'bpt-pose-replay-build-v1', 'candidateId': candidate,
                    'sourceSHA256': before, 'sourceStableAcrossBuild': True,
                    'executablePath': str(binary), 'executableSHA256': digest(binary),
                    'swiftVersion': command('swift', '--version'), 'buildCommand': cmd}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open('x') as out:
            json.dump(manifest, out, indent=2, sort_keys=True)
            out.write('\n')
        print(f'Frozen build: {args.output}; no inference executed', flush=True)


if __name__ == '__main__':
    main()
