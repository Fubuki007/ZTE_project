#!/usr/bin/env python3
"""Read-only Linux resource sampling for real parallel MATLAB workers."""
import argparse
import json
import time
from pathlib import Path


def snapshot():
    memory = {}
    for line in Path('/proc/meminfo').read_text().splitlines():
        parts = line.split()
        if parts[0] in ('MemTotal:', 'MemAvailable:', 'SwapFree:'):
            memory[parts[0][:-1] + '_kib'] = int(parts[1])
    workers = []
    for path in Path('/proc').iterdir():
        if not path.name.isdigit():
            continue
        try:
            args = (path / 'cmdline').read_bytes().split(b'\0')
            if not args or not args[0].endswith(b'/glnxa64/MATLAB'):
                continue
            if not any(arg.startswith(b'run_ris_rmse_snr_sic_worker(') for arg in args):
                continue
            fields = {}
            for line in (path / 'status').read_text().splitlines():
                if line.startswith(('VmRSS:', 'VmHWM:', 'VmSwap:')):
                    key, value, *_ = line.split()
                    fields[key[:-1] + '_kib'] = int(value)
            workers.append(dict(pid=int(path.name), **fields))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
    return dict(time=time.strftime('%Y-%m-%d %H:%M:%S'), workers=workers, **memory)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=int, default=600)
    parser.add_argument('--interval', type=int, default=5)
    args = parser.parse_args()
    end = time.monotonic() + args.seconds
    while True:
        print(json.dumps(snapshot()), flush=True)
        if time.monotonic() >= end:
            break
        time.sleep(min(args.interval, max(0, end-time.monotonic())))
