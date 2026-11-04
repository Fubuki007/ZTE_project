[CmdletBinding()]
param(
    [Parameter(Position=0)][ValidateSet('upload','test','pilot','run','status','fetch')][string]$Action='status',
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{7,40}$')][string]$Release,
    [ValidateRange(1,4)][int]$Workers=4
)
$ErrorActionPreference='Stop'
$target='jzm123@100.120.122.2'
$project=Split-Path $PSScriptRoot -Parent
$code=Join-Path $project 'stage3-RIS与毫米波通感一体化联合优化算法方案/code'
$remote="/home/jzm123/AAA_ZTEproject/RIS_stage3_matlab_fas/releases/$Release/code/fas/paper_scene"
$sshOptions=@('-i',(Join-Path $env:USERPROFILE '.ssh/codex_zte_automation_ed25519'),
    '-o','BatchMode=yes','-o','IdentitiesOnly=yes','-o','StrictHostKeyChecking=yes','-o','ConnectTimeout=10')
function Remote([string]$command) {
    & ssh @sshOptions $target $command
    if($LASTEXITCODE -ne 0){throw "Remote command failed: $LASTEXITCODE"}
}
switch($Action) {
    upload {
        & (Join-Path $PSScriptRoot 'ris-fas-matlab-server.ps1') upload -Release $Release
        Remote "mkdir -p $remote"
        $files=Get-ChildItem -LiteralPath (Join-Path $code 'fas/paper_scene') -File | Where-Object {$_.Extension -in '.m','.md','.sh'}
        & scp @sshOptions @($files.FullName) "${target}:$remote/"
        if($LASTEXITCODE -ne 0){throw 'Upload failed'}
        Remote "bash -n $remote/run_paper_scene.sh"
    }
    test {
        Remote "cd $remote && /home/jzm123/MATLAB/R2022b/bin/matlab -batch `"test_paper_scene('$remote/server_math.json',true); exit(0);`" > server_math.log 2>&1 && cat server_math.log"
    }
    pilot {
        Remote "cd $remote && /home/jzm123/MATLAB/R2022b/bin/matlab -batch `"paper_pilot('$remote/pilot'); exit(0);`" > pilot.log 2>&1 && cat pilot/pilot.json"
    }
    run {
        $launch=@"
import os,pathlib,subprocess
root=pathlib.Path('$remote')
environment=os.environ.copy()
environment.update(PAPER_WORKERS='$Workers')
with (root/'supervisor.log').open('a') as log:
    p=subprocess.Popen(['bash','run_paper_scene.sh'],cwd=root,env=environment,stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True)
print('Supervisor PID',p.pid)
"@
        $launch | & ssh @sshOptions $target 'python3 -'
        if($LASTEXITCODE -ne 0){throw 'Launch failed'}
    }
    status { Remote "cd $remote && python3 ../status.py results_full" }
    fetch {
        Remote "test -f $remote/results_full/verification.json"
        $dest=Join-Path $project "server-results/matlab-fas/paper-scene/$Release"
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        foreach($file in 'manifest.json','paired_gain.csv','case_metrics.csv','design_checks.csv','verification.json') {
            & scp @sshOptions "${target}:$remote/results_full/$file" $dest
            if($LASTEXITCODE -ne 0){throw "Fetch failed: $file"}
        }
    }
}
