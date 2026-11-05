# Service readiness and operator request guards — 2026-11-04

This audit used review source `9cfe92b4f4f5bf1da2cf7254368d337d5b70e090`. It did not contact a phone, launch a UI, send credentials, upload data, start inference, deploy, or change app/server defaults.

## Current read-only evidence

Sanitized timestamped receipts are stored at `~/bpt-data/service-readiness-20261104/evidence.json`, with a companion `READINESS.md`. At 2026-11-04 13:39 UTC:

- Configured Spring `http://151.145.79.106:8080/api/v1/exercises` returned HTTP 200 and a JSON array with five entries. This public HTTP route does not prove TLS, database health, authentication, or the prepared release's deployment.
- The configured Modal and R2 hosts resolved and passed certificate-verified TLS 1.3. Unauthenticated GETs to the calibration/deep job routes returned JSON 401. No existing job was read.
- Modal `/health` and `/openapi.json` returned 404; the source disables OpenAPI. These are not dependency health checks.
- The unsigned R2 root HEAD returned 400. TLS and this response do not establish bucket/object access or presigned PUT/GET correctness.
- `modal app history bpt-calibration --json` still reports v18, October 26 18:42:49 KST, tag `panel-0b18bf1-20261026`, dirty commit metadata `0b18bf1*`. This does not prove the current review source is deployed.

The known Spring HTTPS/admin gap from [November 3](spring_release_readiness_20261103.md) remains: reviewed deployment material specifies no usable HTTPS hostname, service unit, active JAR path, certificate/proxy configuration, or established admin channel. No new speculative probing was performed.

## Operator harness repair

The calibration E2E harness previously sent partial-upload URLs before checking their storage allowlist. Both partial and final batches now validate the entire file list, PUT methods, upload identifier, exact storage hosts, HTTPS/443 and absence of user information/fragments before the first PUT in that batch. An invalid later target cannot follow an earlier valid upload. API base validation happens before reading the token or capture bundle. Existing redirect refusal remains. CLI exceptions expose only their type. Job logs now whitelist bounded status/progress values and result presence; arbitrary job errors, extra fields and result text are never printed.

The deep authenticated harness previously hardcoded a plaintext Spring login URL. It now requires `--spring-api` with an explicitly supplied HTTPS base, validates it before reading credentials/videos or creating output, keeps certificate verification enabled, and refuses redirects. HTTPS port 443 is the current operator contract; a future documented nondefault TLS endpoint needs a reviewed change. The operator must supply an approved real hostname; this repair does not discover or invent one. Its signed upload targets also validate as a complete batch before any PUT. Modal/R2 constants and application runtime/defaults are unchanged.

These commands remain mutating E2E tools; they were not run. A new `--spring-api` argument is required for future authorized deep E2E runs. Existing local HTTP test harnesses are unchanged.

Validation: 31 focused fake-transport tests passed, including invalid last target in partial/final batches, invalid base before credential/file/network access, URL restrictions, redirect refusal, and captured stdout containing no signed URL/JWT/error/result/extra-field text. The full server plus deep-analysis suite passed 242 tests with 3 existing skips under `/opt/homebrew/Caskroom/miniconda/base/envs/bpt-eval/bin/python` (Python 3.12). An earlier attempt under base Python 3.13 lacked `moto`/`trimesh`; using the existing evaluation environment resolved those dependency limits. No dependencies were installed. Python compilation and `git diff --check` passed.

Authenticated acceptance still requires a verified Spring TLS endpoint and legitimate current access token. Existing completed same-owner jobs can then support GET-only API/report/storage checks; queued/running GETs can change watchdog state. A fresh upload/worker full flow and deployment remain separate authorization steps. Public reachability and local request-guard tests do not close these checks.
