"""Operator request guards; fake transport never opens a network connection."""
import importlib.util
from pathlib import Path
import sys
from unittest.mock import patch

import pytest

ROOT = Path(__file__).resolve().parents[3]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


e2e = load('operator_e2e', ROOT / 'server/calibration_modal/e2e.py')
deep = load('operator_deep', ROOT / 'scripts/deep_analysis/verify_authenticated_flow.py')
HOST = 'storage.example'
FILES = {n: b'photo' for n in ['manifest.json', 'view_front.jpg', 'view_rightfront.jpg', 'view_back.jpg', 'view_leftfront.jpg']}


def body(bad=False):
    targets = [{'name': n, 'method': 'PUT', 'url': f'https://{HOST}/{n}?signature=private'} for n in FILES]
    if bad:
        targets[-1]['url'] = 'https://elsewhere.example/photo?signature=private'
    return {'status': 'upload_required', 'uploadId': 'upload-id', 'files': targets}


class Response:
    def __init__(self, status, value):
        self.status_code, self.value = status, value
    def json(self):
        return self.value
    def raise_for_status(self):
        assert self.status_code == 200


class FakeClient:
    def __init__(self, final_bad):
        self.responses = iter([Response(401, {}), Response(200, body(not final_bad)),
                               Response(422, {}), Response(200, body(final_bad))])
        self.puts = []
    def post(self, *args, **kwargs):
        return next(self.responses)
    def put(self, url, **kwargs):
        self.puts.append(url)
        return Response(200, {})


@pytest.mark.parametrize('final_bad,expected_puts', [(False, 0), (True, 4)])
def test_entire_partial_and_final_target_batches_checked_before_put(final_bad, expected_puts):
    fake = FakeClient(final_bad)
    with patch.object(sys, 'argv', ['e2e', '--api', 'https://api.example/v1', '--storage-host', HOST]), \
         patch.dict('os.environ', {'BPT_TOKEN': 'synthetic'}), \
         patch.object(e2e, 'load_bundle', return_value=('session', FILES)), \
         patch.object(e2e.httpx, 'Client', return_value=fake):
        with pytest.raises(ValueError, match='invalid upload targets'):
            e2e.main()
    assert len(fake.puts) == expected_puts
    assert all(url.startswith('https://storage.example/') for url in fake.puts)


@pytest.mark.parametrize('url', ['http://api.example/v1', 'https://user@api.example/v1',
    'https://api.example:444/v1', 'https://api.example/v1?x=1', 'https://api.example/v1#x',
    'https://api.example:bad/v1', 'https://api.example/\n'])
def test_invalid_api_fails_before_credentials_bundle_or_network(url):
    with patch.object(sys, 'argv', ['e2e', '--api', url, '--storage-host', HOST]), \
         patch.dict('os.environ', {}, clear=True), patch.object(e2e, 'load_bundle') as bundle, \
         patch.object(e2e.httpx, 'Client') as client:
        with pytest.raises(SystemExit):
            e2e.main()
    bundle.assert_not_called()
    client.assert_not_called()


@pytest.mark.parametrize('url', ['http://storage.example/a', 'https://storage.example.evil/a',
    'https://user@storage.example/a', 'https://:pw@storage.example/a',
    'https://storage.example:444/a', 'https://storage.example/a#x',
    'https://storage.example:invalid/a', None])
def test_storage_url_fence(url):
    assert not e2e.app_allows_storage(url, [HOST])


def test_valid_https_endpoints_and_signed_urls():
    assert e2e.valid_https('https://api.example/v1', base=True)
    assert e2e.app_allows_storage('https://storage.example/a?signature=private', [HOST])
    assert deep.verified_spring_base('https://spring.example/api/v1/') == 'https://spring.example/api/v1'
    assert deep.signed_url(f'https://{deep.STORAGE_HOST}/a?signature=private')


def test_deep_bad_base_fails_before_local_reads_or_network(tmp_path):
    argv = ['deep', '--spring-api', 'http://spring.example/api/v1', '--video', str(tmp_path/'v'),
            '--credential-file', str(tmp_path/'c'), '--existing-flow', str(tmp_path/'f'),
            '--output', str(tmp_path/'out'), '--session', 's', '--deployment', 'test']
    with patch.object(sys, 'argv', argv), patch.object(deep.Path, 'read_text') as read, \
         patch.object(deep.Path, 'read_bytes') as video, patch.object(deep, 'request') as request:
        with pytest.raises(SystemExit):
            deep.main()
    read.assert_not_called()
    video.assert_not_called()
    request.assert_not_called()
    assert not (tmp_path/'out').exists()


def test_deep_refuses_redirects():
    assert deep.NoRedirect().redirect_request(None, None, 307, '', {}, 'https://elsewhere.example') is None


def test_deep_entire_target_batch_rejected_before_put():
    blobs = {'video.mp4': b'video', 'reps.json': b'{}'}
    targets = [{'name': n, 'method': 'PUT', 'url': f'https://{deep.STORAGE_HOST}/{n}'} for n in blobs]
    targets[-1]['url'] = 'https://elsewhere.example/reps.json'
    with patch.object(deep, 'request') as request:
        with pytest.raises(ValueError, match='unexpected_storage_host'):
            for item in deep.validate_upload_targets(targets, blobs):
                deep.request(item['url'], 'PUT', blobs[item['name']])
    request.assert_not_called()


@pytest.mark.parametrize('url', ['http://spring.example', 'https://user@spring.example',
    'https://spring.example:444', 'https://spring.example?x=1', 'https://spring.example#x'])
def test_deep_rejects_unsafe_spring_base(url):
    with pytest.raises(Exception, match='explicit HTTPS base URL'):
        deep.verified_spring_base(url)


@pytest.mark.parametrize('status,progress', [('failed', 45), ('signed-secret-status', 'query-jwt'),
                                           (['secret'], True), ('done', 101)])
def test_job_log_whitelist(capsys, status, progress):
    secret = 'https://storage.example/object?signature=PRIVATE&jwt=TOKEN'
    job = {'status': status, 'progressRate': progress, 'error': secret,
           'otherField': secret, 'result': {'modelGlbUrl': secret, 'otherField': secret}}
    print(e2e.json.dumps(e2e.job_log_summary(job)))
    logged = capsys.readouterr().out
    assert secret not in logged
    assert 'PRIVATE' not in logged and 'TOKEN' not in logged
    assert 'signed-secret-status' not in logged and 'query-jwt' not in logged
    summary = e2e.json.loads(logged)
    assert set(summary) == {'status', 'progressRate', 'resultPresent'}
    assert summary['status'] in ('queued', 'running', 'done', 'failed', 'unknown')
    assert summary['progressRate'] is None or type(summary['progressRate']) is int


def test_main_failed_job_logs_no_returned_error_result_or_extra_fields(capsys):
    secret = 'https://storage.example/object?signature=PRIVATE&jwt=TOKEN'
    accepted = {'status': 'accepted', 'jobId': 'job-safe'}
    job = {'status': 'failed', 'progressRate': 50, 'error': secret, 'otherField': secret,
           'result': {'modelGlbUrl': secret, 'otherField': secret}}
    class Client:
        def __init__(self):
            self.responses = iter([Response(401, {}), Response(200, body()), Response(422, {}),
                                   Response(200, body()), Response(202, accepted),
                                   Response(202, accepted), Response(200, accepted)])
        def post(self, *args, **kwargs):
            return next(self.responses)
        def put(self, *args, **kwargs):
            return Response(403 if kwargs['headers']['Content-Type'] == 'text/plain' else 200, {})
        def get(self, *args, **kwargs):
            return Response(200, job)
    with patch.object(sys, 'argv', ['e2e', '--api', 'https://api.example/v1', '--storage-host', HOST]), \
         patch.dict('os.environ', {'BPT_TOKEN': 'synthetic'}), \
         patch.object(e2e, 'load_bundle', return_value=('session', FILES)), \
         patch.object(e2e.httpx, 'Client', return_value=Client()):
        with pytest.raises(SystemExit):
            e2e.main()
    logged = capsys.readouterr().out
    assert 'FAIL  job finished' in logged
    assert '"resultPresent": true' in logged
    for forbidden in [secret, 'PRIVATE', 'TOKEN', 'modelGlbUrl', 'otherField']:
        assert forbidden not in logged
