"""Independently check an audited server export and explain its effect sizes."""
import csv
import hashlib
import json
import sys
from pathlib import Path

import matplotlib
import numpy as np

matplotlib.use("Agg")
import matplotlib.pyplot as plt


def analyze(folder):
    manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))
    verification = json.loads((folder / "verification.json").read_text(encoding="utf-8"))
    summary = json.loads((folder / "summary.json").read_text(encoding="utf-8"))
    assert verification["complete"] and verification["cases"] == summary["cases"] == 3900
    assert verification["manifest_id"] == summary["manifest_id"] == manifest["id"]
    methods, snrs = summary["methods"], summary["snr_db"]
    assert len(methods) == 16 and len(snrs) == 13
    method_index = {name: k for k, name in enumerate(methods)}
    snr_index = {value: k for k, value in enumerate(snrs)}
    squared = np.full((300, 13, 16), np.nan)
    failures = np.zeros_like(squared, dtype=bool)
    feasible = np.zeros_like(failures)
    locked = np.zeros_like(failures)
    with (folder / "case_metrics.csv").open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    assert len(rows) == 62400
    for row in rows:
        index = int(row["trial"]), snr_index[int(row["snr_db"])], method_index[row["method"]]
        assert 0 <= index[0] < 300 and np.isnan(squared[index]), "Duplicate or invalid case"
        target_errors = np.array([float(row["target1_error_m"]), float(row["target2_error_m"])])
        error = float(row["position_rmse_m"])
        assert np.isfinite(target_errors).all() and (target_errors >= 0).all()
        assert np.isclose(error**2, np.mean(target_errors**2), rtol=1e-12, atol=1e-12)
        squared[index] = error**2
        failures[index] = bool(int(row["failure"]))
        feasible[index] = bool(int(row["feasible"]))
        locked[index] = bool(int(row["locked"]))
        assert failures[index] == (not locked[index] or not feasible[index] or (target_errors > 5).any())
    assert np.isfinite(squared).all()
    assert (locked == locked[:, :, :1]).all()
    rmse = np.sqrt(np.mean(squared, axis=0))
    max_difference = float(np.max(np.abs(rmse - np.asarray(summary["rmse_m"]))))
    assert max_difference < 1e-9
    assert np.array_equal(failures.sum(axis=0), summary["failure_count"])
    assert np.array_equal(feasible.sum(axis=0), summary["feasible_count"])
    assert np.array_equal(locked[:, :, 0].sum(axis=0), summary["coarse_locked"])
    primary = [snr_index[s] for s in summary["primary_snr_db"]]
    assert summary["primary_snr_db"] == list(range(-20, 11, 5))
    comparisons = summary["comparisons"]
    assert len(comparisons) == 8
    for item in comparisons:
        candidate, reference = method_index[item["method"]], method_index[item["reference"]]
        point = float(100 * np.mean(1 - rmse[primary, candidate] / rmse[primary, reference]))
        assert abs(point - item["mean_of_seven_snr_rmse_reductions_percent"]) < 1e-9
        low, high = item["paired_bootstrap_95_percent"]
        assert np.isfinite([low, high]).all() and low <= high
    no_ris = method_index["NoRIS_PEB_refined"]
    versus_no_ris = {
        name: float(100 * np.mean(1 - rmse[primary, k] / rmse[primary, no_ris]))
        for k, name in enumerate(methods)
    }
    files = ("manifest.json", "verification.json", "summary.json", "case_metrics.csv")
    analysis = {
        "manifest_id": manifest["id"], "cases": 3900, "metric_rows": len(rows),
        "independent_csv_checks_passed": True,
        "max_rmse_difference_from_server_m": max_difference,
        "primary_snr_db": summary["primary_snr_db"],
        "predeclared_comparisons": comparisons,
        "mean_rmse_reductions_vs_NoRIS_PEB_percent_descriptive_only": versus_no_ris,
        "additional_no_ris_comparisons_have_no_predeclared_confidence_intervals": True,
        "locked_count_per_snr": summary["coarse_locked"],
        "locked_but_infeasible_count_per_method": dict(zip(methods, ((~feasible) & locked).sum(axis=(0, 1)).tolist())),
        "input_sha256": {name: hashlib.sha256((folder / name).read_bytes()).hexdigest() for name in files},
        "analysis_script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "limits": ["Original model and 300 geometries only", "Marginal exploratory bootstrap intervals; no multiplicity correction", "Hindsight selection uses test truth and is not achievable or a rigorous bound"],
    }
    (folder / "analysis.json").write_text(json.dumps(analysis, indent=2, allow_nan=False) + "\n", encoding="utf-8", newline="\n")
    with (folder / "per_snr_summary.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["snr_db", "method", "rmse_m", "failure_count", "coarse_locked", "gain_vs_NoRIS_PEB_percent"])
        for si, snr in enumerate(snrs):
            for k, name in enumerate(methods):
                writer.writerow([snr, name, rmse[si, k], int(failures[:, si, k].sum()), int(locked[:, si, k].sum()), 100 * (1 - rmse[si, k] / rmse[si, no_ris])])

    fig, axes = plt.subplots(1, 2, figsize=(12, 4.4), constrained_layout=True)
    names = ["DD_only", "AIC", "BIC", "Ridge_GCV"]
    for condition, color, offset in [("RIS_energy", "#3268a8", -.12), ("RIS_PEB", "#c37622", .12)]:
        items = {item["method"].split("/")[1]: item for item in comparisons if item["method"].startswith(condition + "/")}
        for k, name in enumerate(names):
            item = items[name]; low, high = item["paired_bootstrap_95_percent"]
            axes[0].plot([low, high], [k + offset] * 2, color=color, linewidth=2)
            axes[0].plot(item["mean_of_seven_snr_rmse_reductions_percent"], k + offset, "o", color=color, label=condition if k == 0 else None)
    axes[0].axvline(0, color="0.5", linewidth=.8)
    axes[0].set(yticks=range(4), yticklabels=names, xlabel="Mean RMSE reduction vs full model (%)", title="Predeclared -20 to 10 dB; marginal 95% intervals")
    axes[0].legend()
    for method, reference, label, style in [
        ("RIS_energy/Ridge_GCV", "RIS_energy/Full_normalized", "Energy RIS / GCV vs full", "-o"),
        ("RIS_PEB/Ridge_GCV", "RIS_PEB/Full_normalized", "PEB RIS / GCV vs full", "-s"),
        ("RIS_PEB/Ridge_GCV", "NoRIS_PEB_refined", "PEB RIS / GCV vs NoRIS PEB", "--^"),
    ]:
        gains = 100 * (1 - rmse[primary, method_index[method]] / rmse[primary, method_index[reference]])
        axes[1].plot(summary["primary_snr_db"], gains, style, label=label, markersize=4)
    axes[1].axhline(0, color="0.5", linewidth=.8)
    axes[1].set(xlabel="Input SNR (dB)", ylabel="RMSE reduction (%)", title="Per-SNR effects; NoRIS comparison is descriptive")
    axes[1].legend(fontsize=8)
    for axis in axes:
        axis.grid(alpha=.2)
    fig.savefig(folder / "effect_sizes.png", dpi=220)
    plt.close(fig)
    print(json.dumps(analysis, indent=2))


if __name__ == "__main__":
    analyze(Path(sys.argv[1]))
