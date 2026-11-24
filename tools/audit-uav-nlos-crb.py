#!/usr/bin/env python3
"""Independent Python standard-library audit for uav/nlos_crb full-scale server results."""
import csv
import json
import math
import pathlib
import random
import statistics
import sys


def audit(result_dir: pathlib.Path) -> None:
    manifest = json.loads((result_dir / "manifest.json").read_text(encoding="utf-8"))
    summary = json.loads((result_dir / "summary.json").read_text(encoding="utf-8"))
    verif = json.loads((result_dir / "verification.json").read_text(encoding="utf-8"))

    with (result_dir / "case_metrics.csv").open("r", encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))

    cfg = manifest["config"]
    methods = cfg["methods"]
    rcs_list = cfg["rcs_m2"] if isinstance(cfg["rcs_m2"], list) else [cfg["rcs_m2"]]
    nmc = int(cfg["mc"])
    expected_rows = nmc * len(rcs_list) * len(methods)
    assert len(rows) == expected_rows, f"Row count {len(rows)} != {expected_rows}"

    seen = set()
    by_key = {}
    max_pow = 0.0
    min_sinr = float("inf")
    for r in rows:
        key = (int(float(r["trial"])), float(r["rcs_m2"]), r["method"])
        assert key not in seen, f"Duplicate row key: {key}"
        seen.add(key)
        by_key[key] = r
        if int(float(r["feasible"])) == 1:
            pw = float(r["max_pow_frac"])
            sn = float(r["min_sinr_db"])
            max_pow = max(max_pow, pw)
            min_sinr = min(min_sinr, sn)
            assert pw <= 1.0 + 1e-5, f"Power violation {pw} at {key}"
            assert sn >= 10.0 - 1e-4, f"SINR violation {sn} at {key}"

    max_rmse_diff = 0.0
    groups = []
    for ri, rcs in enumerate(rcs_list):
        nlos_trials = [
            t for t in range(1, nmc + 1)
            if int(float(by_key[(t, float(rcs), "Proposed_Joint_CRB")]["t2_via_ris"])) == 1
        ]
        for mi, m in enumerate(methods):
            sub = [by_key[(t, float(rcs), m)] for t in range(1, nmc + 1)]
            mse = [0.5 * (float(x["err_t1_m"]) ** 2 + float(x["err_t2_m"]) ** 2) for x in sub]
            rmse = math.sqrt(sum(mse) / len(mse))
            ref_rmse = summary["rmse_all_m"][ri][mi] if len(rcs_list) > 1 else summary["rmse_all_m"][mi]
            max_rmse_diff = max(max_rmse_diff, abs(rmse - ref_rmse))

            cap = [x for x in sub if int(float(x["captured_both"])) == 1]
            cond_rmse = math.sqrt(
                sum(0.5 * (float(x["err_t1_m"]) ** 2 + float(x["err_t2_m"]) ** 2) for x in cap) / len(cap)
            ) if cap else None
            succ1 = sum(int(float(x["success_1m"])) for x in sub) / len(sub)
            succ_rel = sum(int(float(x["success_rel2pct"])) for x in sub) / len(sub)

            nlos_sub = [by_key[(t, float(rcs), m)] for t in nlos_trials]
            nlos_succ1 = (sum(int(float(x["success_1m"])) for x in nlos_sub) / len(nlos_sub)) if nlos_sub else None

            groups.append({
                "rcs_m2": rcs,
                "method": m,
                "rmse_all_m": rmse,
                "cond_rmse_m": cond_rmse,
                "capture_rate": len(cap) / len(sub),
                "success_1m_rate": succ1,
                "success_rel2pct_rate": succ_rel,
                "nlos_cases": len(nlos_trials),
                "nlos_success_1m_rate": nlos_succ1,
            })

    assert max_rmse_diff < 1e-10, f"RMSE recompute mismatch: {max_rmse_diff}"

    # Independent Python paired bootstrap (4,000 repeats) at primary RCS
    pri_rcs = float(cfg["primary_rcs_m2"])
    rng = random.Random(int(cfg["bootstrap_seed"]) + 1)
    pairs = [
        ("Proposed_vs_FixedOpt_RIS", "FixedOpt_RIS", "Proposed_Joint_CRB"),
        ("Proposed_vs_MatchedPos_NoRIS", "MatchedPos_NoRIS", "Proposed_Joint_CRB"),
        ("Proposed_vs_OnlineUAV_NoRIS", "OnlineUAV_NoRIS", "Proposed_Joint_CRB"),
        ("Proposed_vs_Lit_EnergyMax_AO", "Lit_EnergyMax_AO", "Proposed_Joint_CRB"),
    ]
    indep_boot = []
    for label, ma, mb in pairs:
        va = [0.5 * (float(by_key[(t, pri_rcs, ma)]["err_t1_m"]) ** 2 + float(by_key[(t, pri_rcs, ma)]["err_t2_m"]) ** 2) for t in range(1, nmc + 1)]
        vb = [0.5 * (float(by_key[(t, pri_rcs, mb)]["err_t1_m"]) ** 2 + float(by_key[(t, pri_rcs, mb)]["err_t2_m"]) ** 2) for t in range(1, nmc + 1)]
        sa = [int(float(by_key[(t, pri_rcs, ma)]["success_1m"])) for t in range(1, nmc + 1)]
        sb = [int(float(by_key[(t, pri_rcs, mb)]["success_1m"])) for t in range(1, nmc + 1)]
        b_rmse, b_s1 = [], []
        for _ in range(4000):
            idxs = [rng.randrange(nmc) for _ in range(nmc)]
            ra = math.sqrt(sum(va[i] for i in idxs) / nmc)
            rb = math.sqrt(sum(vb[i] for i in idxs) / nmc)
            b_rmse.append(100.0 * (1.0 - rb / max(ra, 1e-15)))
            b_s1.append(100.0 * (sum(sb[i] - sa[i] for i in idxs) / nmc))
        b_rmse.sort(); b_s1.sort()
        indep_boot.append({
            "name": label,
            "rcs_m2": pri_rcs,
            "rmse_gain_pct": 100.0 * (1.0 - math.sqrt(sum(vb)/nmc) / max(math.sqrt(sum(va)/nmc), 1e-15)),
            "rmse_ci95_pct": [b_rmse[100], b_rmse[3900]],
            "succ1m_diff_pp": 100.0 * (sum(sb) - sum(sa)) / nmc,
            "succ1m_ci95_pp": [b_s1[100], b_s1[3900]],
        })

    audit_out = {
        "passed": True,
        "manifest_id": manifest["id"],
        "rows_verified": len(rows),
        "max_rmse_diff_m": max_rmse_diff,
        "max_power_fraction": max_pow,
        "min_feasible_sinr_db": min_sinr,
        "server_verification_passed": bool(verif["passed"]),
        "groups": groups,
        "independent_bootstrap_primary_rcs": indep_boot,
    }
    out_path = result_dir / "independent_audit.json"
    out_path.write_text(json.dumps(audit_out, indent=2), encoding="utf-8")
    print(f"Independent audit PASSED: {len(rows)} rows, max_rmse_diff={max_rmse_diff:.3e} m")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: python tools/audit-uav-nlos-crb.py <result_dir>")
    audit(pathlib.Path(sys.argv[1]))
