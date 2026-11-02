# Actual worker report host preflight — Nov 2, 2026

A CPU-only Flutter host test parsed the genuine returned worker report through explicit synthetic local job metadata and rendered/expanded the actual first rep in the production DeepAnalysisReport widget. Original report SHA256 is `f651a10ac6d8415908f3969353266be4175364e18d77a9eafe53ff4c2320c9fa`. The report object was unchanged. A video placeholder was used; this does not test the physical phone, native video initialization, authenticated API, seeking, playback, form accuracy or model inference.

The first attempt failed in test infrastructure: `.first` on an empty lazy ExpansionTile finder threw StateError before scrolling through the actual timeline. Its log is preserved separately. The second attempt passed after scrolling to the unique actual first-rep title, retaining real production-widget expansion and error assertions. The corresponding narrow phone-test freeze is `9f6f3ca`, distinct from earlier `6fa9c3d`; no production/native/model change occurred.

Authoritative host proof and source/log hashes: `~/Documents/bpt-handoff/terminal-device-capture-20261102/actual-report/host-preflight-proof.json`. Private logs are `~/bpt-data/terminal-device-capture-20261102/actual-report-device/host-preflight-attempt1.log` and `host-preflight-attempt2.log`. The host test source remains in the handoff actual-report directory. No actual worker bytes or video were committed to Git.

At this checkpoint the fresh phone readiness query returned CoreDevice4016 with no assertable states, before installation or configuration change. Actual phone rendering remains pending changed readiness and the new finder-fixed signed artifact; it must not be inferred from this host PASS.
