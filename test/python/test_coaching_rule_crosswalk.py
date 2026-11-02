"""Read-only source audit consistency, not expert accuracy or runtime posture tests."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
SCRIPT=ROOT/'scripts/audit/coaching_rule_crosswalk.py'
spec=importlib.util.spec_from_file_location('crosswalk',SCRIPT)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)


class CrosswalkTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.audit=m.build();cls.rules={r['key']:r for r in cls.audit['nativePostureRules']}

    def test_pinned_artifact_is_deterministic_and_complete(self):
        self.assertEqual(self.audit,json.loads((ROOT/'docs/results/coaching_rule_crosswalk_20261103.json').read_text()))
        self.assertEqual(set(self.rules),set(m.A));self.assertEqual(len(self.rules),20)
        self.assertTrue(all(not r['expertValidated'] for r in self.rules.values()))

    def test_enabled_measurement_quiet_and_feature_off_are_separate(self):
        pike=self.rules['pushup_hip_pike']
        self.assertTrue(pike['defaultConditionEnabled']);self.assertFalse(pike['defaultDeliveryKeyEnabled']);self.assertEqual(pike['liveOverlayPhase'],'always')
        for key in ('squat_heel_rise','row_shrug'):
            self.assertFalse(self.rules[key]['defaultConditionEnabled']);self.assertTrue(self.rules[key]['defaultDeliveryKeyEnabled']);self.assertFalse(self.rules[key]['current3DMetricAvailable'])
        active=[r for r in self.rules.values() if r['effectiveDefaultPostureDelivery']]
        self.assertEqual(len(active),12);self.assertEqual(sum(r['grade']!='reference' for r in active),7)
        self.assertEqual(sum(r['grade']=='reference' for r in active),5)

    def test_only_conditional_shallow_scalar_mappings_have_matching_native_keys(self):
        deep={r['fault_id']:r for r in self.audit['deepFallback']['rules']}
        pairs=self.audit['conditionalFormulaMappings'];self.assertEqual(len(pairs),2)
        for pair in pairs:
            native=self.rules[pair['native']];server=deep[pair['deep']]
            self.assertEqual(server['device_key'],pair['native'])
            self.assertEqual(float(server['threshold']),native['defaultThresholds']['shallowOverBaselineDegrees'])
            self.assertIn('conditional',native['comparison'])
        self.assertEqual(self.audit['deepFallback']['applicableCounts'],{'pushup':5,'squat':5,'barbell-row':4})

    def test_torso_lumbar_wrist_and_hybrid_contracts_are_not_renamed_into_parity(self):
        self.assertIsNone(self.rules['row_torso_swing']['existingDeepCounterpart'])
        self.assertEqual(self.rules['row_torso_swing']['defaultThresholds']['torsoSwingRangeDegrees'],39.9)
        self.assertFalse(self.rules['squat_hips_first']['liveOverlayFullPredicate'])
        self.assertTrue(self.rules['squat_hips_first']['additional2DDependencies'])
        self.assertIn('lumbar_flexion',self.audit['nonComparable']);self.assertIn('wrist_placement',self.audit['nonComparable'])

    def test_catalog_proposal_is_not_installed_authority_or_annotations(self):
        catalog=self.audit['catalogProposal'];self.assertEqual(catalog['rows'],54)
        self.assertFalse(catalog['ancestorOfAuditedBase']);self.assertFalse(catalog['autoDiscoveryPathPresentAtBase'])
        self.assertTrue(catalog['copyingWouldChangeDefaultRules']);self.assertFalse(any(catalog['frozenPackageCatalogPresent'].values()))

    def test_source_anchors_refer_to_exact_pinned_nonempty_lines(self):
        for rule in self.rules.values():
            for ref in [rule['judgeRef'],rule['aggregationRef'],rule['geometryRef'],*rule['thresholdRefs']]:
                text=m.source(ref['commit'],ref['path']);self.assertTrue(text.splitlines()[ref['line']-1].strip())

    def test_cli_refuses_overwrite_and_non_JSON_even_under_optimized_python(self):
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory)/'audit.json'
            first=subprocess.run([sys.executable,str(SCRIPT),'--output',str(out)],capture_output=True)
            self.assertEqual(first.returncode,0);before=out.read_bytes()
            second=subprocess.run([sys.executable,str(SCRIPT),'--output',str(out)],capture_output=True)
            self.assertNotEqual(second.returncode,0);self.assertEqual(out.read_bytes(),before)
            forbidden=Path(directory)/'fault_catalog.csv'
            attempt=subprocess.run([sys.executable,'-O',str(SCRIPT),'--output',str(forbidden)],capture_output=True)
            self.assertNotEqual(attempt.returncode,0);self.assertFalse(forbidden.exists())


if __name__=='__main__':unittest.main()
