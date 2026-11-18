param([ValidateSet('merge','render')][string]$Mode='merge', [string]$FinalFile)
$ErrorActionPreference='Stop'
$base=$PSScriptRoot
$build=Join-Path $base '.build-results-20261118'
$source=Join-Path $base 'deliverables/RIS_通感一体化_定位全流程.pptx'
$sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
$app=New-Object -ComObject PowerPoint.Application
$deck=$null
try {
    if($Mode -eq 'merge') {
        $candidate=Join-Path $build 'combined.candidate-v3.pptx'
        if(Test-Path -LiteralPath $candidate) { throw 'Candidate already exists. Use a new revision rather than overwrite.' }
        $deck=$app.Presentations.Open($source,-1,0,0)
        if($deck.Slides.Count -ne 11) { throw 'Unexpected source slide count.' }
        $deck.SaveAs($candidate,24)
        $inserted=$deck.Slides.InsertFromFile((Join-Path $build 'appendix.pptx'),11)
        if($inserted -ne 7 -or $deck.Slides.Count -ne 18) { throw 'Slide insertion did not match expected counts.' }
        $deck.Save()
        [PSCustomObject]@{Candidate=$candidate; Slides=$deck.Slides.Count; Inserted=$inserted} | ConvertTo-Json
    } else {
        if(-not $FinalFile) { throw 'FinalFile is required.' }
        $deck=$app.Presentations.Open($FinalFile,-1,0,0)
        $preview=Join-Path $build 'final'
        New-Item -ItemType Directory -Force -Path $preview | Out-Null
        $deck.Export($preview,'PNG',1280,720)
        $overflow=@()
        for($i=12;$i -le 18;$i++) {
            foreach($shape in $deck.Slides.Item($i).Shapes) {
                if($shape.HasTextFrame -eq -1 -and $shape.TextFrame2.HasText -eq -1) {
                    $height=$shape.TextFrame2.TextRange.BoundHeight
                    if($height -gt $shape.Height+2) { $overflow += [PSCustomObject]@{Slide=$i; Shape=$shape.Name; Height=$shape.Height; TextHeight=$height; Text=$shape.TextFrame2.TextRange.Text} }
                }
            }
        }
        $overflow | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $build 'text-overflow.json') -Encoding utf8
        [PSCustomObject]@{File=$FinalFile; Slides=$deck.Slides.Count; TextOverflowCount=$overflow.Count; Preview=$preview} | ConvertTo-Json
    }
} finally {
    if($deck) { $deck.Close() }
    if($app.Presentations.Count -eq 0) { $app.Quit() }
    if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $sourceHash) { throw 'Source deck unexpectedly changed.' }
}
