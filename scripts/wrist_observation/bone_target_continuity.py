"""Offline numerical mirror of frozen BoneTargetContinuity.swift, no pose inputs."""
import math

class BoneTargetContinuity:
    half_life_seconds=.2
    maximum_gap_seconds=1.
    def __init__(self):self.reset()
    def reset(self):self.shape=None;self.previous_time=None;self.profile_epoch=None
    def update(self,targets,source_time,source,profile_epoch,tracking_valid=True):
        def out(original,filtered,status,alpha=None):return dict(source=source,original_targets=targets,original_shape=original,filtered_shape=filtered,status=status,alpha=alpha)
        def reject(reason,original=None):self.reset();return out(original,None,reason)
        if not tracking_valid:return reject('unsupported_tracking')
        if not profile_epoch:return reject('unsupported_profile_epoch')
        if source_time is None or not math.isfinite(source_time) or source_time<0:return reject('unsupported_source_time')
        if not targets or any(not math.isfinite(v) or v<=0 for v in targets.values()):return reject('unsupported_target')
        total=sum(targets[k] for k in sorted(targets))
        if not math.isfinite(total) or total<=0:return reject('unsupported_target')
        original={k:v/total for k,v in targets.items()}
        if any(not math.isfinite(v) or v<=0 for v in original.values()):return reject('unsupported_target')
        if self.profile_epoch is not None and self.profile_epoch!=profile_epoch:reason='reset_profile_epoch'
        elif self.shape is None:reason='initialized'
        elif self.shape.keys()!=original.keys():reason='reset_target_keys'
        else:
            dt=source_time-self.previous_time
            if dt<=0:return reject('unsupported_nonmonotonic_time',original)
            if dt>self.maximum_gap_seconds:reason='reset_long_gap'
            else:
                alpha=-math.expm1(-math.log(2)*dt/self.half_life_seconds)
                nxt={k:self.shape[k]+(v-self.shape[k])*alpha for k,v in original.items()}
                s=sum(nxt[k] for k in sorted(nxt));nxt={k:v/s for k,v in nxt.items()}
                self.shape=nxt;self.previous_time=source_time;self.profile_epoch=profile_epoch
                return out(original,nxt,'filtered',alpha)
        self.shape=original;self.previous_time=source_time;self.profile_epoch=profile_epoch
        return out(original,original,reason,1.)
