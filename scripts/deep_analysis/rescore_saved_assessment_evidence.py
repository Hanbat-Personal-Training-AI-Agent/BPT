#!/usr/bin/env python3
"""CPU-only re-score of the hash-bound recovered row; never imports a model.

Reproduces the archived deep_rules.csv-only rule environment. Writes private
JSON only. Original runtime metadata is retained; no new runtime is implied.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
ARCHIVED_RULE_SHA = 'ce95348cf2324cbe7818d894e1c18f8d1a9586bdd7f7012b41be96e32f518a32'
EXPECTED = {
    'result.npz': '620022c1f057114be510186db1495e01b0ffaef3ccefaa39eeb07a1c4e7e27ce',
    'worker_report.json': 'f651a10ac6d8415908f3969353266be4175364e18d77a9eafe53ff4c2320c9fa',
    'reps.json': '70a1e8d88b83acb13b9d2d322fa2675625e4060e0346b3d12f2204ed8118ec09',
}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False, allow_nan=False).encode()


def run(out):
    if not __debug__:
        raise RuntimeError('Assertions must remain enabled')
    import numpy as np
    sys.path.insert(0, str(ROOT / 'server/calibration_modal'))
    import deep_metrics
    assert digest(deep_metrics.RULE_PATH) == ARCHIVED_RULE_SHA, 'Archived rule snapshot changed'
    private = Path.home() / 'bpt-data'
    actual = private / 'native-deep-inline-l4-20261103-verified-private'
    inputs = {'result.npz': actual/'result.npz', 'worker_report.json': actual/'worker_report.json',
              'reps.json': private/'native-deep-current-row-20261103-final-private/reps.json'}
    assert {k: digest(p) for k, p in inputs.items()} == EXPECTED
    out = Path(out).expanduser().resolve()
    assert out.is_relative_to(private.resolve()) and not out.exists(), 'Fresh private output required'
    os.umask(0o077)
    out.mkdir(mode=0o700, parents=True)
    original = json.loads(inputs['worker_report.json'].read_bytes())
    manifest = json.loads(inputs['reps.json'].read_bytes())
    # The recovered worker source package had only deep_rules.csv, no team catalog.
    # Explicitly reproduce that provenance; never claim this is current-catalog scoring.
    old_catalog = deep_metrics.CATALOG_PATH
    try:
        deep_metrics.CATALOG_PATH = out/'absent-archived-catalog.csv'
        with np.load(inputs['result.npz'], allow_pickle=False) as data:
            meta = json.loads(str(data['meta']))
            support = np.clip(data['vitpose_coco17'][:, :, 2], 0, 1) * (meta['person_frames']/meta['frames'])
            report = deep_metrics.metrics(data['h36m17_world'], 30, manifest,
                        confidence=support.mean(axis=1), joint_confidence=support,
                        tracked_mask=data['tracked_mask'])
    finally:
        deep_metrics.CATALOG_PATH = old_catalog
    assert {k:v for k,v in report.items() if k != 'assessmentEvidence'} == {k:original[k] for k in report if k != 'assessmentEvidence'}, 'Archived legacy fields changed'
    selected = {**original, 'assessmentEvidence': report['assessmentEvidence']}
    target = out/'rescored-worker-report.json'
    target.write_bytes(canonical(selected))
    rows = [m for r in report['assessmentEvidence']['reps'] for m in r['metrics']]
    proof = {'actualSavedArrays': True, 'noInference': True, 'inputSHA256': EXPECTED,
             'selectedReportSHA256': digest(target), 'legacyFieldsExactEqual': True,
             'archivedRuleSource': report['rules'], 'archivedRuleSHA256': ARCHIVED_RULE_SHA, 'repCount': len(report['reps']),
             'metricCount': len(rows), 'measurementAvailable': sum(m['measurement']['assessment']=='available' for m in rows),
             'postureAvailable': sum(m['postureAssessment']['assessment']=='available' for m in rows),
             'sourceSHA256': {str(p.relative_to(ROOT)): digest(p) for p in [Path(__file__), Path(deep_metrics.__file__), deep_metrics.RULE_PATH]}}
    assert {k:digest(p) for k,p in inputs.items()} == EXPECTED
    (out/'replay-proof.json').write_bytes(canonical(proof))
    print(json.dumps({'privateOutput': str(target), **proof}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', required=True)
    run(parser.parse_args().out)
