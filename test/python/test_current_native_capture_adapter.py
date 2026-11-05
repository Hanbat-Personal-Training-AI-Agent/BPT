"""Synthetic binding-only fixtures; no anatomical/accuracy or device-run claim."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('current_adapter',ROOT/'scripts/deep_analysis/native_capture_adapter.py')
a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)
spec=importlib.util.spec_from_file_location('existing_terminal_fixtures',ROOT/'scripts/terminal_evidence/tests/test_replay.py')
f=importlib.util.module_from_spec(spec);spec.loader.exec_module(f)


def fixture(root, mutation=None):
    rows=f.capture();rows[0]['provenance']='ios_video_as_camera_pipeline';rows[1]['exercise']='barbellRow'
    for row in rows:
        if row['type']=='terminal_frame':row['source_kind']='video_frame'
    rows=[dict(row,sequence=i) for i,row in enumerate(rows)]
    native={'schemaVersion':1,'sessionId':'synthetic_binding_only','timebase':'video_ms','reps':[
        {'repIndex':1,'startMs':0,'endMs':66,'side':'left','onDeviceWarnings':[]}]}
    recording={'videoPath':'/var/mobile/Containers/Data/Application/SYNTHETIC/Documents/workout_videos/example.mp4',
        'durationMs':600,'sourceDurationMs':600,'durationDeltaMsDescriptiveOnly':0,'width':640,'height':480,
        'manifest':native,'uploaded':False,'queuePersisted':False}
    callback={'scope':'actual_native_onSetEnd_before_test_verdict','hostAttemptId':'terminal_synthetic',
        'exerciseId':'barbell-row','sourceDurationMs':600,'recording':True,
        'actualSetEnd':{'videoLocalPath':recording['videoPath'],'deepAnalysis':copy.deepcopy(native)}}
    success={'scope':'actual_native_existing_video_terminal_candidate_capture','synthetic_input':False,
        'hostAttemptId':'terminal_synthetic','exerciseId':'barbell-row','new_camera_recording':False,
        'new_native_video_as_camera_recording':True,'recording':recording,'uploaded':False,
        'native_counter_unchanged_by_test':True,'DartNetworkAttempts':0,'realPreferencesBackendUsed':False,
        'realRecordWrites':0,'TTSRequested':False,'flutterErrorCount':0,'terminalFileName':'synthetic.jsonl',
        'records':len(rows),'frameRows':18,'repRows':1,'footer':copy.deepcopy(rows[-1])}
    ops={'exerciseId':'barbell-row','recording':True,'sourceDurationMs':600,'terminalFileName':'synthetic.jsonl',
        'rows':len(rows),'footer':copy.deepcopy(rows[-1]),'DartNetworkAttempts':0,'flutterErrors':0,'pendingTestExceptionType':None}
    if mutation:mutation(success,callback,ops,rows)
    provenance={'expectedHostAttemptId':'terminal_synthetic'}
    for key,value in [('nativeSetEnd',callback),('operational',ops),('terminal',rows)]:
        p=root/(key+'.json')
        p.write_text(('\n'.join(json.dumps(row) for row in value)+'\n') if key=='terminal' else json.dumps(value))
        provenance[key]={'path':p,'sha256':a.sha(p)}
    p=root/'success.json';p.write_text(json.dumps(success))
    return p,provenance,native


class CurrentAdapterTests(unittest.TestCase):
    def test_official_context_only_preserves_original_native_callback_and_observations(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);p,provenance,native=fixture(root);before=p.read_bytes()
            result=a.adapt(p,a.sha(p),ROOT/'server/calibration_modal',root/'package',provenance=provenance)
            service=json.loads((root/'package/reps.json').read_text())
            original=json.loads((root/'package/native-manifest-original.json').read_text())
            self.assertEqual(original,native);self.assertNotIn('exerciseId',original)
            self.assertEqual(service,{**native,'exerciseId':'barbell-row'})
            self.assertEqual(result['uiContextAddedFields'],['exerciseId'])
            self.assertNotEqual(result['originalNativeManifestCanonicalSha256'],result['serviceReadyManifestCanonicalSha256'])
            self.assertFalse(result['videoByteIdentityVerified']);self.assertFalse(result['remoteTransportAllowed'])
            self.assertEqual(p.read_bytes(),before)

    def test_mixed_host_callback_observations_and_runtime_failures_reject(self):
        mutations=[
            lambda s,c,o,r:c.update(hostAttemptId='terminal_other'),
            lambda s,c,o,r:c['actualSetEnd']['deepAnalysis']['reps'][0].update(endMs=67),
            lambda s,c,o,r:c['actualSetEnd'].update(videoLocalPath='/other.mp4'),
            lambda s,c,o,r:o.update(DartNetworkAttempts=1),
            lambda s,c,o,r:s.update(realRecordWrites=1),
            lambda s,c,o,r:r[1].update(exercise='pushUp'),
            lambda s,c,o,r:r[0].update(provenance='synthetic_test'),
            lambda s,c,o,r:r[2].update(source_kind='camera_capture_index'),
            lambda s,c,o,r:s['recording'].update(sourceDurationMs=601),
            lambda s,c,o,r:s.update(repRows=True),
            lambda s,c,o,r:s['recording']['manifest'].update(exerciseId='squat'),
            lambda s,c,o,r:r[-1].update(flush_complete=False),
        ]
        for index,mutation in enumerate(mutations):
            with self.subTest(index=index),tempfile.TemporaryDirectory() as directory:
                p,provenance,_=fixture(Path(directory),mutation)
                with self.assertRaises((a.IdentityError,ValueError)):a.load_current_receipt(p,a.sha(p),provenance)

    def test_missing_or_modified_terminal_and_unpinned_provenance_reject(self):
        with tempfile.TemporaryDirectory() as directory:
            p,provenance,_=fixture(Path(directory))
            with self.assertRaises(a.IdentityError):a.load_current_receipt(p,a.sha(p),None)
            bad=copy.deepcopy(provenance);bad['nativeSetEnd']['sha256']='0'*64
            with self.assertRaises(a.IdentityError):a.load_current_receipt(p,a.sha(p),bad)
            provenance['terminal']['path'].write_text('{}\n')
            with self.assertRaises(a.IdentityError):a.load_current_receipt(p,a.sha(p),provenance)

    def test_matching_existing_exercise_is_preserved_not_overwritten(self):
        def add(s,c,o,r):
            s['recording']['manifest']['exerciseId']='barbell-row';c['actualSetEnd']['deepAnalysis']['exerciseId']='barbell-row'
        with tempfile.TemporaryDirectory() as directory:
            p,provenance,_=fixture(Path(directory),add)
            source,_,identity=a.load_current_receipt(p,a.sha(p),provenance)
            self.assertEqual(source['manifest'],identity['originalNativeManifest'])
            self.assertEqual(identity['uiContextAddedFields'],[])


if __name__=='__main__':unittest.main()
