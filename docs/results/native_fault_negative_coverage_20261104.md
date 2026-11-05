# Native fault negative coverage closure: 2026-11-04

All **20 old rule IDs now have supported positive and supported negative fixtures** through the unchanged strict exporter. The four new fixtures were emitted by the actual Swift tracker on fully observed neutral synthetic poses. All 74 native false conditions exported as `no_warning`; 34 unavailable/not-called opportunities stayed withheld. No warnings were created by these neutral fixtures.

This closes the eight explicit negative-fixture gaps recorded in [the frozen real-run report](native_fault_export_20261104.md): hand position, row short pull/shrug/standing up, and squat heel rise/hips first/knee valgus/lean drift. It tests execution/evidence completeness; it does not establish expert correctness or false-negative rates.

## Per-rule coverage

Positive counts are the previously verified actual-tracker fixtures. Added negatives use the new native default-threshold neutral fixtures.

| Rule | Supported positive | Prior negative | Added negative | Total negative |
| --- | --- | --- | --- | --- |

| pushup_depth_fade | 3 | 3 | 3 | 6 |

| pushup_hand_position | 1 | 0 | 1 | 1 |

| pushup_head_drop | 4 | 7 | 4 | 11 |

| pushup_head_up | 4 | 7 | 4 | 11 |

| pushup_hip_pike | 4 | 8 | 4 | 12 |

| pushup_hip_sag | 8 | 4 | 4 | 8 |

| pushup_no_lockout | 6 | 2 | 4 | 6 |

| pushup_shallow | 6 | 1 | 3 | 4 |

| row_head_up | 1 | 3 | 4 | 7 |

| row_short_pull | 3 | 0 | 3 | 3 |

| row_shrug | 8 | 0 | 4 | 4 |

| row_standing_up | 3 | 0 | 3 | 3 |

| row_torso_swing | 6 | 1 | 4 | 5 |

| squat_depth_fade | 3 | 3 | 3 | 6 |

| squat_heel_rise | 8 | 0 | 8 | 8 |

| squat_hips_first | 7 | 0 | 4 | 4 |

| squat_knee_valgus | 4 | 0 | 4 | 4 |

| squat_lean_drift | 3 | 0 | 3 | 3 |

| squat_no_lockout | 7 | 1 | 4 | 5 |

| squat_shallow | 3 | 3 | 3 | 6 |


## Validation and provenance

**31 exporter tests and 56 combined exporter/importer/evaluator tests pass.** The added regressions require every actual false rule condition to export a fully checked, full-window negative. A second regression removes a required current observation from a supported negative for each of all 20 rules and requires withholding. Fixture bytes are checked against the committed producer receipts.

Producer test commit: `82136eb9c4443147f05ed19f169c3a3ec6dae856`; runtime base: `260fbd3ade9d0cbfc611f7f77888a0f37664dc01`. Each case has 20 frames and four native repetitions. Numeric rule thresholds use native defaults; test-only baseline/trend windows are one and heel/shrug are explicitly enabled. The producer receipt and exact fixture hashes are stored in [negative fixture provenance](../../test/python/fixtures/native_fault_trace/negative_v1_provenance.json).

## Frozen real-run result preserved

No exporter code, support policy, real trace, original report, task or evidence was changed or rerun. Hash checks preserve all of these inputs. The existing real result remains **3 warning / 66 no-warning / 131 withheld**, with all **200 labels unknown** and no accuracy estimate. The original report retains its historically accurate at-freeze coverage-gap statement; this separate note closes that test gap.

[Machine-readable closure matrix and unchanged artifact hashes](native_fault_negative_coverage_20261104.json).
