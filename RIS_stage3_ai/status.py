"""Read live heartbeat, process identity and real stage progress (no fabricated ETA)."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import platform
from .storage import read_json
from .server_pipeline import process_identity, STAGES


def status(output):
    output = Path(output)
    state = read_json(output/'pipeline_state.json')
    owner = state['owner']
    same_host = owner['host'] == platform.node()
    identity = state.get('process')
    alive = (identity is not None and process_identity(owner['pid']) == identity) if same_host else None
    age = (datetime.now(timezone.utc)-datetime.fromisoformat(state['updated'])).total_seconds()
    effective = state['state']
    if effective == 'RUNNING' and alive is False and platform.system() == 'Linux':
        effective = 'STOPPED_WITH_STALE_STATE'
    stages = {}
    for stage in STAGES:
        stages[stage] = {}
        for name in ('state.json','progress.json'):
            path = output/stage/name
            if path.exists():
                stages[stage][name] = read_json(path)
    return dict(effective_state=effective, runner_alive=alive, heartbeat_age_seconds=age,
                pipeline=state, stages=stages,
                note='Progress files are saved counts; COMPLETE may include retained algorithm/deadline failures.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(status(args.output), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
