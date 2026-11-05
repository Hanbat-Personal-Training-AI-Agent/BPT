"""Validate a rich capture, then replay the exact compiled production candidate. Aggregate output only."""
import argparse
import json
import subprocess
from pathlib import Path
from replay import load, InvalidCapture

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('--engine', type=Path, required=True)
    args=parser.parse_args()
    try:
        epochs,capped,_=load(args.capture)
        if capped: raise InvalidCapture('candidate_capture_capped')
        completed=subprocess.run([str(args.engine.resolve()),str(args.capture.resolve())],capture_output=True,text=True,timeout=30)
        if completed.returncode: raise InvalidCapture('same_code_replay_or_logged_report_parity_failed')
        result=json.loads(completed.stdout)
        incomplete=sum(data['end'] is None or data['end']['incomplete'] for data in epochs.values())
        result['capture_status_counts']={'epochs':len(epochs),'incomplete_epochs':incomplete}
        result['fully_recorded_capture']=incomplete==0
        print(json.dumps(result,ensure_ascii=False,indent=2,allow_nan=False))
    except (InvalidCapture,OSError,ValueError,subprocess.TimeoutExpired) as error:
        parser.exit(2,f'candidate_capture_rejected: {error}\n')
