import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / f'{name}.py')
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m


class AttributionTests(unittest.TestCase):
    def testStrictThresholdBoundaryAndDirectionNoPrivateIdentifiers(self):
        audit, e = load('attribute_gvhmr_boundaries'), load('eval_gvhmr_fit3d')
        def reps(values): return [{'torso_range': v} for v in values]
        rows = [{'exercise': 'barbell_row', 'subject': 'NEVER_EXPORT', 'cam': 'SECRET',
                 'rep_metrics': {'GT': reps([34.9,39.9,44.9,45.0]),
                                 'A': reps([34.9,39.9,44.9,45.0]),
                                 'B': reps([40.0,40.0,39.0,45.0]),
                                 'Bw': reps([34.9,39.9,44.9,45.0])}}]
        out = audit.attribute(rows,e)
        v = out['metrics']['row_torso_swing']['variants']['B']
        self.assertEqual((v['nearTotal'],v['nearAgree']), (3,0))
        self.assertEqual(v['falsePositiveVsAngleThreshold'],2)
        self.assertEqual(v['falseNegativeVsAngleThreshold'],1)
        self.assertEqual(v['baselineCorrectVariantWrong'],3)
        self.assertEqual(out['metrics']['row_torso_swing']['separateWorldUpDiagnostic']['B_to_Bw']['decisionChanged'],3)
        self.assertNotIn('NEVER_EXPORT', str(out)); self.assertNotIn('SECRET', str(out))

    def testBaselineNaNsEmptyCohortAndMisalignment(self):
        audit, e = load('attribute_gvhmr_boundaries'), load('eval_gvhmr_fit3d')
        reps = [{'elbow_min': lo, 'elbow_max': hi} for lo,hi in [(100,170),(100,165),(100,160),(115,155)]]
        row = {'exercise':'pushup','rep_metrics': {'GT':reps,'B':reps}}
        out = audit.attribute([row],e)
        self.assertEqual(out['metrics']['pushup_shallow']['variants']['B']['nearTotal'],1)
        self.assertEqual(out['metrics']['row_torso_swing']['variants']['B']['nearTotal'],0)
        row['rep_metrics']['B'] = reps[:3]
        with self.assertRaises(ValueError): audit.attribute([row],e)

    def testNoLockoutDecomposesReferenceAndCurrentErrors(self):
        audit, e = load('attribute_gvhmr_boundaries'), load('eval_gvhmr_fit3d')
        def reps(maxima): return [{'elbow_min':100,'elbow_max':v} for v in maxima]
        rows = [{'exercise':'pushup','rep_metrics': {'GT':reps([170,165,160,155]),
                                                  'B':reps([170,165,154,155])}}]
        out = audit.attribute(rows,e)['metrics']['pushup_no_lockout']['variants']['B']
        expected = e.decisions(rows,'pushup_no_lockout')['B']
        self.assertEqual((out['nearAgree'],out['nearTotal']),tuple(expected[2:]))
        components = out['disagreementDeficitComponents']
        self.assertEqual(components['runningSetMaxErrorDegrees']['median'],0)
        self.assertEqual(components['currentRepMaxErrorDegrees']['median'],-6)
        self.assertEqual(out['disagreementSignedPredictionErrorDegrees']['median'],6)
