#!/usr/bin/env python3
"""Create a diagnostic launcher with an original library, without editing MATLAB.

Only the launcher, main executable and tested library are independent files.
All other installation files are shared read-only by convention. Never run an
installer/updater or savepath against this diagnostic tree.
"""
from pathlib import Path
import hashlib
import shutil

root = Path('/home/jzm123/AAA_ZTEproject/.jobs/matlab_repair/20261010_1037')
installed = Path('/home/jzm123/MATLAB/R2022b')
trial = root / 'original_library_trial'
relative = Path('bin/glnxa64/matlab_startup_plugins/lmgrimpl/libmwlmgrimpl.so')
original = root / 'original_component/clean' / relative
backup = root / 'critical_backup/libmwlmgrimpl.so'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

assert digest(backup) == digest(installed / relative)
assert digest(original) == '4e52640dbf8401b04f13b435becb382100de61c91eef48409da33faaa020c498'
assert not trial.exists(), 'Never overwrite an existing diagnostic tree.'

independent = {Path('bin/matlab'), Path('bin/glnxa64/MATLAB'), relative}
branches = {p for f in independent for p in f.parents if p != Path('.')}

def populate(src, dst, rel=Path('.')):
    dst.mkdir()
    for item in src.iterdir():
        child = rel / item.name
        target = dst / item.name
        if child in branches:
            populate(item, target, child)
        elif child in independent:
            shutil.copy2(original if child == relative else item, target)
        else:
            target.symlink_to(item, target_is_directory=item.is_dir())

populate(installed, trial)
assert digest(trial / relative) == digest(original)
(root / 'trial-candidate.txt').write_text(str(trial) + '\n')
print('TRIAL_PREPARED=' + str(trial))
