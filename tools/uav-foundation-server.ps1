[CmdletBinding()]
param(
    [Parameter(Position=0)][ValidateSet('upload','test','pilot','run','status','fetch')][string]$Action='status',
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$Release,
    [ValidateSet('foundation','diagnosis')][string]$Experiment='foundation',
    [ValidateRange(1,8)][int]$Workers=8
)
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$relative='stage3-RIS与毫米波通感一体化联合优化算法方案/code'
$target='jzm123@100.120.122.2'
$remote="/home/jzm123/AAA_ZTEproject/RIS_UAV_foundation/releases/$Release"
$uav="$remote/code/uav"
$runner='run_uav_foundation'; $tester='test_uav_foundation'
if($Experiment -eq 'diagnosis') {
    $uav="$uav/diagnosis"; $runner='run_uav_diagnosis'; $tester='test_uav_diagnosis'
}
$sshOptions=@('-i',(Join-Path $env:USERPROFILE '.ssh/codex_zte_automation_ed25519'),
    '-o','BatchMode=yes','-o','IdentitiesOnly=yes','-o','StrictHostKeyChecking=yes','-o','ConnectTimeout=10')
function Remote([string]$command) {
    & ssh @sshOptions $target $command
    if($LASTEXITCODE -ne 0){throw "Remote command failed: $LASTEXITCODE"}
}
switch($Action) {
    upload {
        $head=(git -C $project rev-parse HEAD).Trim()
        if($head -ne $Release){throw 'Upload must use the current committed release'}
        $staging=Join-Path $project 'tmp/uav-foundation'
        New-Item -ItemType Directory -Force -Path $staging | Out-Null
        $bundle=Join-Path $staging "$Release.tar"
        $base=@('build_default_params.m','channel_geometry.m','joint_estimator_fast.m',
            'prepare_ris_observation.m','refine_ris_parameters.m','evaluate_estimation.m')
        if($Experiment -eq 'diagnosis'){$base+=@('path_reliability/pr_dictionary.m','path_reliability/pr_refine.m')}
        $paths=@("$relative/uav")+@($base | ForEach-Object {"$relative/$_"})
        & git -C $project archive --format=tar "--output=$bundle" HEAD -- @paths
        if($LASTEXITCODE -ne 0){throw 'Source archive failed'}
        Remote "test ! -e $remote && mkdir -p $remote/code"
        & scp @sshOptions $bundle "${target}:$remote/source.tar"
        if($LASTEXITCODE -ne 0){throw 'Source upload failed'}
        Remote "tar -xf $remote/source.tar --strip-components=2 -C $remote/code && bash -n $uav/run_server.sh"
        $verify=@"
import hashlib,pathlib,tarfile,json
root=pathlib.Path('$remote')
checked=[]
with tarfile.open(root/'source.tar') as archive:
    for member in archive.getmembers():
        if not member.isfile(): continue
        rel=pathlib.PurePosixPath(member.name).parts[2:]
        expected=hashlib.sha256(archive.extractfile(member).read()).hexdigest()
        p=root/'code'/pathlib.Path(*rel)
        actual=hashlib.sha256(p.read_bytes()).hexdigest()
        assert actual==expected,str(p)
        checked.append({'file':'/'.join(rel),'sha256':actual})
(root/'deployment_hashes.json').write_text(json.dumps(checked,indent=2))
print('Verified immutable archive:',len(checked),'files, release=$Release')
"@
        $verify | & ssh @sshOptions $target 'python3 -'
        if($LASTEXITCODE -ne 0){throw 'Deployment hash verification failed'}
    }
    test {
        Remote "cd $uav && /home/jzm123/MATLAB/R2022b/bin/matlab -batch `"${tester}('server_smoke.json'); exit(0);`" > server_smoke.log 2>&1 && cat server_smoke.json"
    }
    pilot {
        Remote "cd $uav && /home/jzm123/MATLAB/R2022b/bin/matlab -batch `"${runner}('pilot','$uav/results_pilot'); exit(0);`" > pilot.log 2>&1 && cat results_pilot/verification.json && cat results_pilot/summary.json"
    }
    run {
        $launch=@"
import json,os,pathlib,subprocess
root=pathlib.Path('$uav')
assert json.loads((root/'server_smoke.json').read_text())['passed']
pilot=json.loads((root/'results_pilot/verification.json').read_text())
assert pilot['passed'] and pilot['cases']==3
environment=os.environ.copy(); environment['UAV_WORKERS']='$Workers'
with (root/'supervisor.log').open('a') as log:
    p=subprocess.Popen(['bash','run_server.sh'],cwd=root,env=environment,stdin=subprocess.DEVNULL,
        stdout=log,stderr=log,start_new_session=True)
print('Supervisor PID',p.pid)
"@
        $launch | & ssh @sshOptions $target 'python3 -'
        if($LASTEXITCODE -ne 0){throw 'Launch failed'}
    }
    status {
        $status=@"
import json,pathlib,datetime,os
root=pathlib.Path('$uav/results_full')
state=(root/'state').read_text().strip() if (root/'state').exists() else 'NOT_STARTED'
workers=[]
for p in sorted(root.glob('worker_*.json')):
    x=json.loads(p.read_text()); workers.append(x)
saved=len(list((root/'samples').glob('mc_*_rcs_*.mat')))
print(json.dumps({'state':state,'checkpoints':saved,'expected':900,'workers':workers},indent=2))
"@
        $status | & ssh @sshOptions $target 'python3 -'
        if($LASTEXITCODE -ne 0){throw 'Status failed'}
    }
    fetch {
        Remote "test -f $uav/results_full/verification.json && grep -qx COMPLETE $uav/results_full/state"
        $dest=Join-Path $project "server-results/uav-$Experiment/$Release"
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        foreach($file in 'manifest.json','summary.json','verification.json','case_metrics.csv','comparison.png') {
            & scp @sshOptions "${target}:$uav/results_full/$file" $dest
            if($LASTEXITCODE -ne 0){throw "Fetch failed: $file"}
        }
        & scp @sshOptions "${target}:$remote/deployment_hashes.json" "${target}:$uav/server_smoke.json" $dest
        if($LASTEXITCODE -ne 0){throw 'Audit evidence fetch failed'}
    }
}
