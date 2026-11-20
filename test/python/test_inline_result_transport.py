"""Local protocol/admission tests only; public CPU execution is separate opt-in."""
import copy
import importlib.util
import json
from pathlib import Path
import pickle
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
SCRIPT=ROOT/'scripts/deep_analysis/inline_result_transport.py'
spec=importlib.util.spec_from_file_location('inline_transport',SCRIPT)
m=importlib.util.module_from_spec(spec);sys.modules[spec.name]=m;spec.loader.exec_module(m)


def records(code=0):return list(m.emit_result({'archive':b'a'*(m.CHUNK_BYTES+7),'returnCode':code}))


class InlineTransportTests(unittest.TestCase):
    def collect(self,rows):
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory);receipt=m.collect_result(iter(rows),out)
            self.assertEqual((out/'artifact.complete.bin').read_bytes(),b'a'*(m.CHUNK_BYTES+7))
            self.assertFalse((out/'artifact.incomplete.part').exists())
            return receipt

    def rejected(self,rows):
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory)
            with self.assertRaises((ValueError,RuntimeError)):m.collect_result(rows,out)
            self.assertFalse((out/'artifact.complete.bin').exists())
            self.assertFalse((out/'completion.json').exists())
            self.assertTrue((out/'artifact.incomplete.part').exists())
            self.assertEqual(json.loads((out/'failure.json').read_text())['status'],'incomplete_not_consumable')

    def test_complete_multichunk_integrity_and_exact_zero_return_code(self):
        receipt=self.collect(records());self.assertEqual(receipt['chunks'],2);self.assertEqual(receipt['returnCode'],0)

    def test_every_pickled_public_record_below_installed_blob_threshold(self):
        from modal._utils.blob_utils import MAX_OBJECT_SIZE_BYTES
        for row in m.emit_result({'archive':m.public_payload(),'returnCode':0}):
            self.assertLess(len(pickle.dumps(row)),MAX_OBJECT_SIZE_BYTES)
        self.assertGreater(len(pickle.dumps({'archive':m.public_payload(),'returnCode':0})),MAX_OBJECT_SIZE_BYTES)

    def test_missing_header_chunk_end_rejected_without_consumable_file(self):
        for indices in ((0,),(1,),(3,)):
            rows=records()
            for i in reversed(indices):del rows[i]
            with self.subTest(indices=indices):self.rejected(iter(rows))

    def test_duplicate_out_of_order_and_after_end_rejected(self):
        for mutate in (lambda r:r.insert(2,copy.deepcopy(r[1])),lambda r:r.__setitem__(slice(1,3),list(reversed(r[1:3]))),lambda r:r.append(copy.deepcopy(r[1]))):
            rows=records();mutate(rows);self.rejected(iter(rows))

    def test_chunk_and_final_digest_mismatch_rejected(self):
        rows=records();rows[1]['data']=b'b'*m.CHUNK_BYTES;self.rejected(iter(rows))
        rows=records();rows[-1]['sha256']='0'*64;self.rejected(iter(rows))
        rows=records();rows[0]['sha256']=rows[-1]['sha256']='0'*64;self.rejected(iter(rows))

    def test_declared_bounds_types_and_exact_chunk_size(self):
        for key,value in [('bytes',True),('bytes',m.MAX_BYTES+1),('chunks',True),('chunkBytes',1),('returnCode',True),('sha256','z'*64)]:
            rows=records();rows[0][key]=value
            with self.subTest(key=key,value=value):self.rejected(iter(rows))
        rows=records();rows[1]['data']=b'a';rows[1]['sha256']=m.digest(b'a');self.rejected(iter(rows))
        rows=records();rows[1]['index']=False;self.rejected(iter(rows))

    def test_nonzero_analysis_code_never_commits_even_with_valid_transport(self):
        for code in (1,-9):self.rejected(iter(records(code)))
        rows=records();rows[-1]['returnCode']=False;self.rejected(iter(rows))

    def test_exception_before_header_and_midstream_retains_explicit_incomplete(self):
        def before():raise RuntimeError('synthetic connection failure');yield
        def middle():
            yield from records()[:2]
            raise RuntimeError('synthetic connection failure')
        self.rejected(before());self.rejected(middle())

    def test_extra_header_or_unknown_schema_rejected(self):
        rows=records();rows.insert(1,copy.deepcopy(rows[0]));self.rejected(iter(rows))
        rows=records();rows[2]['schema']='unknown';self.rejected(iter(rows))

    def test_output_cannot_overwrite_previous_completion_or_part(self):
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory);m.collect_result(iter(records()),out);original=(out/'artifact.complete.bin').read_bytes()
            with self.assertRaises(ValueError):m.collect_result(iter(records()),out)
            self.assertEqual((out/'artifact.complete.bin').read_bytes(),original)
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory);(out/'artifact.incomplete.part').write_bytes(b'prior_incomplete')
            with self.assertRaises(FileExistsError):m.collect_result(iter(records()),out)
            self.assertEqual((out/'artifact.incomplete.part').read_bytes(),b'prior_incomplete')

    def test_bad_return_shape_rejected_before_any_record(self):
        for result in ({'archive':b'a','returnCode':False},{'archive':bytearray(b'a'),'returnCode':0},{'archive':b'','returnCode':0}):
            with self.assertRaises(ValueError):list(m.emit_result(result))

    def test_installed_sdk_factory_constructs_two_CPU_functions_single_public_source(self):
        import modal
        for mode in ('direct','chunks'):
            _,call=m.definition(modal,mode);source=call._get_source_info()
            self.assertFalse(source.is_serialized());self.assertEqual(Path(source._file).resolve(),SCRIPT)
            self.assertEqual(len(source.get_entrypoint_mount()),1)
        p=m.plan();self.assertEqual(p['maxFunctionCalls'],2);self.assertEqual(p['secrets'],[]);self.assertEqual(p['volumes'],[])

    def test_wrong_approval_prevents_output_creation_and_remote_import(self):
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory)/'absent'
            p=subprocess.run([sys.executable,str(SCRIPT),'--output-dir',str(out),'--execute','--approved-plan-sha','wrong'],capture_output=True)
            self.assertNotEqual(p.returncode,0);self.assertFalse(out.exists())


if __name__=='__main__':unittest.main()
