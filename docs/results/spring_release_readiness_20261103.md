# Spring release access and TLS readiness — read-only audit

The live Spring address is still `http://151.145.79.106:8080/api/v1`. Its public `/exercises` GET returned JSON200 during this audit. The repository's backend change guide identifies OCI deployment with a 512 MiB Java heap. No service unit name, active JAR path, SSH deployment command, reverse-proxy configuration, certificate path or HTTPS hostname is specified there.

A bounded local search covered the repository backend/deployment files, backend guides, `docs/handoff/security_followup.md`, and the BPT handoff directory. The security handoff explicitly records that the port80 proxy configuration is not in the repository and domain/TLS setup remains pending. The local SSH config contains no BPT/Kori alias or HostName matching the recorded server IP. This audit did not infer access from unrelated host entries, guess an SSH user/key, inspect private key contents or open an SSH connection.

Current previously recorded probes establish only the following:

- `https://hqbfgym--bpt-calibration-api.modal.run/v1/...`: verified TLS, unauthenticated deep-job GET returns401. Existing Modal app metadata reports version18 (October26), not the new source.
- `http://151.145.79.106:8080/api/v1/exercises`: JSON200, usable public HTTP route.
- `https://151.145.79.106:8080/health`: connection error; `https://151.145.79.106/api/v1/exercises`: connection timeout.
- `/health` outside the Spring context returns HTML200 over HTTP; that is not a service/database health contract.

These results do not prove that no TLS endpoint exists elsewhere. They establish that **no usable, verified Spring TLS hostname or authorized server-admin channel was found in the available BPT deployment material**. No additional network probing was performed after that access gap was established.

The security release source and boot JAR are already prepared and tested in [the token-use release candidate](token_use_release_candidate_20261103.md). The final strict JAR is `~/bpt-data/deployment-readiness-20261103-private/token-use-backend-strict.jar`, SHA256 `80c22504934ddf18c80f5fc582033e8324ba9a0032ba1ec5fc9d777a48ddb15f`. No signing secret or database migration is required by that code change.

The concrete remaining deployment inputs are: the established BPT SSH/admin route, actual Spring service unit and active JAR location, and an approved HTTPS hostname with its existing or approved certificate/proxy configuration. Without those facts, a command such as restarting an invented `bpt.service` or installing a guessed Nginx configuration would not be a reviewable deployment procedure. Existing Modal source deployment is separately known (`server/calibration_modal/modal_app.py`) and remains unexecuted pending authorization.

Fresh phone credentials were read only as local metadata: access expired, refresh unexpired, and legacy claim shapes match the migration policy. No JWT/password was sent over HTTP or unverified TLS, no token was refreshed, and the original phone preference hash is unchanged. Existing completed same-owner jobs may be read after a legitimate current access token and verified endpoint are available; queued/running job GETs can trigger the existing timeout watchdog and are not a strict read-only substitute. This audit created no job, upload, GPU warmup, deployment, restart or configuration change.
