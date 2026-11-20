"""No remote calls/GPU/media: new wrapper uses pinned analysis exactly once."""
import builtins
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/deep_analysis'))
import native_deep_inline_l4 as m
import inline_result_transport as t


def payload():return {'plan':{'publicSourceMounts':m.source_inventory()}}


class NativeInlinePackageTests(unittest.TestCase):
    def test_original_approved_analysis_script_remains_byte_identical(self):
        self.assertEqual(t.digest(Path(m.analysis.__file__).read_bytes()),m.OLD_SCRIPT_SHA)

    def test_model_function_called_once_then_many_chunks_reassemble(self):
        data=b'public_fixture'*20000
        with patch.object(m.analysis,'gpu_once',return_value={'returnCode':0,'archive':data,'remoteTempCleanupOnReturn':True}) as run:
            rows=list(m.gpu_stream(payload()))
        run.assert_called_once();self.assertGreater(len(rows),3)
        with tempfile.TemporaryDirectory() as directory:
            receipt=t.collect_result(iter(rows),Path(directory))
            self.assertEqual(receipt['sha256'],t.digest(data));self.assertEqual(receipt['diagnostics']['analysisInvocations'],1)

    def test_changed_source_rejects_before_any_analysis(self):
        value=payload();value['plan']['publicSourceMounts'][1]['sha256']='0'*64
        with patch.object(m.analysis,'gpu_once') as run:
            with self.assertRaisesRegex(ValueError,'source hash'):list(m.gpu_stream(value))
        run.assert_not_called()

    def test_analysis_exception_never_retries_and_keeps_part(self):
        with tempfile.TemporaryDirectory() as directory,patch.object(m.analysis,'gpu_once',side_effect=RuntimeError('synthetic failure')) as run:
            out=Path(directory)
            with self.assertRaises(RuntimeError):t.collect_result(m.gpu_stream(payload()),out)
            self.assertTrue((out/'artifact.incomplete.part').exists());self.assertFalse((out/'completion.json').exists())
            run.assert_called_once()

    def test_actual_local_SDK_source_mounts_are_exact_three_files(self):
        import modal
        _,call,image=m.definition(modal,modal.Volume.from_name('bpt-gvhmr',create_if_missing=False))
        files=m.local_sdk_mount_inventory(call,image)
        self.assertEqual(len(files),3)
        self.assertEqual({x['localFileName'] for x in files},set(m.PUBLIC_FILES))
        self.assertEqual({x['remotePath'] for x in files},{'/root/'+x for x in m.PUBLIC_FILES})
        self.assertFalse(call._get_source_info().is_serialized())

    def test_failed_zero_or_unverified_archive_never_forensically_promoted(self):
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory)
            self.assertEqual(m.inspect_failed_archive(out)['status'],'no_failed_archive_available')
            (out/'artifact.incomplete.part').write_bytes(b'notzip')
            (out/'failure.json').write_text(json.dumps({'declaredReturnCode':0,'verifiedEndSeen':True}))
            self.assertEqual(m.inspect_failed_archive(out)['status'],'unverified_or_transport_partial_no_extraction')
            (out/'failure.json').write_text(json.dumps({'declaredReturnCode':1,'verifiedEndSeen':False}))
            self.assertEqual(m.inspect_failed_archive(out)['status'],'unverified_or_transport_partial_no_extraction')

    def test_nonzero_complete_transport_exposes_only_bounded_forensic_logs(self):
        content=io.BytesIO()
        with zipfile.ZipFile(content,'w') as archive:
            archive.writestr('run.log','synthetic failure diagnostic')
            archive.writestr('current_error.json','{"errorType":"Synthetic"}')
            archive.writestr('worker_report.json','{"must_not_be_promoted":true}')
            archive.writestr('../escape.log','ignored')
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory)
            with self.assertRaises(ValueError):t.collect_result(t.emit_result({'archive':content.getvalue(),'returnCode':-9}),out)
            result=m.inspect_failed_archive(out)
            self.assertFalse(result['reportReady']);self.assertEqual(result['analysisReturnCode'],-9)
            folder=out/'failed-analysis-log-excerpts-private'
            self.assertEqual({x.name for x in folder.iterdir()},{'run.log','current_error.json'})
            self.assertFalse((out/'artifact.complete.bin').exists());self.assertFalse((out/'completion.json').exists())

    def test_plan_keeps_actual_inputs_sources_and_precision_changes_only_transport_guards(self):
        base={'videoSha256':'a'*64,'serviceReadyManifestCanonicalSha256':'b'*64,'currentSourceCommit':'8e',
              'executionScriptSha256':m.OLD_SCRIPT_SHA,'resources':{'timeoutSeconds':900,'startupTimeoutSeconds':120},
              'precision':'production_runner_default_fp32_half_false','externalBeta':None}
        with patch.object(m.analysis,'prepare',return_value=(base,{},{})):
            result,_,_=m.prepare(ROOT,'unused','unused','a'*64,'b'*64,'c'*40)
        self.assertEqual(result['resources'],{'timeoutSeconds':600,'startupTimeoutSeconds':90})
        self.assertIsNone(result['externalBeta']);self.assertEqual(result['precision'],'production_runner_default_fp32_half_false')
        self.assertEqual(result['approvedAnalysisScriptSha256'],m.OLD_SCRIPT_SHA)
        self.assertEqual(result['maximumCombinedPriorAndNewFunctionPlusStartupSeconds'],876)

    def test_receipts_persist_before_SDK_even_when_preflight_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory)/'out';spec={'videoSha256':'a'*64,'serviceReadyManifestCanonicalSha256':'b'*64}
            args=['tool','--root',str(ROOT),'--package','unused','--video','unused','--expected-video-sha','a'*64,'--expected-service-manifest-sha','b'*64,'--capture-source-commit','c'*40,'--output-dir',str(out),'--execute','--approved-plan-sha',t.digest(t.canonical(spec))]
            original=builtins.__import__
            def guard(name,*a,**k):
                if name=='modal':
                    self.assertTrue((out/'run_plan.json').exists());self.assertTrue((out/'attempt.json').exists())
                    raise ImportError('synthetic SDK failure')
                return original(name,*a,**k)
            with patch.object(m,'prepare',return_value=(spec,{},{})),patch.object(sys,'argv',args),patch.dict(os.environ,{'BPT_NATIVE_INLINE_TRANSFER_APPROVED':'a'*64},clear=True),patch('builtins.__import__',side_effect=guard):self.assertEqual(m.main(),2)
            self.assertFalse(json.loads((out/'execution-failure.json').read_text())['reportReady'])
            self.assertFalse((out/'completion.json').exists())

    def test_new_plan_authorization_required_before_any_output(self):
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory)/'never';spec={'videoSha256':'a'*64}
            args=['tool','--root',str(ROOT),'--package','unused','--video','unused','--expected-video-sha','a'*64,'--expected-service-manifest-sha','b'*64,'--capture-source-commit','c'*40,'--output-dir',str(out),'--execute','--approved-plan-sha','old_plan']
            with patch.object(m,'prepare',return_value=(spec,{},{})),patch.object(sys,'argv',args),patch.dict(os.environ,{},clear=True):
                with self.assertRaises(ValueError):m.main()
            self.assertFalse(out.exists())


if __name__=='__main__':unittest.main()
