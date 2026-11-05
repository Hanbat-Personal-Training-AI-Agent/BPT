# Provisional deep findings: presentation correction

The saved actual row contained ten placeholder symmetry events, all with posture assessment withheld. The report screen nevertheless displayed their legacy corrective title (“양쪽 움직임을 맞춰 봐”) and body as primary timeline advice. This contradicted the typed evidence even though the numeric report remained intact.

Commit `0dd9efa` changes presentation only: matching server events show the measured metric and value, the summary calls them provisional observations, and event bodies/buttons explicitly withhold normal/abnormal posture judgment. Unknown metrics receive neutral wording. Provisional critical severity uses the informational color. Original report numbers, event count, severity, title/body strings and timestamp evidence remain untouched; the user can still seek to each measured interval. Informational timeline entries and partial metric observations remain visible.

Two new regressions first failed on the old screen, including the hash-bound actual report. Final coverage adds unknown-metric/malformed-optional-rules handling; **11 targeted tests passed**, with no analyzer issues. The synthetic test verifies both timeline and detail-button seeks. The actual report still has all ten events and preserves exact JSON. Private source-before/source-after and log hashes are in `~/bpt-data/deep-provisional-findings-20261103-private/proof.json` (matching source hashes). The input report SHA256 remains `1d713aad203739b413575c844c258a7d9e96d882f4bcd8853a70845c26326b67`.

These are host widget tests, not a new model run, independent posture validation or physical-device proof. No upload, model/default change or deployment was performed for this correction.
