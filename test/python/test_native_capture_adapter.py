"""Synthetic contract regressions; actual private input verified separately by CLI."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('native_adapter',ROOT/'scripts/deep_analysis/native_capture_adapter.py')
a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)


def capture():
    return {'scope':'local_native_capture_only','uploaded':False,'queuePersisted':False,'networkAttempts':0,
      'videoPath':'/var/mobile/Containers/Data/Application/SYNTHETIC/Documents/workout_videos/example.mp4',
      'durationMs':1000,'width':720,'height':1280,
      'manifest':{'schemaVersion':1,'sessionId':'synthetic-session','exerciseId':'barbell-row','timebase':'video_ms',
        'reps':[{'repIndex':1,'startMs':100.5,'endMs':900.5,'side':'left','onDeviceWarnings':[],
                 'onDeviceMetrics2D':{'synthetic_metric':1.25},'onDeviceMetrics3D':{'synthetic_metric':2.5}}]}}


def copy_receipt(video):
    suffix='Documents/workout_videos/example.mp4'
    return {'info':{'outcome':'success','arguments':['devicectl','device','copy','from','--source',suffix]},
      'result':{'domain':'appDataContainer','domainIdentifier':'com.bpt.liftdev','source':suffix,'destination':video.as_uri()}}


class NativeAdapterTests(unittest.TestCase):
    def test_actual_production_parser_preserves_every_observation(self):
        source=capture();original=copy.deepcopy(source['manifest'])
        hashes=a.service_validate(source['manifest'],ROOT/'server/calibration_modal')
        self.assertEqual(source['manifest'],original);self.assertEqual(len(hashes),3)
        self.assertEqual(source['manifest']['reps'][0]['onDeviceWarnings'],[])

    def test_missing_native_side_or_warning_is_never_filled(self):
        for field in ('side','onDeviceWarnings'):
            source=capture();source['manifest']['reps'][0].pop(field)
            with self.subTest(field=field),self.assertRaises(Exception):a.service_validate(source['manifest'],ROOT/'server/calibration_modal')

    def test_capture_digest_and_native_duration_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)/'source.json';p.write_text(json.dumps(capture()))
            with self.assertRaises(a.IdentityError):a.load_receipt(p,'0'*64)
            source=capture();source['manifest']['reps'][0]['endMs']=1001;p.write_text(json.dumps(source))
            with self.assertRaises(a.IdentityError):a.load_receipt(p,a.sha(p))

    def test_duplicate_keys_and_wrong_timebase_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)/'source.json'
            p.write_text('{"scope":1,"scope":2}')
            with self.assertRaises(a.IdentityError):a.load_receipt(p,a.sha(p))
            source=capture();source['manifest']['timebase']='source_frames';p.write_text(json.dumps(source))
            with self.assertRaises(a.IdentityError):a.load_receipt(p,a.sha(p))

    def test_no_video_preflight_is_not_claimed_as_model_or_e2e(self):
        with tempfile.TemporaryDirectory() as directory:
            d=Path(directory);p=d/'capture.json';p.write_text(json.dumps(capture()));before=p.read_bytes()
            result=a.adapt(p,a.sha(p),ROOT/'server/calibration_modal',d/'package')
            self.assertFalse(result['videoByteIdentityVerified']);self.assertFalse(result['remoteTransportAllowed'])
            self.assertFalse(result['newInferenceExecuted']);self.assertFalse(result['serviceReportProduced'])
            self.assertEqual(json.loads((d/'package/reps.json').read_text()),capture()['manifest'])
            self.assertEqual(p.read_bytes(),before)
            with self.assertRaises(FileExistsError):a.adapt(p,a.sha(p),ROOT/'server/calibration_modal',d/'package')

    def test_verified_copy_uses_real_file_uri_contract_and_exact_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            d=Path(directory);video=d/'example.mp4';video.write_bytes(b'synthetic_header_only_not_real_media')
            probe=json.dumps({'streams':[{'codec_name':'h264','width':720,'height':1280,'duration':'1.000'}]}).encode()
            with patch.object(a.subprocess,'check_output',return_value=probe):
                value=a.validate_video(capture(),video,a.sha(video),copy_receipt(video))
            self.assertEqual(value['duration'],'1.000')
            receipt=copy_receipt(video);receipt['result']['destination']='https://remote.invalid/example.mp4'
            with self.assertRaises(a.IdentityError):a.validate_video(capture(),video,a.sha(video),receipt)

    def test_wrong_bytes_or_wrong_device_source_reject_before_probe(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)/'example.mp4';p.write_bytes(b'synthetic')
            with self.assertRaises(a.IdentityError):a.validate_video(capture(),p,'0'*64,copy_receipt(p))
            receipt=copy_receipt(p);receipt['info']['arguments'][-1]='Documents/other.mp4'
            with self.assertRaises(a.IdentityError):a.validate_video(capture(),p,a.sha(p),receipt)

    def test_same_shape_different_video_digest_cannot_bind_report(self):
        source=capture();report={'exerciseId':'barbell-row','reps':copy.deepcopy(source['manifest']['reps'])}
        with self.assertRaises(a.IdentityError):a.reject_wrong_report_binding(source,report,'a'*64,'b'*64)
        a.reject_wrong_report_binding(source,report,'a'*64,'a'*64)
        report['reps'][0]['onDeviceMetrics3D']['synthetic_metric']=99
        with self.assertRaises(a.IdentityError):a.reject_wrong_report_binding(source,report,'a'*64,'a'*64)

    def test_separate_squat_report_cannot_be_assigned_to_row(self):
        with self.assertRaises(a.IdentityError):a.reject_wrong_report_binding(capture(),{'exerciseId':'squat','reps':[]},'a'*64,'a'*64)


if __name__=='__main__':unittest.main()
