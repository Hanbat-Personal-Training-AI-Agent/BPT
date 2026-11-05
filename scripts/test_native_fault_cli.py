#!/usr/bin/env python3
"""Focused headless CLI checks. No media decoding, models, phone or UI."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--build-manifest', type=Path, required=True)
    args = parser.parse_args()
    binary = str(args.binary.resolve())
    build = json.loads(args.build_manifest.read_text())
    with tempfile.TemporaryDirectory(prefix='bpt-fault-cli-check-') as directory:
        root = Path(directory)
        video = root / 'empty.mp4'
        video.write_bytes(b'no decoding is permitted by these validation checks')
        binding = root / 'binding.json'
        clip = {'candidateId': build['candidateId'], 'clipId': 'synthetic-validation-only',
                'sourceSHA256': hashlib.sha256(video.read_bytes()).hexdigest()}
        def write_binding():
            binding.write_text(json.dumps({'buildManifest': build, 'clips': [clip]}))
        write_binding()
        def reject(options, expected):
            result = subprocess.run([binary, *options, str(video)], text=True, capture_output=True)
            assert result.returncode != 0, result.stdout
            assert expected in result.stdout + result.stderr, result.stderr
        reject(['--fault-trace-dir', str(root / 'trace')], 'must be supplied together')
        reject(['--fault-trace-dir', str(root / 'trace'), '--fault-binding', str(binding),
                '--keypoints-csv', 'missing.csv'], 'rounded CSV timestamps')
        reject(['--fault-trace-dir', str(root / 'trace'), '--fault-binding', str(binding),
                '--exercise', 'bench'], 'only squat, pushup and row')
        clip['sourceSHA256'] = '0' * 64
        write_binding()
        reject(['--fault-trace-dir', str(root / 'trace'), '--fault-binding', str(binding)],
               'full source SHA256 mismatch')
        clip['candidateId'] = 'arbitrary-label'
        write_binding()
        reject(['--fault-trace-dir', str(root / 'trace'), '--fault-binding', str(binding)],
               'frozen 40-hex commit')
        clip['candidateId'] = build['candidateId']
        clip['taskId'] = 'must-not-prebind'
        write_binding()
        reject(['--fault-trace-dir', str(root / 'trace'), '--fault-binding', str(binding)],
               'task/boundary unbound')
        # Default-off CSV replay remains model-free and emits only the original output shape.
        csv = root / 'pose.csv'
        header = ['frame', 'time', 'status', 'rep'] + [f'j{j}_{v}' for j in range(17) for v in ['x', 'y', 'c']]
        rows = [','.join([str(i), str(i / 30), '', '0'] + ['0'] * 51) for i in range(3)]
        csv.write_text(','.join(header) + '\n' + '\n'.join(rows) + '\n')
        result = subprocess.run([binary, '--motion3d', 'none', '--keypoints-csv', str(csv),
                                 '--output-dir', str(root / 'output'), str(video)],
                                text=True, capture_output=True)
        assert result.returncode == 0, result.stderr
        reports = list((root / 'output').glob('*.json'))
        assert len(reports) == 1
        report = json.loads(reports[0].read_text())
        assert report['frames'] == 3
        assert not any('fault' in key.lower() for key in report)
        assert not (root / 'trace').exists(), 'rejected checks created a trace directory'
    print('7 focused CLI checks passed; no inference or UI used')


if __name__ == '__main__':
    main()
