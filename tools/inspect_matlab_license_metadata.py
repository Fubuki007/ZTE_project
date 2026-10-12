#!/usr/bin/env python3
"""Report product validity metadata only, never license signatures or keys."""
from pathlib import Path

for path in Path('/home/jzm123/MATLAB/R2022b/licenses').glob('*.lic'):
    for line in path.read_text(errors='replace').splitlines():
        fields = line.split()
        if len(fields) > 5 and fields[0] in ('INCREMENT', 'FEATURE') and fields[1] == 'MATLAB':
            print('MATLAB license metadata:', 'version=' + fields[3],
                  'expiry=' + fields[4], 'count=' + fields[5])
