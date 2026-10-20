import numpy as np

from pose_feedback.geometry.pose3d_constraints import Pose3DConstraints


def test_gate_only_preserves_input_but_keeps_bone_quality_rejection():
    # Unequal long chains deliberately disagree with the default length prior.
    p = np.array([
        [0, 0, 0], [.08, .02, 0], [.10, .25, .01], [.12, .48, 0],
        [-.08, .02, 0], [-.10, .25, .01], [-.12, .48, 0],
        [0, -.2, 0], [0, -.4, 0], [0, -.45, 0], [0, -.52, 0],
        [-.20, -.36, 0], [-.35, -.15, 0], [-.45, .05, 0],
        [.20, -.36, 0], [.35, -.15, 0], [.45, .05, 0],
    ])
    options = dict(angle_limits=(), knee_clamp_deg=None, bad_bone_fraction=.01)
    gate = Pose3DConstraints(**options)
    regular = Pose3DConstraints(**options)
    corrected, prior_report = regular.apply(p)
    preserved, report = gate.apply(p, project_bone_lengths=False)
    np.testing.assert_array_equal(preserved, p)
    assert not np.allclose(corrected, p)
    assert report["bone_max_correction"] == prior_report["bone_max_correction"]
    assert report["bone_source"] == prior_report["bone_source"] == "prior"
    assert report["invalid_joints"] == list(range(17))
    assert report["bad"]
    assert gate.history.keys() == regular.history.keys()
    for edge in gate.history:
        assert gate.history[edge] == regular.history[edge]
