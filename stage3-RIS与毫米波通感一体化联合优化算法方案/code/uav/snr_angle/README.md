# UAV RIS SNR-angle sweep

The formal sweep uses 300 paired stationary-target scenes, RCS 10/100/1000 m^2,
and reference SNR -60:5:-20 dB (8,100 cases). The reference SNR is defined at
200 m and RCS 1 m^2. Receiver noise is scaled to set that reference; transmit
power, 28 GHz carrier, 12,672 subcarriers, 16 Tx / 64 Rx elements, 256 symbols
per CPI, and 256-element 2-bit RIS remain unchanged.

RIS is enabled for both fine-stage configurations. The existing model performs
coarse range/angle capture through the direct path; the sweep reports that
capture and RIS fine-stage coverage separately. Angle RMSE is spherical
direction error over targets and paired scenes that actually enter feasible
RIS fine estimation. The plot includes its 95% paired-scene bootstrap interval
and a second panel for RIS fine-stage coverage, so uncaptured cases are visible.
All strict failures remain in the per-case table and failure rate.

Run the smoke test locally from the repository root:

```powershell
& 'E:\Matlab R2024a\bin\matlab.exe' -batch "cd(fullfile(pwd,'stage3-RIS与毫米波通感一体化联合优化算法方案','code','uav','snr_angle')); test_uav_snr_angle('local_smoke.json')"
```

After committing and pushing a release, deploy and run the full experiment on
the configured server:

```powershell
./tools/uav-foundation-server.ps1 upload -Experiment snr_angle -Release <sha>
./tools/uav-foundation-server.ps1 test -Experiment snr_angle -Release <sha>
./tools/uav-foundation-server.ps1 pilot -Experiment snr_angle -Release <sha>
./tools/uav-foundation-server.ps1 run -Experiment snr_angle -Release <sha> -Workers 8
./tools/uav-foundation-server.ps1 status -Experiment snr_angle -Release <sha>
./tools/uav-foundation-server.ps1 fetch -Experiment snr_angle -Release <sha>
```
