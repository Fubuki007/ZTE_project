"""Run local mathematical smoke checks and save reproducible evidence."""
import argparse
from datetime import datetime, timezone, timedelta
import hashlib
import io
import json
import platform
from pathlib import Path
import sys
import time
import unittest

import numpy as np
import scipy
import torch
from . import test_design


class RecordedResult(unittest.TextTestResult):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.records = []

    def startTest(self, test):
        self.test_started = time.perf_counter()
        super().startTest(test)

    def addSuccess(self, test):
        super().addSuccess(test)
        self.records.append(dict(test=test.id(), status='PASS', seconds=time.perf_counter()-self.test_started))

    def addFailure(self, test, err):
        super().addFailure(test, err)
        self.records.append(dict(test=test.id(), status='FAIL', seconds=time.perf_counter()-self.test_started))

    def addError(self, test, err):
        super().addError(test, err)
        self.records.append(dict(test=test.id(), status='ERROR', seconds=time.perf_counter()-self.test_started))

    def addSkip(self, test, reason):
        super().addSkip(test, reason)
        self.records.append(dict(test=test.id(), status='SKIPPED', reason=reason))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', choices=('design', 'dataset', 'training'), default='design')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.suite == 'training':
        from . import test_training
        module = test_training
    elif args.suite == 'dataset':
        from . import test_dataset
        module = test_dataset
    else:
        module = test_design
    if args.output is None:
        args.output = Path('RIS_stage3_ai/evidence')/dict(design='g2_design_checks.json', dataset='g3_dataset_checks.json', training='g3_training_checks.json')[args.suite]
    root = Path(__file__).resolve().parent.parent
    files = sorted((root/'RIS_stage3_ai').glob('*.py'))+[root/'RIS_stage3/stage3_model.py', root/'RIS_stage3/streaming.py', root/'RIS_stage3_ai/requirements.txt', root/'RIS_stage3_ai/experiment_v1.json']
    files += [root/'RIS_stage3_ai/training_v1.json']
    hashes_before = {str(p.relative_to(root)).replace('\\', '/'): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    stream = io.StringIO()
    started = time.perf_counter()
    result = unittest.TextTestRunner(stream=stream, verbosity=2, resultclass=RecordedResult).run(
        unittest.defaultTestLoader.loadTestsFromModule(module))
    unchanged = all(hashlib.sha256((root/name).read_bytes()).hexdigest() == sha for name, sha in hashes_before.items())
    complete = result.wasSuccessful() and not result.skipped and unchanged and len(result.records) == result.testsRun
    report = dict(
        scope='LOCAL_SMOKE_NOT_FORMAL_TRAINING_OR_RMSE', suite=args.suite, passed=complete,
        date=datetime.now(timezone(timedelta(hours=8))).isoformat(),
        python=sys.version, platform=platform.platform(), torch=torch.__version__,
        numpy=np.__version__, scipy=scipy.__version__, device='cpu',
        tests_run=result.testsRun, tests=result.records,
        seconds=time.perf_counter()-started, source_unchanged_during_checks=unchanged,
        source_sha256=hashes_before, transcript=stream.getvalue())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False)+'\n', encoding='utf-8', newline='\n')
    print(stream.getvalue())
    print(f'CHECK_REPORT={args.output}; PASSED={complete}')
    return 0 if complete else 1


if __name__ == '__main__':
    raise SystemExit(main())
