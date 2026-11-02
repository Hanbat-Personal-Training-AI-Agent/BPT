"""Synthetic archive admission only; real model evidence is never synthesized."""
import importlib.util
import copy
from pathlib import Path
import stat
import tempfile
import unittest
import zipfile

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('verify_output',ROOT/'scripts/deep_analysis/verify_native_deep_output.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)


class ArchiveAdmissionTests(unittest.TestCase):
    def archive(self,path,extra=None,missing=None,symlink=False):
        with zipfile.ZipFile(path,'w') as out:
            for name in m.REQUIRED|{'before_metrics.json'}:
                if name!=missing:out.writestr(name,b'synthetic-not-model-evidence')
            if extra:
                if symlink:
                    info=zipfile.ZipInfo(extra);info.external_attr=(stat.S_IFLNK|0o777)<<16;out.writestr(info,b'/private/forbidden')
                else:out.writestr(extra,b'synthetic')

    def test_allowed_exact_file_names_extract_exclusively(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);archive=root/'result.zip';out=root/'out';out.mkdir();self.archive(archive)
            m.unpack_checked(archive,out)
            self.assertEqual({p.name for p in out.iterdir()},m.REQUIRED|{'before_metrics.json'})
            with self.assertRaises(FileExistsError):m.unpack_checked(archive,out)

    def test_missing_required_and_traversal_or_unexpected_file_reject(self):
        for extra,missing in [('../outside',None),('unknown-file',None),(None,'evidence.json')]:
            with tempfile.TemporaryDirectory() as directory:
                root=Path(directory);out=root/'out';out.mkdir();archive=root/'result.zip';self.archive(archive,extra,missing)
                with self.assertRaises(ValueError):m.unpack_checked(archive,out)
                self.assertFalse((root/'outside').exists())

    def test_success_error_contradiction_or_symlink_rejected(self):
        for extra,symlink in [('current_error.json',False),('before_error.json',False),('run.log',True)]:
            with tempfile.TemporaryDirectory() as directory:
                root=Path(directory);out=root/'out';out.mkdir();archive=root/'result.zip';self.archive(archive,extra,missing=extra if symlink else None,symlink=symlink)
                with self.assertRaises(ValueError):m.unpack_checked(archive,out)

    def test_partial_geometry_and_untracked_withholding_are_admitted_as_report_contract(self):
        report={'reps':[{'repIndex':1,'anglesDeg':{'elbow':{'min':None,'max':None,'rom':None},'knee':{'min':90.,'max':150.,'rom':60.}},
            'metricValidity':{'elbow':{'assessment':'withheld','reasons':['invalid_geometry','tracking_interpolated']},
                              'knee':{'assessment':'available','reasons':[]}},'serverWarnings':[],
            'validity':{'reasons':['invalid_geometry','tracking_interpolated']}}]}
        contract=m.scoring_contract(report)
        self.assertEqual(contract[0]['metricValidity']['elbow']['assessment'],'withheld')
        self.assertEqual(len(contract[0]['metricNullPaths']),3)
        changed=copy.deepcopy(report);changed['reps'][0]['anglesDeg']['elbow']['min']=0
        self.assertNotEqual(m.scoring_contract(changed),contract)
        changed=copy.deepcopy(report);changed['reps'][0]['metricValidity']['elbow']['assessment']='available'
        self.assertNotEqual(m.scoring_contract(changed),contract)

    def test_nonfinite_observation_remains_explicit_not_clamped_or_zeroed(self):
        self.assertEqual(m.observed_numbers([1.2,float('nan'),float('inf'),-.1]),[1.2,{'nonfiniteRawValue':'nan'},{'nonfiniteRawValue':'inf'},-.1])


if __name__=='__main__':unittest.main()
