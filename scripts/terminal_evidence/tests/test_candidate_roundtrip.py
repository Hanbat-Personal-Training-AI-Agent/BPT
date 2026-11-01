import importlib.util
import json
from pathlib import Path
import subprocess
import sys

import pytest

ROOT=Path(__file__).resolve().parents[3]
MODULE=ROOT/'ios/Runner/NativePose/Evaluators/TerminalObservationCandidate.swift'


@pytest.fixture(scope='module')
def binaries(tmp_path_factory):
    dest=tmp_path_factory.mktemp('candidate-native-replay')
    for target,entry in [('producer',Path(__file__).with_name('make_candidate_fixture.swift')),('replay',ROOT/'scripts/replay_terminal_candidate.swift')]:
        subprocess.run(['swiftc',str(MODULE),str(entry),'-o',str(dest/target)],check=True,capture_output=True,text=True,timeout=60)
    return dest


def run_capture(binaries,tmp_path,mutate=None):
    content=subprocess.check_output([str(binaries/'producer')],text=True)
    rows=[json.loads(line) for line in content.splitlines()]
    if mutate:mutate(rows)
    path=tmp_path/'synthetic.jsonl'
    path.write_text('\n'.join(json.dumps(row,allow_nan=False) for row in rows)+'\n')
    return subprocess.run([sys.executable,str(ROOT/'scripts/terminal_evidence/replay_candidate.py'),str(path),'--engine',str(binaries/'replay')],capture_output=True,text=True,timeout=30)


def test_same_production_module_live_log_and_offline_reports_match(binaries,tmp_path):
    result=run_capture(binaries,tmp_path)
    assert result.returncode==0,result.stderr
    data=json.loads(result.stdout)
    assert data['exact_logged_report_parity'] is True
    assert data['replayed_reports']==4
    assert data['assessment_counts']=={'withheld':3,'relative_terminal_deficit_observed':1}
    assert data['coverage_counts']=={'observed_stable_top_window':4}
    assert 'original' not in data  # aggregate output, no individual source frames/rep identifiers


@pytest.mark.parametrize('field,value',[('assessment','relative_deficit_not_observed'),('referenceCount',999)])
def test_modified_candidate_report_is_rejected(binaries,tmp_path,field,value):
    def mutate(rows):
        row=next(r for r in reversed(rows) if r['type']=='terminal_candidate_report')
        row['payload'][field]=value
    result=run_capture(binaries,tmp_path,mutate)
    assert result.returncode==2
    assert 'parity_failed' in result.stderr


def test_candidate_input_cannot_use_host_clock_as_source_or_fabricate_geometry(binaries,tmp_path):
    for field,value in [('sourceTime',999.),('assessmentAngles',{'elbow':1.})]:
        def mutate(rows):
            row=next(r for r in rows if r['type']=='terminal_candidate_frame')
            row['payload'][field]=value
        result=run_capture(binaries,tmp_path,mutate)
        assert result.returncode==2
        assert 'candidate_' in result.stderr
