[CmdletBinding()]
param(
    [Parameter(Position=0)][ValidateSet('run','status','tail','stop')][string]$Action='status',
    [ValidateRange(1,10000)][int]$McTotal=60,
    [ValidateRange(1,64)][int]$Workers=4,
    [ValidatePattern('^[A-Za-z0-9_]+$')][string]$RunTag='resume_v3',
    [switch]$SinglePrecision,
    [string]$SnrList='',
    [ValidateRange(1,10000)][int]$CasesPerProcess=1,
    [ValidateRange(30,86400)][int]$StallTimeoutSeconds=900,
    [ValidateRange(1,1000)][int]$Lines=30
)
$ErrorActionPreference='Stop'
if($Workers -gt $McTotal){throw 'Workers must not exceed McTotal.'}
if($SnrList -and $SnrList -notmatch '^[+\-0-9.,\s]+$'){throw 'Invalid SnrList.'}
$remoteProject='/home/jzm123/AAA_ZTEproject'
$target='jzm123@100.120.122.2'
$privateKey=Join-Path $env:USERPROFILE '.ssh\codex_zte_automation_ed25519'
$sshOptions=@('-i',$privateKey,'-o','BatchMode=yes','-o','IdentitiesOnly=yes',
    '-o','StrictHostKeyChecking=yes','-o','ConnectTimeout=10')
$precision='double'; $singleValue=0
if($SinglePrecision){$precision='single'; $singleValue=1}
$prefix="ris_sic_rmse_snr_mc${McTotal}_${RunTag}_${precision}"
function Invoke-Ssh([string]$Command){
    & ssh @sshOptions $target $Command
    if($LASTEXITCODE -ne 0){throw "SSH command exited with $LASTEXITCODE."}
}
switch($Action){
    run {
        $root=Split-Path $PSScriptRoot -Parent
        $files=@('run_ris_rmse_snr_sic_worker.m','aggregate_ris_sic_rmse_snr_mc60.m',
            'ris_sic_run_config.m','ris_sic_save_atomic.m','ris_sic_load_sample.m',
            'generate_mimo_ofdm_waveform.m','square_qam_gray.m','joint_estimator_fast.m') |
            ForEach-Object { Join-Path $root $_ }
        Invoke-Ssh "mkdir -p $remoteProject/tools $remoteProject/logs $remoteProject/.jobs"
        Invoke-Ssh "cd $remoteProject; if test -f .jobs/${prefix}.lock; then flock -n .jobs/${prefix}.lock -c true; fi"
        & scp @sshOptions @files "${target}:$remoteProject/"
        if($LASTEXITCODE -ne 0){throw 'MATLAB upload failed.'}
        & scp @sshOptions (Join-Path $PSScriptRoot 'run-ris-sic-resumable.sh') (Join-Path $PSScriptRoot 'ris-sic-progress.py') "${target}:$remoteProject/tools/"
        if($LASTEXITCODE -ne 0){throw 'Launcher upload failed.'}
        $snrEnv=''
        if($SnrList){$snrEnv="RIS_SNR_LIST='$SnrList'"}
        Invoke-Ssh "cd $remoteProject; bash -n tools/run-ris-sic-resumable.sh"
        Invoke-Ssh "cd $remoteProject; nohup env RIS_MC_TOTAL=$McTotal RIS_N_SHARDS=$Workers RIS_USE_SINGLE=$singleValue RIS_RUN_TAG=$RunTag RIS_CASES_PER_PROCESS=$CasesPerProcess RIS_STALL_TIMEOUT_SECONDS=$StallTimeoutSeconds $snrEnv bash tools/run-ris-sic-resumable.sh >> logs/${prefix}_supervisor.out 2>&1 < /dev/null & echo SUBMITTED"
        Write-Output "Submitted $prefix. Use status to confirm startup. The same command resumes saved cases."
    }
    status {
        $snrCount=7
        if($SnrList){$snrCount=($SnrList.Trim() -split '[,\s]+').Count}
        Invoke-Ssh "cd $remoteProject; if test -f tools/ris-sic-progress.py; then python3 tools/ris-sic-progress.py ${prefix}_samples --mc-total $McTotal --snr-count $snrCount --summary; fi"
        Invoke-Ssh "cd $remoteProject; if test -f .jobs/${prefix}.state; then cat .jobs/${prefix}.state; else echo NOT_FOUND; fi; if test -f .jobs/${prefix}.supervisor.pid; then ps -p `$(cat .jobs/${prefix}.supervisor.pid) -o pid,etime,stat,args || true; fi; for f in logs/${prefix}_shard*_supervised.out; do test -f `"`$f`" || continue; echo `"`$f`"; tail -n 3 `"`$f`"; done"
    }
    tail {
        Invoke-Ssh "cd $remoteProject; for f in logs/${prefix}_shard*_supervised.out logs/${prefix}_aggregate.out; do test -f `"`$f`" || continue; echo `"`$f`"; tail -n $Lines `"`$f`"; done"
    }
    stop {
        Invoke-Ssh "cd $remoteProject; test -s .jobs/${prefix}.supervisor.pid; pid=`$(cat .jobs/${prefix}.supervisor.pid); if ps -p `"`$pid`" -o args= | grep -q 'bash tools/run-ris-sic-resumable.sh'; then kill -TERM `"`$pid`"; else echo 'No active matching supervisor'; fi"
    }
}
