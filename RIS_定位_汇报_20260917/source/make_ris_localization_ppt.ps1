$ErrorActionPreference = 'Stop'
function RGB([int]$r, [int]$g, [int]$b) { return ($r + $g * 256 + $b * 65536) }
$navy = RGB 18 53 91
$orange = RGB 232 117 26
$dark = RGB 31 41 55
$gray = RGB 107 114 128
$light = RGB 247 249 252
$white = RGB 255 255 255
$line = RGB 209 213 219
$soft = RGB 235 242 252
$green = RGB 22 128 61
$blue = RGB 31 111 235
function Add-Rect {
    param($slide, [double]$left, [double]$top, [double]$width, [double]$height, [int]$fill, [int]$shape = 1, [int]$lineColor = -1)
    $sh = $slide.Shapes.AddShape($shape, $left, $top, $width, $height)
    $sh.Fill.ForeColor.RGB = $fill
    if ($lineColor -ge 0) { $sh.Line.ForeColor.RGB = $lineColor; $sh.Line.Weight = 0.75 } else { $sh.Line.Visible = 0 }
}
function Add-TextBox {
    param($slide, [string]$text, [double]$left, [double]$top, [double]$width, [double]$height,
        [double]$size, [bool]$bold = $false, [int]$color = 0, [int]$align = 1, [string]$font = 'Microsoft YaHei')
    $sh = $slide.Shapes.AddTextbox(1, $left, $top, $width, $height)
    $tr = $sh.TextFrame.TextRange
    $tr.Text = $text
    $tr.Font.Name = $font
    $tr.Font.NameFarEast = $font
    $tr.Font.Size = $size
    $tr.Font.Bold = $bold
    $tr.Font.Color.RGB = $color
    $tr.ParagraphFormat.Alignment = $align
    $tr.ParagraphFormat.SpaceAfter = 4
    $tr.ParagraphFormat.SpaceWithin = 1.03
    $sh.TextFrame.WordWrap = -1
    $sh.TextFrame.AutoSize = 0
}
function Add-Picture {
    param($slide, [string]$path, [double]$left, [double]$top, [double]$boxW, [double]$boxH)
    Add-Type -AssemblyName System.Drawing
    $img = [System.Drawing.Image]::FromFile($path)
    $iw = $img.Width; $ih = $img.Height; $img.Dispose()
    $scale = [Math]::Min($boxW / $iw, $boxH / $ih)
    $w = $iw * $scale; $h = $ih * $scale
    $x = $left + ($boxW - $w) / 2; $y = $top + ($boxH - $h) / 2
    $sh = $slide.Shapes.AddPicture($path, 0, -1, $x, $y, $w, $h)
    $sh.Line.Visible = 0
}
function New-Slide {
    param([string]$title)
    $slide = $pres.Slides.Add($pres.Slides.Count + 1, 12)
    Add-Rect $slide 0 0 960 540 $light
    Add-Rect $slide 0 0 960 62 $navy
    Add-Rect $slide 0 62 960 4 $orange
    Add-TextBox $slide $title 40 10 880 42 24 $true $white 1
    $num = [string]$pres.Slides.Count
    Add-TextBox $slide 'RIS 辅助定位：通俗解释与系统关系' 40 508 680 20 10 $false $gray 1
    Add-TextBox $slide $num 895 508 30 20 10 $false $gray 3
    return $slide
}
function Set-Notes { param($slide, [string]$text) $slide.NotesPage.Shapes.Placeholders.Item(2).TextFrame.TextRange.Text = $text }
$ppt = New-Object -ComObject PowerPoint.Application
$pres = $ppt.Presentations.Add()
$pres.PageSetup.SlideWidth = 960
$pres.PageSetup.SlideHeight = 540
# test
$s = $pres.Slides.Add(1, 12)
Add-Rect $s 0 0 960 540 $navy
Add-Rect $s 80 315 800 3 $orange
Add-TextBox $s 'RIS 辅助定位：把复杂问题讲简单' 80 150 800 70 32 $true $white 2
Add-TextBox $s '基站、RIS、用户/目标的关系与定位原理' 80 245 800 46 20 $false $white 2
Add-TextBox $s '汇报人：________    日期：2026-09-17' 80 430 800 28 14 $false (RGB 201 219 242) 2
Set-Notes $s '封面。今天用最直白的话讲清楚 RIS 辅助定位，以及基站、RIS、用户/目标之间的关系。'
$s = New-Slide '一句话讲清 RIS 辅助定位'
Add-Rect $s 40 96 880 92 $soft 5
Add-TextBox $s 'RIS 是一面位置已知、可以编程的镜子。' 60 112 840 34 20 $true $navy 1
Add-TextBox $s '它不主动发信号，也不主动测距；它负责把基站信号按可控方向反射到目标/用户。' 60 150 840 30 15 $false $dark 1
$body = @('• test bullet') -join [char]13
$body = @()
$body += '• 基站位置已知，RIS 位置和朝向通常已知'
$body += '• 用户或目标的位置未知，是需要被定位的对象'
$body += '• 信号走 基站 到 RIS 再到用户/目标 的反射路径'
$body += '• 接收端测量这条路径的时延、角度、多普勒，反推出位置'
Add-TextBox $s $body 60 220 860 220 16 $false $dark 1
Add-Rect $s 40 454 880 52 (RGB 255 244 235) 5
Add-TextBox $s '关键：RIS 自己通常不需要被定位，它的位置是已知锚点。' 60 466 840 30 15 $true $orange 1
Set-Notes $s '核心一句话：RIS 是位置已知的可编程镜子，它不主动测量，只负责反射。被定位的是用户/目标，不是 RIS 自己。'
$s = New-Slide '先分清两件事'
Add-Rect $s 40 96 430 350 $white 5 $line
Add-TextBox $s 'RIS 自己的位置' 60 112 390 30 19 $true $green 1
$left = @(
'• 固定安装：安装时用测量、图纸、BIM 标定'
'• 位置和朝向都已知，之后当成锚点'
'• RIS 是无源器件，不能主动报告我在哪'
'• 如果是无人机或车载移动 RIS：'
'    - 用 GPS/IMU 提供粗位置和姿态'
'    - 或与用户位置一起联合估计'
'    - 或利用已知基站做在线标定'
) -join [char]13
Add-TextBox $s $left 60 152 390 280 14 $false $dark 1
Add-Rect $s 490 96 430 350 $white 5 $line
Add-TextBox $s '被定位目标/用户的位置' 510 112 390 30 19 $true $orange 1
$right = @(
'• 基站位置已知'
'• RIS 位置和朝向已知'
'• 目标/用户位置未知'
'• 通过基站到 RIS 到目标的反射路径来定位'
'• 测量量：'
'    - 时延，给出距离信息'
'    - 到达角或离开角，给出方向信息'
'    - 多普勒，给出运动速度信息'
) -join [char]13
Add-TextBox $s $right 510 152 390 280 14 $false $dark 1
Set-Notes $s '先区分两个概念：RIS 自己的位置一般是已知锚点；真正要定位的是用户/目标。只有移动 RIS 才需要估计 RIS 自身位置。'
$s = New-Slide '生活中的比喻：黑屋、手电筒和镜子'
$body = @(
'• 你在黑屋里想找一个人'
'• 你有一支手电筒，墙上有一面位置已知的镜子'
'• 你用手电筒照镜子，镜子把光反射到那个人身上'
'• 你通过两件事判断人在哪：'
''
'    1）光绕了多久，说明人离镜子有多远'
'    2）光从哪个方向回来，说明人在镜子的哪个方向'
''
'• 距离给出一个可能的圈，方向给出一条可能的线'
'• 圈和线相交，位置就确定了'
) -join [char]13
Add-TextBox $s $body 50 92 860 350 16 $false $dark 1
Add-Rect $s 50 456 860 50 $soft 5
Add-TextBox $s 'RIS 辅助定位，本质就是这个过程。' 70 468 820 28 16 $true $navy 1
Set-Notes $s '用生活比喻讲：手电筒是基站，镜子是 RIS，人是目标。时延给距离，方向给角度，圈和线相交就是位置。'
$s = New-Slide '系统关系图：基站、RIS、用户/目标'
$pic1 = 'D:\AA 学习项目\AAA 智能反射面辅助通信感知\AAA ZTE_project\RIS_定位_汇报_20260917\ris_system_relation.png'
Add-Picture $s $pic1 40 90 880 300
Add-Rect $s 40 408 880 100 $soft 5
Add-TextBox $s '• 基站 BS：已知位置，负责发射信号' 60 422 840 26 14 $false $dark 1
Add-TextBox $s '• RIS：已知位置和朝向，像可控镜子，把信号反射到目标/用户' 60 450 840 26 14 $false $dark 1
Add-TextBox $s '• 用户/目标：未知位置，是定位对象；直射路径可能被遮挡，RIS 提供虚拟视距' 60 478 840 26 14 $false $dark 1
Set-Notes $s '这张图表示基站、RIS、用户/目标的关系。直射路径可能被遮挡，RIS 提供可控反射路径。RIS 位置已知，用户位置未知。'
$s = New-Slide '定位原理：距离圈加方向线'
$pic2 = 'D:\AA 学习项目\AAA 智能反射面辅助通信感知\AAA ZTE_project\RIS_定位_汇报_20260917\ris_positioning_principle.png'
Add-Picture $s $pic2 40 90 420 350
Add-Rect $s 490 102 430 220 $white 5 $line
Add-TextBox $s '怎么理解？' 510 118 390 30 18 $true $navy 1
$body = @(
'• RIS 到目标的距离，给一个距离圈'
'• RIS 到目标的方向，给一条方向射线'
'• 两者相交，就确定目标位置'
''
'• 距离来自信号时延'
'• 方向来自 RIS 阵列的相位或波束扫描'
'• 只能测方向，就是远场定位'
'• 还能测距离，就是近场定位'
) -join [char]13
Add-TextBox $s $body 510 152 390 170 14 $false $dark 1
Add-Rect $s 490 342 430 160 $soft 5
Add-TextBox $s '一句话：' 510 356 390 26 16 $true $navy 1
Add-TextBox $s 'RIS 把测距和测角结合起来，就能定出目标位置。' 510 386 390 48 14 $false $dark 1
Add-TextBox $s '多个 RIS 就相当于多面镜子，给出多个圈，交点唯一。' 510 438 390 48 14 $false $dark 1
Set-Notes $s '定位原理就是距离圈和方向线相交。距离来自时延，方向来自 RIS 阵列。一个 RIS 有模糊，多个 RIS 或多测几次可以解模糊。'
$s = New-Slide '为什么一个 RIS 往往不够？'
$body = @(
'• 单次测量可能有两个对称位置都满足条件，这叫镜像模糊'
'• 例如只知道目标在 RIS 右边 20 米，但可能在右上或右下'
'• 解决办法：'
''
'    1）多放几个 RIS，每个 RIS 给一个距离圈'
'    2）基站或用户移动，多测几次'
'    3）利用目标运动过程中的连续测量'
'    4）利用多个天线、多个子载波提供更多信息'
''
'• 这就像用多面镜子交叉定位：镜子越多，位置越唯一'
) -join [char]13
Add-TextBox $s $body 50 96 860 350 16 $false $dark 1
Add-Rect $s 50 456 860 50 (RGB 255 244 235) 5
Add-TextBox $s '核心：一个 RIS 可能不够，多 RIS 或多测量才能解模糊、提精度。' 70 468 820 28 16 $true $orange 1
Set-Notes $s '解释为什么一个 RIS 不够：单次测量有镜像模糊。多 RIS、多测量、运动信息可以解模糊。'
$s = New-Slide '远场和近场，用大白话说'
Add-Rect $s 40 100 430 320 $white 5 $line
Add-TextBox $s '远场' 60 118 390 32 20 $true $blue 1
$left = @(
'• RIS 离目标很远'
'• RIS 看目标，就像你看远处的星星'
'• 只能判断在哪个方向'
'• 很难判断具体多远'
'• 远场主要靠角度定位'
) -join [char]13
Add-TextBox $s $left 60 160 390 230 15 $false $dark 1
Add-Rect $s 490 100 430 320 $white 5 $line
Add-TextBox $s '近场' 510 118 390 32 20 $true $green 1
$right = @(
'• RIS 很大，目标离 RIS 很近'
'• RIS 不同部位看到的距离不一样'
'• 就像两只眼睛看近处物体'
'• 除了方向，还能判断远近'
'• 大 RIS 近场可以同时测角度和距离'
) -join [char]13
Add-TextBox $s $right 510 160 390 230 15 $false $dark 1
Add-Rect $s 40 446 880 58 $soft 5
Add-TextBox $s '所以：大 RIS 加近场，是 RIS 定位里提升精度的重要方向。' 60 460 840 30 16 $true $navy 1
Set-Notes $s '用简单类比解释远场和近场：远场像看星星，只知道方向；近场像两只眼睛看近处，能判断距离和方向。'
$s = New-Slide 'RIS 自定位和 RIS 辅助定位'
Add-Rect $s 40 100 430 330 $white 5 $line
Add-TextBox $s 'RIS 辅助定位' 60 118 390 32 19 $true $navy 1
$left = @(
'• 基站或网络侧负责接收'
'• 基站通过 RIS 反射路径定位用户或目标'
'• RIS 位置已知，作为锚点'
'• 适合蜂窝网、ISAC 感知场景'
''
'• 例：基站到 RIS 到目标，接收回波或用户信号'
) -join [char]13
Add-TextBox $s $left 60 160 390 240 14 $false $dark 1
Add-Rect $s 490 100 430 330 $white 5 $line
Add-TextBox $s 'RIS 自定位' 510 118 390 32 19 $true $orange 1
$right = @(
'• 用户设备自己接收 RIS 反射信号'
'• 周围可能没有基站，RIS 充当已知锚点'
'• 用户根据反射路径判断我在哪'
'• 适合室内、无 GPS、零接入点场景'
''
'• 例：Keykhosravi 2022 的 RIS self-localization'
) -join [char]13
Add-TextBox $s $right 510 160 390 240 14 $false $dark 1
Add-Rect $s 40 456 880 50 $soft 5
Add-TextBox $s '共同点：RIS 位置都当作已知锚点；区别只在谁接收、谁定位。' 60 468 840 28 16 $true $navy 1
Set-Notes $s '区分两种场景：基站接收并定位用户叫 RIS 辅助定位；用户自己接收并定位自己叫 RIS 自定位。共同点是 RIS 位置都是已知锚点。'
$s = New-Slide '可以直接对老师说的总结'
Add-Rect $s 40 92 880 340 $white 5 $line
$body = @(
'老师，RIS 辅助定位可以这样理解：'
''
'RIS 本身位置已知，是一面可编程的镜子，也是定位的锚点。'
'基站发出信号，经 RIS 反射到目标或用户；接收端测量这条反射路径的时延和方向。'
'时延告诉我们目标离 RIS 有多远，方向告诉我们目标在 RIS 的哪个方向。'
'距离给出一个圈，方向给出一条线，圈和线相交，就确定目标位置。'
''
'一个 RIS 可能有模糊，多个 RIS 或多次测量可以解决。'
'如果 RIS 是移动的，才需要 GPS 或和用户位置联合估计。'
) -join [char]13
Add-TextBox $s $body 70 112 820 300 16 $false $dark 1
Add-TextBox $s '结论：RIS 自己通常不参与被定位，它是位置已知的可控反射锚点；被定位的是用户或目标。' 50 452 860 38 16 $true $orange 1
Set-Notes $s '这是可以直接对老师说的总结版。重点：RIS 自己不是被定位对象，而是已知锚点；通过反射路径的时延和方向定位用户/目标。'
$outDir = 'D:\AA 学习项目\AAA 智能反射面辅助通信感知\AAA ZTE_project\RIS_定位_汇报_20260917'
$outPath = Join-Path $outDir 'RIS辅助定位_通俗汇报.pptx'
$pres.SaveAs($outPath)
$pdfPath = Join-Path $outDir 'RIS辅助定位_通俗汇报.pdf'
$pres.SaveAs($pdfPath, 32)
$pres.Close()
$ppt.Quit()
Write-Output "PPT saved: $outPath"
Write-Output "PDF saved: $pdfPath"
