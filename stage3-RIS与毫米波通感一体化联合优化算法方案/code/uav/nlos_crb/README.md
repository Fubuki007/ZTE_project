# 3GPP UMi Urban Street-Canyon UAV-BS + Passive 32×32 RIS ISAC (`nlos_crb`)

Implementation of Proposal v2.0 (Scheme 2 — Medium Risk) for SCI Q2/Q1 publication.

## Physical Model & Declared Assumptions

- **Waveform & hardware (full-scale Stage-3 parameters)**: 28 GHz carrier, 120 kHz spacing,
  **12,672 subcarriers** ($B = 1.521\text{ GHz}$), 16 Tx ($4\times 4$) / 64 Rx ($8\times 8$),
  256 coarse symbols (81 LoS + 175 NLoS = 256) and 256 fine symbols (8 RIS configs × 32 symbols = 256),
  1 W total radiated power, 290 K / 7 dB receiver NF ($N_0 = -105.15\text{ dBW}$),
  2 ground communication users with 10 dB SINR constraint, 2 stationary ground sensing targets ($v_q = 0$).
- **Passive RIS**: $32\times 32 = 1024$ 2-bit elements, physical aperture $L = 17.1\text{ cm}$,
  diagonal $D = 24.2\text{ cm}$, Fraunhofer far-field distance $D_F = 2D^2/\lambda = 11.0\text{ m}$.
  All feasible UAV positions enforce $\|\mathbf{q}-\mathbf{p}_R\|_2 \ge 14.0\text{ m} > D_F$.
- **True wideband model**: All forward echoes, FIM/EFIM, and delay-window fine estimation use
  frequency-dependent steering across $f_n = f_{\text{ref}} + n\Delta f$ (narrowband centre-frequency
  steering is evaluated separately in `run_nlos_ablations.m`).
- **3GPP UMi street canyon (zero artificial no-fly boxes)**: Main avenue $x \in [-20,0], y \in [-160,160]$,
  30 m East-South & East-North buildings forming a 12 m recessed side alley ($y \in [-6,6]$),
  facade RIS at $(-20, 0, 12)$ facing $+x$. UAV may fly anywhere in legal street/alley airspace
  ($z \in [14,24]\text{ m}$, 2 m wall clearance); NLoS arises naturally from building geometry +
  28 GHz 1 W / 10 dB communication SINR physical range tether.
- **Fair baselines (8 methods)**: Includes offline global optimal fixed sites (`FixedOpt_NoRIS`,
  `FixedOpt_RIS`) calibrated on 100 disjoint scenes (`10001..10100`), unconfigured random-phase RIS
  (`FixedOpt_RandomRIS`), online UAV without RIS (`OnlineUAV_NoRIS`), exact paired same-position
  control (`MatchedPos_NoRIS`), discrete grid heuristic (`GridSelect_RIS`), external literature
  energy-max AO (`Lit_EnergyMax_AO`), and `Proposed_Joint_CRB`.

## Local Smoke Tests (Gate 1 & Gate 2)

```powershell
& 'E:\Matlab R2024a\bin\matlab.exe' -batch "cd('stage3-RIS与毫米波通感一体化联合优化算法方案\code\uav\nlos_crb'); test_gate1_math('gate1_evidence.json'); test_gate2_pipeline('gate2_evidence.json');"
```

## Server Execution (Gate 3 Pilot & Gate 4 Full 900 Cases)

Formal `full` simulations are blocked on Windows PC (`assert(~strcmp(profile,'full') || ~ispc)`)
and must run on the Linux MATLAB server:

```bash
# Gate 3: Full-bandwidth Pilot (3 scenes x 3 RCS = 9 cases)
$MATLAB_BIN -batch "run_nlos_crb('pilot','$PWD/results_pilot',0,1); exit(0);"

# Gate 4: Full 900-case experiment (300 scenes x 3 RCS x 8 methods = 7,200 rows, 8 workers)
UAV_WORKERS=8 MATLAB_BIN=/path/to/matlab bash run_server.sh

# Targeted ablations (wideband squint, prior sigma, RIS calibration, ROC/Pareto, flight energy)
$MATLAB_BIN -batch "run_nlos_ablations('$PWD/results_ablations',50); exit(0);"
```

Independent audit on fetched results:

```powershell
python tools/audit-uav-nlos-crb.py <fetched_result_dir>
```
