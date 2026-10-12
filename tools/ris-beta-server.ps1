[CmdletBinding()]
param(
    [Parameter(Position=0)][ValidateSet('upload','run','status','tail','stop','fetch')][string]$Action='status',
    [ValidateRange(1,10000)][int]$McTotal=50,
    [ValidateRange(1,64)][int]$Workers=4,
    [ValidatePattern('^[A-Za-z0-9_]+$')][string]$RunTag='20261010',
    [string]$SnrList='-25,-20,-15,-10,0,10,20',
    [string]$BetaList='10,100,1000',
    [ValidateRange(1,10000)][int]$CasesPerProcess=1,
    [ValidateRange(1,1000)][int]$Lines=15
)
$ErrorActionPreference='Stop'
if($Workers -gt $McTotal){throw 'Workers exceed MC count.'}
foreach($v in @($SnrList,$BetaList)){if($v -notmatch '^[+\-0-9.,\s]+$'){throw 'Invalid numeric list.'}}
$root=Split-Path $PSScriptRoot -Parent
$prefix="ris_beta_sweep_mc${McTotal}_${RunTag}_double"
$remote="/home/jzm123/AAA_ZTEproject/.jobs/experiments/$prefix"
$target='jzm123@100.120.122.2'
$sshOptions=@('-i',(Join-Path $env:USERPROFILE '.ssh/codex_zte_automation_ed25519'),
    '-o','BatchMode=yes','-o','IdentitiesOnly=yes','-o','StrictHostKeyChecking=yes','-o','ConnectTimeout=10')
function Remote([string]$cmd){& ssh @sshOptions $target $cmd; if($LASTEXITCODE -ne 0){throw "SSH failed: $LASTEXITCODE"}}
$envArgs="RIS_MC_TOTAL=$McTotal RIS_N_SHARDS=$Workers RIS_SNR_LIST='$SnrList' RIS_BETA_LIST='$BetaList' RIS_RESULT_PREFIX=$prefix RIS_CASES_PER_PROCESS=$CasesPerProcess RIS_WORKER_FUNCTION=ris_beta_worker RIS_AGGREGATE_FUNCTION=aggregate_ris_beta_sweep ZTE_PROJECT_DIR=$remote"
switch($Action){
    {$_ -in @('upload','run')} {
        Remote "mkdir -p $remote/tools $remote/logs $remote/.jobs"
        Remote "cd $remote; if test -f .jobs/$prefix.lock; then flock -n .jobs/$prefix.lock -c true; fi"
        $names=@('ris_beta_config.m','ris_beta_prepare.m','ris_beta_load_sample.m','ris_beta_worker.m',
            'ris_beta_summarize.m','aggregate_ris_beta_sweep.m','test_ris_beta_sweep.m',
            'ris_sic_save_atomic.m','build_default_params.m','generate_HSI.m',
            'generate_mimo_ofdm_waveform.m','square_qam_gray.m','design_precoder.m',
            'build_ris_target_model.m','optimize_ris_target_phase.m',
            'simulate_radar_channel_3d.m','estimate_si_channel_ls.m','joint_estimator_fast.m','evaluate_estimation.m')
        $files=$names | ForEach-Object {Join-Path $root $_}
        $files+=Join-Path $PSScriptRoot 'validate_ris_beta_equivalence.m'
        & scp @sshOptions @files "${target}:$remote/"
        if($LASTEXITCODE -ne 0){throw 'MATLAB upload failed.'}
        $helpers=@('run-ris-sic-resumable.sh','ris-sic-progress.py','ris-beta-progress.py','test-ris-sic-supervisor.sh') |
            ForEach-Object {Join-Path $PSScriptRoot $_}
        & scp @sshOptions @helpers "${target}:$remote/tools/"
        if($LASTEXITCODE -ne 0){throw 'Supervisor upload failed.'}
        Remote "cd $remote; bash -n tools/run-ris-sic-resumable.sh"
        if($Action -eq 'upload'){Write-Output "Uploaded to $remote"; break}
        Remote "cd $remote; nohup env $envArgs bash tools/run-ris-sic-resumable.sh >> logs/${prefix}_supervisor.out 2>&1 < /dev/null & echo SUBMITTED"
        Write-Output "Experiment directory: $remote"
    }
    status {
        $snrs=($SnrList.Trim() -split '[,\s]+').Count
        $betas=($BetaList.Trim() -split '[,\s]+').Count
        Remote "cd $remote; cat .jobs/$prefix.state; python3 tools/ris-beta-progress.py ${prefix}_samples --mc $McTotal --snr-count $snrs --beta-count $betas; for f in logs/${prefix}_shard*_supervised.out; do echo `"`$f`"; tail -n 3 `"`$f`"; done"
    }
    tail {Remote "cd $remote; tail -n $Lines logs/${prefix}_shard*_supervised.out"}
    stop {Remote "cd $remote; pid=`$(cat .jobs/$prefix.supervisor.pid); if ps -p `"`$pid`" -o args= | grep -q 'bash tools/run-ris-sic-resumable.sh'; then kill -TERM `"`$pid`"; fi"}
    fetch {
        $dest=Join-Path $root "server-results/$prefix"
        New-Item -ItemType Directory -Force $dest | Out-Null
        & scp @sshOptions "${target}:$remote/${prefix}_results.mat" "${target}:$remote/${prefix}_summary.csv" "${target}:$remote/fig/${prefix}*.png" $dest
        if($LASTEXITCODE -ne 0){throw 'Result download failed or not complete.'}
        Write-Output $dest
    }
}
