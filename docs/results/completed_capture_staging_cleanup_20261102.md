# Completed capture staging cleanup — Nov 2, 2026

After completed capture proofs and the corrected worker-report signed artifact were preserved, root authorized deletion of exactly the first six obsolete staging paths under `~/Documents/bpt-handoff/terminal-device-capture-20261102/`:

- `assemble-capture-generation-attempt1`
- `assemble-capture`
- `diagnostic2/assemble`
- `diagnostic2/app_terminal_capture_diagnostic2.app` (never installed)
- `diagnostic3/assemble`
- `actual-report/assemble`

The audit rejected symlinks, held the local heavy-work lock, checked runtime dependencies, retained four distinct App.framework symbol trees and one canonical Flutter SDK symbol tree by exact hash, and verified3656 protected/tested/ready/source/evidence file hashes before and after. Original ten protected apps, actual tested apps, corrected ready artifact, raw captures, videos, receipts, logs and git HEAD/status were unchanged. No phone call was made.

The removed roots totalled1,040,696KiB by `du`. Available space measured18,176,237,568→18,888,876,032bytes, an observed interval delta of712,638,464bytes. APFS clones share blocks; the allocation sum is not physical reclaimed space, and the global interval delta is not exclusively attributable to this operation.

Exact manifests, before/after filesystem measurements, protected hashes, git snapshots and retained-symbol proofs are in `~/Documents/bpt-handoff/terminal-device-capture-20261102/cleanup-first-six-audit/`, especially `result.json`. The two `.dart_tool/flutter_build` caches, current corrected worker-report staging/artifact and all remaining paths were left untouched. Actual worker-report phone rendering, restoration and any remaining narrow cleanup stay pending genuine approved inference output.
