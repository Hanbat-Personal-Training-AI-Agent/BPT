"""Offline executable regression; set BPT_POSE_REPLAY to a built macOS pose-replay.

Only synthetic CSVs are opened. --motion3d none and --keypoints-csv prevent model
inference and video loading. No model/default configuration is changed.
"""
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


@unittest.skipUnless(os.environ.get('BPT_POSE_REPLAY'), 'requires an existing macOS pose-replay executable')
class PoseReplayCSVTests(unittest.TestCase):
    def check_roundtrip(self, joints, output_joints, extra_names=None):
        binary = Path(os.environ['BPT_POSE_REPLAY']).resolve()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, output = root/'source.csv', root/'output'
            header = ['frame', 'time', 'status', 'rep'] + [
                f'j{joint}_{axis}' for joint in range(joints) for axis in ('x','y','c')]
            if extra_names is not None:
                header[4+17*3:] = extra_names
            rows = [[frame,frame/30,'top',0] + [value for joint in range(joints)
                    for value in (10+joint*2+frame,20+joint*3+frame,.9)] for frame in range(6)]
            with source.open('w', newline='') as stream:
                writer=csv.writer(stream); writer.writerow(header); writer.writerows(rows)
            before=hashlib.sha256(source.read_bytes()).hexdigest()
            environment=os.environ.copy(); environment.pop('BPT_POSE_MODEL',None)
            subprocess.run([str(binary),'--model','mhalpe26','--motion3d','none',
                '--image-size','640x480','--keypoints-csv',str(source),'--output-dir',str(output),
                str(root/'synthetic_unopened.mp4')],env=environment,check=True,capture_output=True,text=True)
            with next(output.glob('*.csv')).open() as stream:
                actual=list(csv.reader(stream))
            self.assertEqual(len(actual),7)
            self.assertEqual(len(actual[0]),4+output_joints*3)
            for row, saved in zip(rows,actual[1:]):
                for value, retained in zip(row[4:4+output_joints*3],saved[4:]):
                    self.assertAlmostEqual(value,float(retained),places=4)
            report=json.loads(next(output.glob('*.json')).read_text())
            self.assertEqual(report['frames'],6)
            self.assertIsNone(report['motion3d'])
            self.assertFalse((root/'synthetic_unopened.mp4').exists())
            self.assertEqual(before,hashlib.sha256(source.read_bytes()).hexdigest())

    def test_coco17_legacy_columns_are_preserved(self):
        self.check_roundtrip(17,17)

    def test_named_halpe26_extras_are_preserved(self):
        self.check_roundtrip(26,26)

    def test_unrelated_trailing_metrics_are_not_halpe_joints(self):
        self.check_roundtrip(26,17,[f'metric{index}' for index in range(27)])

    def test_incomplete_halpe_header_is_not_partial_feet(self):
        self.check_roundtrip(25,17)

    def test_reordered_halpe_columns_are_not_silently_misinterpreted(self):
        names=[f'j{joint}_{axis}' for joint in range(17,26) for axis in ('x','y','c')]
        names[0],names[1]=names[1],names[0]
        self.check_roundtrip(26,17,names)


if __name__ == '__main__':
    unittest.main()
