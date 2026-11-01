"""Synthetic math/metadata tests only; no real performance or human labels."""
import copy
import importlib.util
import math
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('mac_geometry',ROOT/'scripts/diagnostics/mac_terminal_geometry.py')
g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)


def inputs():
    report={'exercise':'pushup','motion3d':'existing_model','form_source':'3d','frames':50,'lookahead':5,'cadence':1,
      'reps':[{'rep_index':1,'start_frame':1,'end_frame':3,'side':'left'},
              {'rep_index':2,'start_frame':25,'end_frame':29,'side':'left'}]}
    two={i:{'frame':str(i),'time':str(i/50),'j0_c':'-0.1','j1_c':'1.2'} for i in range(50)}
    three={}
    for i in range(50):
        angle=170 if i==8 else 90
        row={'frame':str(i),'state':'ok','row':'21','filled':'27'}
        for prefix in ('r','c'):
            for joint,point in zip((11,12,13),[(1,0,0),(0,0,0),(math.cos(math.radians(angle)),math.sin(math.radians(angle)),0)]):
                for axis,value in zip('xyz',point):row[f'{prefix}{joint}_{axis}']=str(value)
        three[i]=row
    return report,two,three


class MacGeometryTests(unittest.TestCase):
    def test_fixed15_uses_observed_clock_and_preserves_raw_scores(self):
        report,two,three=inputs();original=copy.deepcopy((report,two,three))
        aggregate,details=g.analyze(report,two,three)
        self.assertEqual(aggregate['completeFutureClosedWindows'],1)
        self.assertEqual(aggregate['windowWithheldReasons'],{'last_or_open_next_rep_unknown':1})
        metric=details[0]['metrics']['raw_elbow']
        self.assertAlmostEqual(metric['differenceDegrees'],80)
        self.assertEqual(metric['earliestExtendedMaximumOffsetFrames'],5)
        self.assertAlmostEqual(metric['earliestExtendedMaximumOffsetSeconds'],0.1)
        self.assertAlmostEqual(details[0]['extraSpanSeconds'],0.3)
        self.assertFalse(aggregate['nativeAssessmentEligible'])
        self.assertFalse(aggregate['constraintInvalidMaskAvailable'])
        self.assertFalse(aggregate['rawSimccScores']['clamped'])
        self.assertEqual(aggregate['rawSimccScores']['outsideZeroOne'],100)
        self.assertEqual((report,two,three),original)

    def test_crossing_next_original_start_never_becomes_shorter_window(self):
        report,two,three=inputs();report['reps'][1]['start_frame']=18
        a,d=g.analyze(report,two,three)
        self.assertEqual(a['completeFutureClosedWindows'],0)
        self.assertEqual(d[0]['withheldReason'],'next_completed_report_start_inside_fixed_window')
        self.assertEqual(a['metrics'],{})

    def test_last_open_unknown_is_withheld_even_with_many_later_frames(self):
        report,two,three=inputs();report['reps']=report['reps'][:1]
        a,d=g.analyze(report,two,three)
        self.assertEqual(d[0]['withheldReason'],'last_or_open_next_rep_unknown')
        self.assertEqual(a['completeFutureClosedWindows'],0)

    def test_one_bad_raw_sample_withholds_entire_metric_not_finite_subset(self):
        report,two,three=inputs();three[8]['r11_x']='nan'
        a,d=g.analyze(report,two,three)
        self.assertIsNone(d[0]['metrics']['raw_elbow']['value'])
        self.assertIn('differenceDegrees',d[0]['metrics']['constrained_elbow'])
        self.assertEqual(a['metrics']['raw_elbow']['geometryWithheldWindows'],1)

    def test_tracking_loss_anywhere_prevents_implicit_flush_assumption(self):
        report,two,three=inputs();three[40]['state']='tracking_lost'
        a,d=g.analyze(report,two,three)
        self.assertEqual(a['completeFutureClosedWindows'],0)
        self.assertTrue(all(x['withheldReason']=='legacy_implicit_flush_provenance_unavailable' for x in d))
        self.assertFalse(a['row21ProvesUnclamped'])

    def test_eof_tail_is_excluded_even_when_row_stays21(self):
        report,two,three=inputs();report['reps'][0].update(start_frame=23,end_frame=31);report['reps'][1].update(start_frame=48,end_frame=49)
        a,d=g.analyze(report,two,three)
        self.assertEqual(d[0]['withheldReason'],'known_eof_flush_tail_in_fixed_window')

    def test_missing_join_or_wrong_configuration_withholds_run(self):
        for variant in ('join','cadence','lookahead','rotation','row'):
            report,two,three=inputs()
            if variant=='join':three.pop(40)
            elif variant=='row':three[40]['row']='22'
            elif variant=='rotation':report['capture_rotation']=90
            else:report[variant]=2
            a,_=g.analyze(report,two,three)
            with self.subTest(variant=variant):self.assertEqual(a['completeFutureClosedWindows'],0)

    def test_malformed_clock_or_2d_fallback_is_rejected(self):
        for variant in ('clock','fallback'):
            report,two,three=inputs()
            if variant=='clock':two[8]['time']=two[7]['time']
            else:report['motion3d']=None
            with self.subTest(variant=variant),self.assertRaises(ValueError):g.analyze(report,two,three)


if __name__=='__main__':unittest.main()
