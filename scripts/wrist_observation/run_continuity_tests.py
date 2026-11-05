"""Compile/run the isolated Swift shape-filter contract tests, no app or model."""
import fcntl
from pathlib import Path
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[2]
if __name__=='__main__':
    with tempfile.TemporaryDirectory(prefix='bpt-bone-continuity-') as tmp,open('/tmp/bpt-heavy.lock','a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        scratch=Path(tmp);(scratch/'main.swift').write_bytes(Path(__file__).with_name('continuity_tests.swift').read_bytes())
        subprocess.run(['swiftc','-O',str(Path(__file__).with_name('BoneTargetContinuity.swift')),str(ROOT/'ios/Runner/NativePose/PosePipeline/BoneLengthConstraint.swift'),str(scratch/'main.swift'),'-o',str(scratch/'tests')],check=True)
        subprocess.run([str(scratch/'tests')],check=True)
