"""call_failure maps a fit_body call's poll outcome; modal.FunctionCall is faked (no network)."""
import modal
import pytest

import modal_app


@pytest.mark.parametrize("outcome, expected", [
    (TimeoutError(), None),  # modal 1.6 raises the builtin TimeoutError while queued or running
    (modal.exception.OutputExpiredError("old"), None),  # the deadline handles it
    (modal.exception.FunctionTimeoutError("15 min"), "timeout"),
    (RuntimeError("container died"), "internal_error"),
    (None, None),  # finished normally: the worker wrote done itself
])
def test_call_failure(monkeypatch, outcome, expected):
    class Call:
        def get(self, timeout):
            assert timeout == 0
            if outcome:
                raise outcome

    monkeypatch.setattr(modal.FunctionCall, "from_id", staticmethod(lambda call_id: Call()))
    assert modal_app.call_failure("fc-1") == expected
