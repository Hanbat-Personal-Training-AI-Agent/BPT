"""Freeze all successful engine test requests and complete Python outputs for native parity.
Run from repository root: python -m scripts.coaching_criteria.generate_parity_fixtures [--check]
Synthetic evidence only. No source recordings, model, network or product state.
"""
import copy
import json
from pathlib import Path
import sys
import unittest
from .tests import test_engine


def main():
    original = test_engine.evaluate
    cases = {}
    def capture(request):
        result = original(request)
        case = {'request': copy.deepcopy(request), 'expected': result}
        cases[json.dumps(case, sort_keys=True, allow_nan=False)] = case
        return result
    test_engine.evaluate = capture
    try:
        outcome = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromModule(test_engine))
    finally:
        test_engine.evaluate = original
    if not outcome.wasSuccessful():
        raise SystemExit(1)
    content = json.dumps({'schema': 'bpt.coaching-criteria-parity.v1', 'cases': list(cases.values())}, ensure_ascii=True, indent=2, allow_nan=False) + '\n'
    path = Path(__file__).parent / 'fixtures/parity_v1.json'
    if '--check' in sys.argv:
        if path.read_text() != content:
            raise SystemExit('Parity fixture stale; regenerate and review changes')
    else:
        path.write_text(content)
    print(f'{len(cases)} complete-output synthetic parity cases')

if __name__ == '__main__':
    main()
