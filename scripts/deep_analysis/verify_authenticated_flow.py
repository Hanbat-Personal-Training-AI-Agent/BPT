"""Exercise the deployed deep API with an existing, authorized test account.

Credentials are read from a private file and remain in memory. This never creates
an account, bypasses JWT checks, or retries GPU work. Synthetic repetition windows
exercise the transport contract only; a calibration clip is not exercise evidence.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

SPRING = 'http://151.145.79.106:8080/api/v1'
API = 'https://hqbfgym--bpt-calibration-api.modal.run/v1'
STORAGE_HOST = '1de0e5ab10d7233b02491befb246f0ff.r2.cloudflarestorage.com'


def private_json(path, value):
    temporary = path.with_suffix('.tmp')
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    temporary.replace(path)


def request(url, method='GET', payload=None, headers=None):
    req = urllib.request.Request(url, data=payload, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def signed_url(url):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != 'https' or parsed.hostname != STORAGE_HOST:
        raise ValueError('unexpected_storage_host')
    return url


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--video', type=Path, required=True)
    p.add_argument('--credential-file', type=Path, required=True)
    p.add_argument('--existing-flow', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--session', required=True)
    p.add_argument('--deployment', required=True, help='Reviewed deployment tag, for reproducibility')
    p.add_argument('--require-runtime', action='store_true', help='Require scoped worker timing and sampled absolute GPU memory')
    args = p.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,128}', args.session):
        p.error('invalid session identifier')
    args.output.mkdir(parents=True, exist_ok=True)
    os.chmod(args.output, 0o700)
    evidence_path = args.output / 'evidence.json'
    if evidence_path.exists():
        p.error('preserve prior evidence; use a new output directory and the same session to resume')
    data = args.video.read_bytes()
    if not 0 < len(data) <= 32 * 1024 * 1024:
        p.error('video outside upload size contract')
    account = re.search(r'start \(id ([a-z0-9]+)\)', args.existing_flow.read_text()).group(1)
    password = json.loads(args.credential_file.read_text())['DEMO_PW']
    evidence = {'session': args.session, 'source_sha256': hashlib.sha256(data).hexdigest(),
                'deployment': args.deployment,
                'started_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                'source_bytes': len(data), 'purpose': 'authenticated_transport_smoke_synthetic_rep_intervals',
                'exercise_quality_evaluation': False, 'checks': {}, 'polls': []}
    started = time.monotonic()

    def save():
        evidence['elapsed_seconds'] = round(time.monotonic() - started, 3)
        private_json(evidence_path, evidence)

    def check(name, condition):
        evidence['checks'][name] = bool(condition)
        save()
        if not condition:
            raise ValueError('check_failed:' + name)

    try:
        code, raw = request(SPRING + '/auth/login', 'POST', json.dumps({'email': account, 'password': password}).encode(),
                            {'Content-Type': 'application/json'})
        check('existing_account_login_200', code == 200)
        auth = json.loads(raw)
        token = auth['token']
        headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token,
                   'Idempotency-Key': args.session}

        def api(path, method='GET', body=None, authorized=True):
            status, response = request(API + path, method, None if body is None else json.dumps(body).encode(),
                                       headers if authorized else {'Content-Type': 'application/json'})
            return status, json.loads(response)

        # These windows deliberately test serialization, not actual repetition labels.
        m = {'schemaVersion': 1, 'sessionId': args.session, 'exerciseId': 'squat', 'timebase': 'video_ms',
             'testPurpose': 'transport_only_calibration_clip_synthetic_intervals',
             'reps': [{'repIndex': i + 1, 'startMs': i * 4000, 'endMs': (i + 1) * 4000,
                       'side': 'left', 'onDeviceRepIndex': i + 1, 'onDeviceWarnings': [],
                       'onDeviceMetrics2D': {}, 'onDeviceMetrics3D': {}} for i in range(4)]}
        blobs = {'video.mp4': data, 'reps.json': json.dumps(m).encode()}
        types = {'video.mp4': 'video/mp4', 'reps.json': 'application/json'}
        body = {'schemaVersion': 1, 'clientSessionId': args.session,
                'files': [{'name': name, 'contentType': types[name], 'sizeBytes': len(blob)} for name, blob in blobs.items()]}
        code, _ = api('/deep-analysis/uploads', 'POST', body, authorized=False)
        check('prepare_without_auth_rejected_401', code == 401)
        code, prepared = api('/deep-analysis/uploads', 'POST', body)
        check('prepare_200', code == 200)
        if prepared.get('status') == 'accepted':
            job = prepared['jobId']
            evidence['reused_existing_job'] = True
        else:
            check('prepare_requests_upload', prepared.get('status') == 'upload_required')
            for item in prepared['files']:
                name = item['name']
                # The storage request uses no bearer token.
                code, _ = request(signed_url(item['url']), 'PUT', blobs[name], {'Content-Type': types[name]})
                check('storage_put_' + name, code in (200, 204))
            path = '/deep-analysis/uploads/' + prepared['uploadId'] + '/complete'
            code, completed = api(path, 'POST', {'clientSessionId': args.session})
            check('complete_202', code == 202 and completed.get('status') == 'accepted')
            job = completed['jobId']
            code, duplicate = api(path, 'POST', {'clientSessionId': args.session})
            check('duplicate_complete_same_job', code == 202 and duplicate.get('jobId') == job)
        evidence['job_id'] = job
        code, duplicate = api('/deep-analysis/uploads', 'POST', body)
        check('reprepare_same_job', code == 200 and duplicate.get('jobId') == job)
        path = '/deep-analysis/jobs/' + job
        deadline = time.monotonic() + 1000
        last_status = None
        while time.monotonic() < deadline:
            code, status = api(path)
            check('poll_authenticated_200', code == 200)
            state = status.get('status')
            if (state, status.get('progressRate')) != last_status:
                last_status = state, status.get('progressRate')
                evidence['polls'].append({'seconds': round(time.monotonic() - started, 2),
                                          'status': state, 'progress': status.get('progressRate')})
                save()
                print(json.dumps(evidence['polls'][-1]), flush=True)
            if state in ('done', 'failed'):
                if state == 'failed':
                    evidence['worker_error_code'] = status.get('error')
                break
            time.sleep(5)
        check('worker_done', status.get('status') == 'done')
        result = status['result']
        report = result['report']
        evidence['worker_timing'] = result.get('workerTiming')
        evidence['resource_usage'] = report.get('resourceUsage')
        evidence['runtime'] = report.get('runtime')
        evidence['runner_elapsed_seconds'] = report.get('runnerElapsedSeconds')
        evidence['processing_timing_seconds'] = report.get('processingTimingSeconds')
        if args.require_runtime:
            check('scoped_worker_timing_present', isinstance(evidence['worker_timing'], dict)
                  and evidence['worker_timing'].get('seconds', {}).get('total', 0) > 0)
            check('sampled_absolute_gpu_memory_present', isinstance(evidence['resource_usage'], dict)
                  and (evidence['resource_usage'].get('deviceUsedPeakMiB') or 0) > 0)
        check('rep_boundaries_preserved', [(r['startMs'], r['endMs']) for r in report['reps']] ==
              [(r['startMs'], r['endMs']) for r in m['reps']])
        check('validity_contract_present', all('validity' in r for r in report['reps']))
        check('joint_metric_validity_present', all('metricValidity' in r for r in report['reps']))
        check('observed_tracking_mask_retained', all(
            'tracking_mask_missing' not in r['validity']['reasons'] for r in report['reps']))
        evidence['metric_assessments'] = {
            key: {state: sum(r['metricValidity'][key]['assessment'] == state for r in report['reps'])
                  for state in ('available', 'withheld')}
            for key in report['reps'][0]['metricValidity']}
        check('calibration_shape_used', report.get('bodyShape', {}).get('source') == 'calibration')
        code, raw = request(signed_url(result['reportUrl']))
        check('report_signed_get_without_bearer', code == 200 and json.loads(raw) == report)
        evidence['report_sha256'] = hashlib.sha256(raw).hexdigest()
        private_json(args.output / 'report.json', report)
        time.sleep(2)
        code, refreshed = api(path)
        check('signed_urls_refreshed', code == 200 and refreshed['result']['videoUrl'] != result['videoUrl'])
        check('report_stable_on_refresh', refreshed['result']['report'] == report)
        code, video = request(signed_url(refreshed['result']['videoUrl']))
        check('video_signed_get_without_bearer', code == 200 and len(video) > 1000)
        output = args.output / 'overlay.mp4'
        fd = os.open(output, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        with os.fdopen(fd, 'wb') as stream:
            stream.write(video)
        evidence['overlay_sha256'] = hashlib.sha256(video).hexdigest()
        evidence['overlay_bytes'] = len(video)
        code, _ = api(path, authorized=False)
        check('job_without_auth_rejected_401', code == 401)
        code, unavailable = api(path + '/retry', 'POST')
        check('completed_job_not_retried', code == 409 and unavailable.get('error') == 'retry_unavailable')
        evidence['result'] = 'passed'
        save()
        print(json.dumps({'result': 'passed', 'checks': len(evidence['checks']), 'elapsed_seconds': evidence['elapsed_seconds']}))
        return 0
    except Exception as error:
        # Do not print exception URLs, payloads or credentials.
        evidence['result'] = 'failed'
        evidence['error_type'] = type(error).__name__
        save()
        print(json.dumps({'result': 'failed', 'error_type': type(error).__name__,
                          'failed_checks': [k for k, v in evidence['checks'].items() if not v]}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
