[CmdletBinding()]
param(
    [Parameter(Position=0)][ValidateSet('upload','run','status','fetch')][string]$Action='status',
    [ValidatePattern('^[A-Za-z0-9_]+$')][string]$RunName='results_full_mc100',
    [ValidateRange(1,10000)][int]$Mc=100,
    [ValidateRange(1,4)][int]$Workers=2,
    [ValidatePattern('^[0-9,+.\-]+$')][string]$Snr='-30,-25,-20,-15,-10,-5,0,5,10,15,20'
)
$ErrorActionPreference='Stop'
$target='jzm123@100.120.122.2'
$remote='/home/jzm123/AAA_ZTEproject/RIS_stage3'
$key=Join-Path $env:USERPROFILE '.ssh/codex_zte_automation_ed25519'
$sshOptions=@('-i',$key,'-o','BatchMode=yes','-o','IdentitiesOnly=yes',
              '-o','StrictHostKeyChecking=yes','-o','ConnectTimeout=10')
$localRoot=Split-Path $PSScriptRoot -Parent
function Remote([string]$Command){
    & ssh @sshOptions $target $Command
    if($LASTEXITCODE -ne 0){throw "Remote command failed: $LASTEXITCODE"}
}
switch($Action){
    upload {
        Remote "mkdir -p $remote"
        $files=Get-ChildItem -LiteralPath (Join-Path $localRoot 'RIS_stage3') -File |
            Where-Object { $_.Extension -in '.py','.sh','.txt','.md' }
        & scp @sshOptions @($files.FullName) "${target}:$remote/"
        if($LASTEXITCODE -ne 0){throw 'Stage-3 upload failed'}
        Remote "cd $remote && bash -n run_server.sh && .venv311/bin/python -m py_compile stage3_model.py streaming.py run_stage3.py"
    }
    run {
        Remote "cd $remote; mkdir -p $RunName; nohup env STAGE3_RUN_NAME=$RunName STAGE3_MC=$Mc STAGE3_WORKERS=$Workers STAGE3_SNR='$Snr' bash run_server.sh >> $remote/$RunName/supervisor.log 2>&1 < /dev/null &"
        Write-Output "Submitted $RunName. Verify using status."
    }
    status {
        Remote "cd $remote && .venv311/bin/python status_stage3.py $RunName"
    }
    fetch {
        $dest=Join-Path $localRoot "server-results/stage3/$RunName"
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Remote "cd $remote && .venv311/bin/python run_stage3.py --aggregate-only --partial --output $RunName"
        & scp @sshOptions "${target}:$remote/$RunName/angle_rmse_vs_snr.csv" "${target}:$remote/$RunName/angle_rmse_vs_snr.png" "${target}:$remote/$RunName/angle_rmse_vs_snr.svg" "${target}:$remote/$RunName/manifest.json" "${target}:$remote/$RunName/progress.json" $dest
        if($LASTEXITCODE -ne 0){throw 'Fetch failed'}
        Write-Output "RESULTS=$dest"
    }
}
