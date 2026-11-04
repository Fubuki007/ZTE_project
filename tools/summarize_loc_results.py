"""Analyze audited full results; bootstrap whole MC geometries across SNRs."""
import csv
import json
import sys
from pathlib import Path

import numpy as np


METHODS = ["Fixed_energy", "FAS_energy_guard0", "FAS_energy_guard4",
           "Fixed_localization", "FAS_localization_guard0", "FAS_localization_guard4"]
SNRS = np.arange(-50, 11, 5)
PRIMARY_SNRS = np.arange(-20, 11, 5)


def read_csv(path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def paired_gains(mse, resamples=5000, seed=2026110301):
    """One resampled trial index applies to every method and SNR in that draw."""
    assert mse.ndim == 3 and mse.shape[2] == 6
    assert np.all(np.isfinite(mse)) and np.all(mse >= 0)
    rmse = np.sqrt(mse.mean(axis=0))
    assert np.all(rmse[:, 3] > 0)
    point = 100 * (1 - rmse[:, 4:6] / rmse[:, 3:4])
    boot = np.empty((resamples, mse.shape[1], 2))
    rng = np.random.default_rng(seed)
    for start in range(0, resamples, 100):
        count = min(100, resamples - start)
        indices = rng.integers(len(mse), size=(count, len(mse)))
        sampled = np.sqrt(mse[indices].mean(axis=1))
        assert np.all(sampled[:, :, 3] > 0)
        boot[start:start + count] = 100 * (1 - sampled[:, :, 4:6] / sampled[:, :, 3:4])
    return point, boot


def distribution(values):
    values = np.asarray(values, dtype=float)
    finite = values[np.isfinite(values)]
    result = {"total": len(values), "finite": len(finite),
              "positive_infinity": int(np.isposinf(values).sum()),
              "negative_infinity": int(np.isneginf(values).sum()), "unavailable": int(np.isnan(values).sum())}
    if len(finite):
        result["finite_quantiles_0_5_50_95_100"] = np.quantile(finite, [0, .05, .5, .95, 1]).tolist()
    return result


def summarize(run):
    verification = json.loads((run / "audit" / "verification.json").read_text(encoding="utf-8"))
    manifest = json.loads((run / "manifest.json").read_text(encoding="utf-8"))
    revision = json.loads((run / "aggregation_revision.json").read_text(encoding="utf-8"))
    assert verification["complete"] and verification["profile"] == "full"
    assert verification["count"] == 3900 and verification["oracle_count"] == 300
    assert verification["input_manifest_id"] == manifest["id"] == revision["input_manifest_id"]
    assert verification["aggregation_sha256"] == revision["aggregation_sha256"]
    rows = read_csv(run / "audit" / "case_metrics.csv")
    assert len(rows) == 3900 * 6
    mse = np.full((300, 13, 6), np.nan)
    seen = set()
    for row in rows:
        trial, snr, method = int(row["trial"]), int(row["snr_db"]), row["method"]
        assert 0 <= trial < 300 and snr in SNRS and method in METHODS
        index = (trial, int(np.flatnonzero(SNRS == snr)[0]), METHODS.index(method))
        assert index not in seen
        seen.add(index)
        mse[index] = float(row["position_mse_m2"])
    point, boot = paired_gains(mse)
    selected = np.isin(SNRS, PRIMARY_SNRS)
    summary = {"input_manifest_id": manifest["id"], "verification": verification,
               "bootstrap": {"resamples": len(boot), "seed": 2026110301,
                             "unit": "whole MC geometry, paired across all SNRs and methods"},
               "primary_metric": "unweighted mean of seven per-SNR RMSE reductions, including all failures",
               "primary_snrs_db": PRIMARY_SNRS.tolist(), "comparisons": {}}
    for j, method in enumerate(METHODS[4:6]):
        interval = np.quantile(boot[:, selected, j].mean(axis=1), [.025, .975])
        # Approximate simultaneous bootstrap band across all 13 SNRs, per comparison.
        radius = float(np.quantile(np.max(abs(boot[:, :, j] - point[:, j]), axis=1), .95))
        summary["comparisons"][method] = {
            "reference": METHODS[3], "primary_gain_percent": float(point[selected, j].mean()),
            "primary_paired_ci95_percent": interval.tolist(),
            "all_snr_gain_percent": point[:, j].tolist(),
            "all_snr_pointwise_ci95_percent": np.quantile(boot[:, :, j], [.025, .975], axis=0).T.tolist(),
            "all_snr_simultaneous95_radius_percent": radius}
    oracle = read_csv(run / "oracle.csv")
    assert len(oracle) == 300 and {int(r["trial"]) for r in oracle} == set(range(300))
    summary["oracle"] = {key: distribution([float(row[key]) for row in oracle]) for key in
                         ["gain_percent", "guard4_gain_percent", "continuous_objective_gain_percent"]}
    designs = read_csv(run / "audit" / "design_checks.csv")
    summary["design_checks"] = {}
    for method in METHODS[3:5]:
        selected_rows = [row for row in designs if row["method"] == method]
        summary["design_checks"][method] = {key: distribution([float(row[key]) for row in selected_rows]) for key in
                                           ["max_displacement_lambda", "search_seconds", "iteration_limit_runs", "negative_exit_runs"]}
    (run / "analysis.json").write_bytes((json.dumps(summary, indent=2, allow_nan=False) + "\n").encode("utf-8"))
    plot(run, point, boot, oracle)
    print(json.dumps(summary["comparisons"], indent=2))


def plot(run, point, boot, oracle):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(1, 2, figsize=(11, 4.1), layout="constrained")
    for j, label in enumerate(["FAS, guard 0", "FAS, guard 4"]):
        ci = np.quantile(boot[:, :, j], [.025, .975], axis=0)
        line, = axes[0].plot(SNRS, point[:, j], "o-", label=label)
        axes[0].fill_between(SNRS, ci[0], ci[1], color=line.get_color(), alpha=.15)
        key = ["gain_percent", "guard4_gain_percent"][j]
        values = np.array([float(row[key]) for row in oracle])
        finite = np.sort(values[np.isfinite(values)])
        # Keep all 300 geometries in the CDF denominator, including nonfinite entries.
        cumulative = (np.arange(1, len(finite) + 1) + np.isneginf(values).sum()) / len(values)
        axes[1].step(finite, cumulative, where="post", label=label)
    axes[0].axhline(0, color="0.3", linewidth=.8)
    axes[0].set(xlabel="SNR (dB)", ylabel="RMSE reduction vs fixed localization (%)",
                title="300 paired MC; pointwise 95% bootstrap intervals")
    axes[1].set(xlabel="Oracle PEB reduction vs fixed localization (%)", ylabel="Fraction of 300 geometries",
                title="Truth-assisted reference; not a global bound")
    for ax in axes:
        ax.grid(alpha=.25)
        ax.legend()
    fig.savefig(run / "localization_gain.png", dpi=180)
    plt.close(fig)


def self_test():
    baseline = np.arange(1, 10, dtype=float)[:, None] * np.array([1, 3, 10])[None, :]
    mse = np.repeat(baseline[:, :, None], 6, axis=2)
    mse[:, :, 4] *= .9 ** 2
    mse[:, :, 5] *= 1.1 ** 2
    point, boot = paired_gains(mse, resamples=200)
    assert np.allclose(point, [10, -10]) and np.allclose(boot, [10, -10])
    counts = distribution([1, np.inf, np.nan])
    assert counts["finite"] == 1 and counts["positive_infinity"] == 1 and counts["unavailable"] == 1
    print("PAIRED BLOCK BOOTSTRAP SELF-TEST PASSED (synthetic data only)")


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        self_test()
    else:
        summarize(Path(sys.argv[1]))
