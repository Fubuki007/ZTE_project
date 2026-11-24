param(
    [string]$TargetPpt = ""
)
$ErrorActionPreference = "Stop"

$base = $PSScriptRoot
$build = Join-Path $base ".build-nlos-crb-20261124"
New-Item -ItemType Directory -Force -Path $build | Out-Null

if (-not $TargetPpt) {
    $TargetPpt = Join-Path $base "deliverables\RIS_通感一体化_定位全流程_结果补充_20261118_v4.pptx"
}
$appendix = Join-Path $build "appendix_nlos_crb.pptx"
if (-not (Test-Path -LiteralPath $TargetPpt)) { throw "Target PPT not found: $TargetPpt" }
if (-not (Test-Path -LiteralPath $appendix)) { throw "Appendix PPT not found: $appendix" }

$beforeDir = Join-Path $build "before"
$afterDir  = Join-Path $build "after"
$backupCopy = Join-Path $build "v4_before_20261124.pptx"
$candidate  = Join-Path $build "v4_merged_candidate.pptx"

# Preserve an untouched local snapshot of the 20-slide original before merging (only if not yet created)
if (-not (Test-Path -LiteralPath $backupCopy)) {
    Copy-Item -LiteralPath $TargetPpt -Destination $backupCopy -Force
}

# Always start merge cleanly from the untouched 20-slide snapshot so re-runs are idempotent!
$app = New-Object -ComObject PowerPoint.Application
$deck = $null
try {
    # 1. Render untouched 20-slide baseline if needed
    if (-not (Test-Path -LiteralPath (Join-Path $beforeDir "幻灯片1.PNG"))) {
        New-Item -ItemType Directory -Force -Path $beforeDir | Out-Null
        $deck = $app.Presentations.Open($backupCopy, -1, 0, 0)
        if ($deck.Slides.Count -ne 20) { throw "Expected 20 slides in baseline v4, got $($deck.Slides.Count)" }
        $deck.Export($beforeDir, "PNG", 1280, 720)
        $deck.Close()
        $deck = $null
    }

    # 2. Merge appendix (7 slides) after Slide 20 into candidate -> overwrite TargetPpt atomically
    if (Test-Path -LiteralPath $candidate) { Remove-Item -LiteralPath $candidate -Force }
    $deck = $app.Presentations.Open($backupCopy, -1, 0, 0)
    if ($deck.Slides.Count -ne 20) { throw "Unexpected baseline slide count: $($deck.Slides.Count)" }
    $deck.SaveAs($candidate, 24)
    $inserted = $deck.Slides.InsertFromFile($appendix, 20)
    if ($inserted -ne 7 -or $deck.Slides.Count -ne 27) {
        throw "InsertFromFile mismatch: inserted=$inserted total=$($deck.Slides.Count)"
    }
    $deck.Save()
    $deck.Close()
    $deck = $null

    Copy-Item -LiteralPath $candidate -Destination $TargetPpt -Force

    # 3. Re-open final TargetPpt, render all 27 slides, and measure exact BoundHeight overflow on Slides 21-27
    if (Test-Path -LiteralPath $afterDir) { Remove-Item -LiteralPath $afterDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $afterDir | Out-Null
    $deck = $app.Presentations.Open($TargetPpt, -1, 0, 0)
    $deck.Export($afterDir, "PNG", 1280, 720)

    $overflow = @()
    for ($i = 21; $i -le $deck.Slides.Count; $i++) {
        foreach ($shape in $deck.Slides.Item($i).Shapes) {
            if ($shape.HasTextFrame -eq -1 -and $shape.TextFrame2.HasText -eq -1) {
                $boundH = $shape.TextFrame2.TextRange.BoundHeight
                if ($boundH -gt ($shape.Height + 3.0)) {
                    $overflow += [PSCustomObject]@{
                        Slide = $i
                        Shape = $shape.Name
                        BoxHeightPt = [math]::Round($shape.Height, 2)
                        TextHeightPt = [math]::Round($boundH, 2)
                        Snippet = ($shape.TextFrame2.TextRange.Text -replace "\r|\n", " ").Substring(0, [math]::Min(60, $shape.TextFrame2.TextRange.Text.Length))
                    }
                }
            }
        }
    }
    $overflowPath = Join-Path $build "text_overflow_20261124.json"
    $overflow | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $overflowPath -Encoding utf8

    $sha = (Get-FileHash -LiteralPath $TargetPpt -Algorithm SHA256).Hash
    [PSCustomObject]@{
        TargetPpt = $TargetPpt
        Slides = $deck.Slides.Count
        Inserted = $inserted
        TextOverflowCount = $overflow.Count
        Sha256 = $sha
        AfterDir = $afterDir
    } | ConvertTo-Json
} finally {
    if ($deck) { $deck.Close() }
    if ($app.Presentations.Count -eq 0) { $app.Quit() }
}
