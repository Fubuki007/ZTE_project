import json
from pathlib import Path
import os
import sys

root=Path(sys.argv[1])
print('STATE='+((root/'state').read_text().strip() if (root/'state').exists() else 'NOT_STARTED'))
if (root/'manifest.json').exists():
    m=json.loads((root/'manifest.json').read_text())
    counts=[sum(1 for _ in (root/'samples').glob(f'snr_{si:02d}_mc_*.json')) for si in range(len(m['snr_db']))]
    print(f'COMPLETE_CASES={sum(counts)}/{len(counts)*m["mc"]}')
    print('SNR_COUNTS='+str(dict(zip(m['snr_db'],counts))))
if (root/'workers.pid').exists():
    for line in (root/'workers.pid').read_text().splitlines():
        try:os.kill(int(line),0);print('WORKER_ALIVE='+line)
        except ProcessLookupError:print('WORKER_EXITED='+line)
for f in sorted((root/'logs').glob('worker_*.log')):
    print(f.name+':\n'+'\n'.join(f.read_text(errors='replace').splitlines()[-5:]))
