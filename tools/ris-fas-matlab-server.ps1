[CmdletBinding()]
param(
    [Parameter(Position=0)][ValidateSet('upload','test','run','status','fetch')][string]$Action='status',
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{7,40}$')][string]$Release,
    [ValidatePattern('^[A-Za-z0-9_]+$')][string]$RunName='full_mc300',
    [ValidateRange(1,10000)][int]$Mc=300,
    [ValidateRange(1,4)][int]$Workers=2,
    [ValidatePattern('^[-0-9.,]+$')][string]$Snr='-50,-45,-40,-35,-30,-25,-20,-15,-10,-5,0,5,10'
)
$ErrorActionPreference='Stop'
$target='jzm123@100.120.122.2'
$project=Split-Path $PSScriptRoot -Parent
$source=Join-Path $project 'stage3-RIS与毫米波通感一体化联合优化算法方案/code'
$remote="/home/jzm123/AAA_ZTEproject/RIS_stage3_matlab_fas/releases/$Release"
$run="$remote/code/fas/results_$RunName"
$key=Join-Path $env:USERPROFILE '.ssh/codex_zte_automation_ed25519'
$sshOptions=@('-i',$key,'-o','BatchMode=yes','-o','IdentitiesOnly=yes',
    '-o','StrictHostKeyChecking=yes','-o','ConnectTimeout=10')
function Remote([string]$command) {
    & ssh @sshOptions $target $command
    if($LASTEXITCODE -ne 0) { throw "Remote command failed: $LASTEXITCODE" }
}
switch($Action) {
    upload {
        # New immutable release directory; never overwrite a running release.
        Remote "test ! -e $remote && mkdir -p $remote/code/fas"
        $baseFiles=Get-ChildItem -LiteralPath $source -File | Where-Object { $_.Extension -in '.m','.md' }
        $fasFiles=Get-ChildItem -LiteralPath (Join-Path $source 'fas') -File | Where-Object { $_.Extension -in '.m','.md','.sh','.py' }
        & scp @sshOptions @($baseFiles.FullName) "${target}:$remote/code/"
        if($LASTEXITCODE -ne 0) { throw 'Base source upload failed' }
        & scp @sshOptions @($fasFiles.FullName) "${target}:$remote/code/fas/"
        if($LASTEXITCODE -ne 0) { throw 'FAS source upload failed' }
        Remote "cd $remote/code/fas && bash -n run_server.sh && python3 -m py_compile status.py"
    }
    test {
        Remote "cd $remote/code/fas && /home/jzm123/MATLAB/R2022b/bin/matlab -batch test_fas > server_test.log 2>&1 && cat server_test.log"
    }
    run {
        Remote "cd $remote/code/fas || exit 1; mkdir -p results_$RunName || exit 1; nohup env FAS_RUN_NAME=$RunName FAS_MC=$Mc FAS_WORKERS=$Workers FAS_SNR='$Snr' bash run_server.sh >> $run/supervisor.log 2>&1 < /dev/null &"
        Write-Output "Submitted release=$Release run=$RunName; use status to verify."
    }
    status {
        Remote "cd $remote/code/fas && python3 status.py results_$RunName"
    }
    fetch {
        $dest=Join-Path $project "server-results/matlab-fas/$Release/$RunName"
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        $aggregateCommand="aggregate_fas('results_$RunName',true)"
        Remote "cd $remote/code/fas && /home/jzm123/MATLAB/R2022b/bin/matlab -batch `"$aggregateCommand`""
        & scp @sshOptions "${target}:$run/manifest.json" "${target}:$run/progress.json" "${target}:$run/metrics.csv" "${target}:$run/paired_gain.csv" "${target}:$run/comparison.png" $dest
        if($LASTEXITCODE -ne 0) { throw 'Fetch failed' }
    }
}
