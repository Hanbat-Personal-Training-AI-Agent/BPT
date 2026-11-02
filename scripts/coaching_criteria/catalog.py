"""Versioned metric identities; no target bounds or default coaching thresholds."""
from dataclasses import asdict, dataclass
import hashlib
import json

@dataclass(frozen=True)
class MetricSpec:
    metricId: str
    version: str
    unit: str
    coordinate: str
    definition: str
    exercises: tuple[str, ...]

    def contract(self):
        result = asdict(self)
        result['exercises'] = list(self.exercises)
        result['definitionHash'] = hashlib.sha256(json.dumps(result, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
        return result

CAMERA = 'XS_H36M17_model_space_body_relative'
GRAVITY = 'source_synchronized_up_required'
EXERCISES = ('pushup', 'squat', 'barbell-row')
CATALOG_VERSION = 'bpt.coaching-metrics.v1'
CATALOG = {}
for side, hip, knee, ankle, shoulder, elbow, wrist in [('right',1,2,3,14,15,16),('left',4,5,6,11,12,13)]:
    for name, triple, exercises in [
        ('KneeDeg',(hip,knee,ankle),EXERCISES),
        ('HipDeg',(8,hip,knee),EXERCISES),
        ('ElbowDeg',(shoulder,elbow,wrist),('pushup','barbell-row')),
        ('UpperArmDeg',(shoulder,elbow),('pushup',))]:
        definition = (f'interior_angle_deg_h36m17_{triple}' if name != 'UpperArmDeg' else
                      f'angle_of_{side}_upper_arm_projected_into_body_frontal_plane_from_caudal_trunk_axis; not anatomical shoulder elevation')
        spec = MetricSpec(side+name,'1','degrees',CAMERA,definition,exercises)
        CATALOG[spec.metricId] = spec
spec = MetricSpec('trunkInclineDeg','1','degrees',GRAVITY,'angle_pelvis0_to_thorax8_vs_verified_synchronized_source_gravity; not lumbar curvature',EXERCISES)
CATALOG[spec.metricId] = spec

for name, unit, definition, exercises in [
    ('cameraTorsoSignedDeg','degrees','FormGeometry.signedTorsoAngle3D pelvis0→thorax8 vs camera up (0,-1,0), hip-defined forward signed; not verified gravity or lumbar angle',EXERCISES),
    ('cameraHipLineDeviationRatio','dimensionless_ratio','FormGeometry.signedHipDeviation3D hip0 vs thorax8→ankleMid(3,6), signed camera-up projection / line length; not floor contact',('pushup',))]:
    spec=MetricSpec(name,'1',unit,'XS_H36M17_camera_reference_no_verified_ground',definition,exercises)
    CATALOG[name]=spec
