# Motion/contact experiment: evidence and scope

The original MotionAGFormer work evaluates a learned 2D-to-3D temporal model on Human3.6M and MPI-INF-3DHP. Its official XS configuration uses 27 frames. These facts justify preserving the existing XS window and comparing all post-processors at the same output timestamp; they do not establish reliability under BPT's exercise-specific occlusions. [Original paper](https://arxiv.org/abs/2310.16288), [official implementation](https://github.com/TaatiTeam/MotionAGFormer).

Fit3D supplies synchronized camera views, marker-based motion capture, 25-joint skeletons, repetition intervals, and fitted GHUM/SMPL-X shapes. The official shape annotations incorporate marker, multiview and body-scan evidence. They therefore belong to ground-truth scoring, rather than being silently substituted for an on-device user's calibration. This experiment instead separates existing RGB-derived calibration estimates and causal online length estimates. [Official Fit3D data description](https://fit3d.imar.ro/fit3d).

Single-image body-shape reconstruction remains ambiguous under occlusion, clothing and perspective. A statistical body model can constrain plausible shape but does not make a wrist's location uniquely identifiable from forearm length. Here, bone intervals are soft and uncertainty-dependent; they do not impose a good exercise pose. [SMPLify original paper](https://arxiv.org/abs/1607.08128).

## BPT-specific evidence, not a universal ranking of causes

- The separate C1 audit found a 6–8° input/target torso-direction difference dominated by fitted joint-definition offsets in virtual side-view training. B1 also shows a related torso bias. This is a specific calibration/definition mechanism, not proof that all occlusion errors have that cause.
- Existing matched-crop MM-Fit controls found that a Halpe26 run with poor rep recovery recovered its count when given the COCO crop path, while the converse worsened. Those runs concern particular clips/encodings and demonstrate upstream crop dependence, not a global model ranking.
- The app's XS coordinates depend on crop size and are root-relative. Contact in the camera image is consequently distinct from a fixed root-relative joint. The new state estimator receives an invertible crop-to-image-height conversion and never invents absolute contact depth.
- Camera rotation boundaries previously required explicit temporal-state resets. That implementation issue has a separate tested fix; it must not be attributed to the model's intrinsic depth ambiguity.

The new A–H experiments measure error on clean, corrupted and moving intervals separately. Low 2D confidence is an operational proxy, not a ground-truth occlusion annotation. Synthetic RGB masks test a specific controlled perturbation; they are not equivalent to every natural self-occlusion or to general home-camera validation.
