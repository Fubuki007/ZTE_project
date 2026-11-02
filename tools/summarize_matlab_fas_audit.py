"""Summarize checkpoint audit CSV without rerunning the simulation."""
import csv
import json
import math
import statistics
import sys
from pathlib import Path


def summarize(source, output):
    with source.open(encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.DictReader(stream))
    assert len(rows) == 3900 * 4
    assert len({(r["trial"], r["snr_db"], r["method"]) for r in rows}) == len(rows)
    methods = ["Fixed_noRIS", "Fixed_RIS", "FAS_noRIS", "FAS_RIS"]
    keys = ["moves", "max_displacement_lambda", "moved_elements", "evaluations",
            "min_history_change", "target_steering_change", "ris_feed_change",
            "min_target_correlation", "score_vs_fixed_percent"]
    summary = {"source": "3900 existing formal checkpoints; no new MC simulation",
               "audit_code_commit": "1a3f0ea1400d57550c190a5b04ea644e2b33d0f8",
               "methods": {}}
    by_snr = []
    for method in methods:
        all_rows = [r for r in rows if r["method"] == method]
        active = [r for r in all_rows if r["locked"] == "1"]
        entry = {"total": len(all_rows), "coarse_locked": len(active),
                 "skipped_at_coarse": len(all_rows) - len(active),
                 "feasible_when_locked": sum(r["feasible"] == "1" for r in active),
                 "samples_with_moves": sum(float(r["moves"]) > 0 for r in active),
                 "history_decreased_beyond_1e_minus8": sum(float(r["min_history_change"]) < -1e-8 for r in active)}
        for key in keys:
            values = [float(r[key]) for r in active if math.isfinite(float(r[key]))]
            if values:
                entry[key] = {"min": min(values), "median": statistics.median(values), "max": max(values)}
        summary["methods"][method] = entry
        if method != "FAS_RIS":
            continue
        for snr in range(-50, 11, 5):
            selected = [r for r in active if float(r["snr_db"]) == snr]
            by_snr.append({"snr_db": snr, "mc": 300, "coarse_locked": len(selected),
                           "fas_moved": sum(float(r["moves"]) > 0 for r in selected),
                           "median_energy_gain_percent": statistics.median(float(r["score_vs_fixed_percent"]) for r in selected) if selected else None,
                           "guard0_samples": sorted({int(r["guard0_samples"]) for r in selected}),
                           "guard4_samples": sorted({int(r["guard4_samples"]) for r in selected})})
    summary["FAS_RIS_by_snr"] = by_snr
    output.write_bytes((json.dumps(summary, indent=2, allow_nan=False) + "\n").encode("utf-8"))
    print(json.dumps(summary["methods"]["FAS_RIS"], indent=2))


if __name__ == "__main__":
    summarize(Path(sys.argv[1]), Path(sys.argv[2]))
