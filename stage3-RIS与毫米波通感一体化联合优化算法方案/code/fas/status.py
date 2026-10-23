"""Read actual MATLAB checkpoint and worker state; no simulation dependencies."""
import json
import os
from pathlib import Path
import sys

root = Path(sys.argv[1])
manifest = json.loads((root / 'manifest.json').read_text()) if (root / 'manifest.json').exists() else {}
workers = [json.loads(p.read_text()) for p in sorted(root.glob('worker_*.json'))]
samples = [p for p in (root / 'samples').glob('snr_*_mc_*.mat') if '.tmp.' not in p.name]
state = (root / 'state').read_text().strip() if (root / 'state').exists() else 'NOT_STARTED'
pids = (root / 'workers.pid').read_text().split() if (root / 'workers.pid').exists() else []
alive = []
for pid in pids:
    try:
        os.kill(int(pid), 0)
        alive.append(int(pid))
    except (ProcessLookupError, PermissionError):
        pass
if state == 'RUNNING' and not alive and workers:
    state = 'NO_LIVE_WORKERS_CHECK_SUPERVISOR'
print(json.dumps(dict(state=state,completed=len(samples),expected=manifest.get('total_cases'),
                     manifest_id=manifest.get('id'),live_worker_pids=alive,workers=workers),
                 ensure_ascii=False,indent=2))
