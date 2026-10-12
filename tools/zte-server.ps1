[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('install', 'check', 'run', 'status', 'tail', 'fetch', 'cancel')]
    [string]$Action = 'status',

    [Parameter(Position = 1)]
    [string]$Job,

    [ValidateRange(1, 10000)]
    [int]$Lines = 40,

    [string]$OutputDir = (Join-Path $PSScriptRoot '..\server-results')
)

$ErrorActionPreference = 'Stop'

$RemoteHostName = '100.120.122.2'
$RemoteUser = 'jzm123'
$RemoteProjectDir = '/home/jzm123/AAA_ZTEproject'
$RemoteRunner = "$RemoteProjectDir/tools/zte-job.sh"
$PrivateKey = Join-Path $env:USERPROFILE '.ssh\codex_zte_automation_ed25519'
$Target = "$RemoteUser@$RemoteHostName"

$SshOptions = @(
    '-i', $PrivateKey,
    '-o', 'BatchMode=yes',
    '-o', 'IdentitiesOnly=yes',
    '-o', 'ConnectTimeout=10',
    '-o', 'ServerAliveInterval=30',
    '-o', 'ServerAliveCountMax=3',
    '-o', 'StrictHostKeyChecking=yes'
)

function Invoke-Native {
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter(Mandatory)] [string[]]$ArgumentList
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE."
    }
}

function Get-JobName {
    param([Parameter(Mandatory)] [string]$InputName)

    $name = [IO.Path]::GetFileNameWithoutExtension($InputName)
    if ($name -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
        throw "Invalid MATLAB job name '$name'. Use letters, digits, and underscores, starting with a letter."
    }
    return $name
}

function Install-Runner {
    $localRunner = Join-Path $PSScriptRoot 'zte-job.sh'
    if (-not (Test-Path -LiteralPath $localRunner -PathType Leaf)) {
        throw "Runner not found: $localRunner"
    }

    Invoke-Native -FilePath 'ssh' -ArgumentList ($SshOptions + @(
        $Target,
        "mkdir -p $RemoteProjectDir/tools"
    ))
    Invoke-Native -FilePath 'scp' -ArgumentList ($SshOptions + @(
        '-C',
        $localRunner,
        "${Target}:$RemoteRunner"
    ))
    Invoke-Native -FilePath 'ssh' -ArgumentList ($SshOptions + @(
        $Target,
        "chmod 700 $RemoteRunner && $RemoteRunner status"
    ))
}

if (-not (Test-Path -LiteralPath $PrivateKey -PathType Leaf)) {
    throw "SSH key not found: $PrivateKey. Run the one-time key setup before using this tool."
}

switch ($Action) {
    'install' {
        Install-Runner
    }
    'check' {
        Invoke-Native -FilePath 'ssh' -ArgumentList ($SshOptions + @(
            $Target,
            "printf 'SSH_OK\n'; test -x $RemoteRunner && printf 'RUNNER_OK\n'; test -x /home/jzm123/MATLAB/R2022b/bin/matlab && printf 'MATLAB_OK\n'; df -h $RemoteProjectDir | tail -n 1"
        ))
    }
    'run' {
        if ([string]::IsNullOrWhiteSpace($Job)) {
            throw 'run requires a local .m file or an existing remote job name.'
        }
        $jobName = Get-JobName $Job
        if (Test-Path -LiteralPath $Job -PathType Leaf) {
            $resolvedScript = (Resolve-Path -LiteralPath $Job).Path
            if ([IO.Path]::GetExtension($resolvedScript) -ne '.m') {
                throw "Only MATLAB .m scripts can be submitted: $resolvedScript"
            }
            Invoke-Native -FilePath 'scp' -ArgumentList ($SshOptions + @(
                '-C',
                $resolvedScript,
                "${Target}:$RemoteProjectDir/$jobName.m"
            ))
        }
        elseif ($Job -match '[\\/]') {
            throw "Local script not found: $Job"
        }

        Invoke-Native -FilePath 'ssh' -ArgumentList ($SshOptions + @(
            $Target,
            "$RemoteRunner start $jobName"
        ))
    }
    'status' {
        $remoteCommand = if ([string]::IsNullOrWhiteSpace($Job)) {
            "$RemoteRunner status"
        }
        else {
            "$RemoteRunner status $(Get-JobName $Job)"
        }
        Invoke-Native -FilePath 'ssh' -ArgumentList ($SshOptions + @($Target, $remoteCommand))
    }
    'tail' {
        if ([string]::IsNullOrWhiteSpace($Job)) {
            throw 'tail requires a job name.'
        }
        $jobName = Get-JobName $Job
        Invoke-Native -FilePath 'ssh' -ArgumentList ($SshOptions + @(
            $Target,
            "$RemoteRunner tail $jobName $Lines"
        ))
    }
    'fetch' {
        if ([string]::IsNullOrWhiteSpace($Job)) {
            throw 'fetch requires a job name.'
        }
        $jobName = Get-JobName $Job
        $bundleOutput = & ssh @SshOptions $Target "$RemoteRunner bundle $jobName"
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to bundle results for $jobName."
        }
        $remoteBundle = ($bundleOutput | Select-Object -Last 1).Trim()
        if ($remoteBundle -notmatch '^/home/jzm123/AAA_ZTEproject/\.jobs/[A-Za-z][A-Za-z0-9_]*-results\.tar\.gz$') {
            throw "Unexpected remote bundle path: $remoteBundle"
        }

        $resolvedOutputDir = [IO.Path]::GetFullPath($OutputDir)
        New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null
        $localBundle = Join-Path $resolvedOutputDir "$jobName-results.tar.gz"
        Invoke-Native -FilePath 'scp' -ArgumentList ($SshOptions + @(
            '-C',
            "${Target}:$remoteBundle",
            $localBundle
        ))
        Invoke-Native -FilePath 'tar' -ArgumentList @(
            '-xzf', $localBundle,
            '-C', $resolvedOutputDir
        )
        Write-Output "RESULTS=$resolvedOutputDir"
        Write-Output "ARCHIVE=$localBundle"
    }
    'cancel' {
        if ([string]::IsNullOrWhiteSpace($Job)) {
            throw 'cancel requires a job name.'
        }
        $jobName = Get-JobName $Job
        Invoke-Native -FilePath 'ssh' -ArgumentList ($SshOptions + @(
            $Target,
            "$RemoteRunner cancel $jobName"
        ))
    }
}
