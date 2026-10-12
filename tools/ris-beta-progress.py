#!/usr/bin/env python3
"""Count beta-sweep checkpoints without starting MATLAB."""
import argparse
from pathlib import Path
import runpy

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('sample_dir', type=Path)
parser.add_argument('--mc', type=int, default=50)
parser.add_argument('--snr-count', type=int, default=7)
parser.add_argument('--beta-count', type=int, default=3)
args = parser.parse_args()
completion = runpy.run_path(str(Path(__file__).with_name('ris-sic-progress.py')))['completion']
cells = 4 * args.snr_count * args.beta_count
saved = complete = 0
for path in sorted(args.sample_dir.glob('mc_[0-9][0-9][0-9][0-9][0-9].mat')):
    done, total = completion(path)
    if total != cells:
        raise ValueError('Unexpected checkpoint shape: ' + str(path))
    saved += done
    complete += done == cells
print(f'Saved cases: {saved}/{cells*args.mc}; complete MC: {complete}/{args.mc}')
