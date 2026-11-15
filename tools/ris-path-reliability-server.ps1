[CmdletBinding()]
param(
    [Parameter(Position=0)][ValidateSet('upload','test','pilot','run','status','fetch')][string]$Action='status',
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$Release,
    [ValidateRange(1,8)][int]$Workers=8
)
$ErrorActionPreference='Stop'
$target='jzm123@100.120.122.2'
$project=Split-Path $PSScriptRoot -Parent
$code=Join-Path $project 'stage3-RIS与毫米波通感一体化联合优化算法方案/code'
$remote="/home/jzm123/AAA_ZTEproject/RIS_stage3_matlab_fas/releases/$Release/code/path_reliability"
$original='/home/jzm123/AAA_ZTEproject/RIS_stage3_matlab_fas/releases/aafa68081d27ee7b0fb379f4823c9fb48ea06194/code/fas/results_full_mc300_20261023'
$localization='/home/jzm123/AAA_ZTEproject/RIS_stage3_matlab_fas/releases/554ff78b42b720939272c60e0d9f0cc37acd82a9/code/fas/localization/results_full'
$sshOptions=@('-i',(Join-Path $env:USERPROFILE '.ssh/codex_zte_automation_ed25519'),
    '-o','BatchMode=yes','-o','IdentitiesOnly=yes','-o','StrictHostKeyChecking=yes','-o','ConnectTimeout=10')
function Remote([string]$command) {
    & ssh @sshOptions $target $command
    if($LASTEXITCODE -ne 0){throw "Remote command failed: $LASTEXITCODE"}
}
switch($Action) {
    upload {
        $head=(git -C $project rev-parse HEAD).Trim()
        if($head -ne $Release){throw 'Upload release must equal the current committed HEAD'}
        & (Join-Path $PSScriptRoot 'ris-fas-matlab-server.ps1') upload -Release $Release
        Remote "mkdir -p $remote $remote/../fas/localization"
        foreach($folder in @('path_reliability','fas/localization')) {
            $files=Get-ChildItem -LiteralPath (Join-Path $code $folder) -File | Where-Object {$_.Extension -in '.m','.md','.sh'}
            & scp @sshOptions @($files.FullName) "${target}:$remote/../$folder/"
            if($LASTEXITCODE -ne 0){throw "Upload failed: $folder"}
        }
        Remote "bash -n $remote/run_path_reliability.sh"
        $deployed=@()
        foreach($folder in @('','fas','fas/localization','path_reliability')) {
            foreach($file in Get-ChildItem -LiteralPath (Join-Path $code $folder) -File) {
                if($file.Extension -notin '.m','.md','.sh','.py'){continue}
                $relative=$file.FullName.Substring($code.Length+1).Replace('\','/')
                $deployed+=@{file=$relative;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLower()}
            }
        }
        $hashFile=Join-Path $project 'tmp/path-reliability/deployment_hashes.json'
        [System.IO.File]::WriteAllText($hashFile,($deployed | ConvertTo-Json -Depth 4),[System.Text.UTF8Encoding]::new($false))
        & scp @sshOptions $hashFile "${target}:$remote/../deployment_hashes.json"
        if($LASTEXITCODE -ne 0){throw 'Hash manifest upload failed'}
        $verification=@"
import hashlib,json,pathlib
root=pathlib.Path('$remote').parent
entries=json.loads((root/'deployment_hashes.json').read_text())
for item in entries:
    p=root/item['file']
    assert hashlib.sha256(p.read_bytes()).hexdigest()==item['sha256'],item['file']
print('Verified deployed source SHA256:',len(entries),'files')
"@
        $verification | & ssh @sshOptions $target 'python3 -'
        if($LASTEXITCODE -ne 0){throw 'Deployed source hash mismatch'}
    }
    test {
        Remote "cd $remote && /home/jzm123/MATLAB/R2022b/bin/matlab -batch `"test_path_reliability('$remote/server_smoke.json'); exit(0);`" > server_smoke.log 2>&1 && cat server_smoke.json"
    }
    pilot {
        Remote "cd $remote && /home/jzm123/MATLAB/R2022b/bin/matlab -batch `"pr_pilot('$original','$localization','$remote/pilot'); exit(0);`" > pilot.log 2>&1 && cat pilot/pilot.json"
    }
    run {
        Remote "test -f $remote/pilot/pilot.json && test -f $remote/server_smoke.json"
        $launch=@"
import json,os,pathlib,subprocess
root=pathlib.Path('$remote')
assert json.loads((root/'server_smoke.json').read_text())['passed']
pilot=json.loads((root/'pilot/pilot.json').read_text())
assert len(pilot)==2 and all(p['passed'] for p in pilot)
environment=os.environ.copy()
environment.update(PR_ORIGINAL='$original',PR_LOCALIZATION='$localization',PR_WORKERS='$Workers')
with (root/'supervisor.log').open('a') as log:
    p=subprocess.Popen(['bash','run_path_reliability.sh'],cwd=root,env=environment,stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True)
print('Supervisor PID',p.pid)
"@
        $launch | & ssh @sshOptions $target 'python3 -'
        if($LASTEXITCODE -ne 0){throw 'Launch failed'}
    }
    status { Remote "cd $remote && python3 ../fas/status.py results_full" }
    fetch {
        Remote "test -f $remote/results_full/verification.json && grep -qx COMPLETE $remote/results_full/state"
        $dest=Join-Path $project "server-results/matlab-fas/path-reliability/$Release"
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        foreach($file in 'manifest.json','verification.json','case_metrics.csv','summary.json','comparison.png') {
            & scp @sshOptions "${target}:$remote/results_full/$file" $dest
            if($LASTEXITCODE -ne 0){throw "Fetch failed: $file"}
        }
    }
}
