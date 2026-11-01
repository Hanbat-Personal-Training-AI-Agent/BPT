"""No remote calls/GPU/media transfers. Validate executable payload and approval gate."""
import ast
import builtins
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
SCRIPT=ROOT/'scripts/deep_analysis/native_deep_isolated_l4.py'
spec=importlib.util.spec_from_file_location('native_l4',SCRIPT)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)


class L4PackageTests(unittest.TestCase):
    def test_wrong_video_scope_rejected_before_snapshot_or_network(self):
        with tempfile.TemporaryDirectory() as directory:
            d=Path(directory);(d/'verification.json').write_text(json.dumps({'status':'exact_video_and_manifest_verified','copiedVideoSha256':'a'*64,'canonicalNativeManifestSha256':'b'*64}))
            (d/'reps.json').write_text('{}');(d/'video.mp4').write_bytes(b'not_the_authorized_video')
            with self.assertRaises(ValueError):m.prepare(ROOT,d,d/'video.mp4','a'*64,'b'*64,'c'*40)

    def test_remote_changed_video_rejected_before_weight_or_model_access(self):
        payload={'plan':{'videoSha256':'0'*64},'video':b'synthetic_not_real_media','manifest':{}}
        with self.assertRaisesRegex(ValueError,'remote input SHA'):m.gpu_once(payload)

    def test_remote_changed_canonical_manifest_rejected_before_model_access(self):
        video=b'synthetic_not_real_media'
        payload={'plan':{'videoSha256':m.sha(video),'nativeManifestCanonicalSha256':'0'*64},'video':video,'manifest':{'synthetic':True}}
        with self.assertRaisesRegex(ValueError,'pinned manifest SHA'):m.gpu_once(payload)

    def test_installed_modal_definition_and_single_file_mount_without_running_app(self):
        import modal
        # Lazy handles only. No hydrate/info/app.run/remote and no local media provided.
        image=modal.Image.from_id(m.IMAGE)
        volume=modal.Volume.from_name('bpt-gvhmr',create_if_missing=False)
        # Register this file module for local source inspection, not serialization.
        sys.modules['native_l4']=m
        app,call=m.define_modal_call(modal,image,volume)
        source=call._get_source_info()
        mounts=source.get_entrypoint_mount()
        self.assertEqual(source.module_name,'native_deep_isolated_l4')
        self.assertEqual(len(mounts),1)
        self.assertIn('native_deep_isolated_l4',mounts)
        self.assertEqual(Path(source._file).resolve(),SCRIPT.resolve())
        self.assertFalse(source.is_serialized())

    def test_embedded_remote_programs_compile_without_executing_them(self):
        tree=ast.parse(SCRIPT.read_text());programs=[]
        for node in ast.walk(tree):
            if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='code' for t in node.targets):
                if isinstance(node.value,ast.Constant):programs.append(node.value.value)
        self.assertEqual(len(programs),1)
        child=ast.parse(programs[0]);compile(child,'current_remote_child','exec')
        old=[n.value.value for n in ast.walk(child) if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='old' for t in n.targets)]
        self.assertEqual(len(old),1);compile(old[0],'before_metrics_child','exec')
        # Real current source API supports the intended beta=None worker path, no execution.
        sys.path.insert(0,str(ROOT/'server/calibration_modal'))
        import deep_worker,inspect
        self.assertIn('beta',inspect.signature(deep_worker.analyze).parameters)

    def test_unapproved_execution_fails_before_modal_sdk_import_or_output(self):
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory)/'never_created'
            plan={'videoSha256':'a'*64};args=['tool','--root',str(ROOT),'--package','unused','--video','unused','--expected-video-sha','a'*64,'--expected-native-manifest-sha','b'*64,'--capture-source-commit','c'*40,'--output-dir',str(output),'--execute']
            original_import=builtins.__import__
            def guarded(name,*a,**k):
                if name=='modal':raise AssertionError('unapproved code imported remote SDK')
                return original_import(name,*a,**k)
            with patch.object(m,'prepare',return_value=(plan,{},{})),patch.object(sys,'argv',args),patch.dict(os.environ,{},clear=True),patch('builtins.__import__',side_effect=guarded):
                with self.assertRaises(PermissionError):m.main()
            self.assertFalse(output.exists())

    def test_changed_plan_or_wrong_video_approval_fails_closed(self):
        for wrong_flag in ('absent','wrong_hash','changed_plan'):
            with tempfile.TemporaryDirectory() as directory:
                plan={'videoSha256':'a'*64,'sourceSha256':{'synthetic':'a'*64}}
                approval=m.sha(m.canonical(plan)) if wrong_flag!='changed_plan' else '0'*64
                args=['tool','--root',str(ROOT),'--package','unused','--video','unused','--expected-video-sha','a'*64,'--expected-native-manifest-sha','b'*64,'--capture-source-commit','c'*40,'--output-dir',str(Path(directory)/'out'),'--execute','--approved-plan-sha',approval]
                env={} if wrong_flag=='absent' else {'BPT_NATIVE_VIDEO_TRANSFER_APPROVED':'a'*64 if wrong_flag=='changed_plan' else '0'*64}
                with patch.object(m,'prepare',return_value=(plan,{},{})),patch.object(sys,'argv',args),patch.dict(os.environ,env,clear=True):
                    with self.assertRaises(PermissionError):m.main()


if __name__=='__main__':unittest.main()
