$ErrorActionPreference = 'Stop'

function RGB([int]$r, [int]$g, [int]$b) { return ($r + $g * 256 + $b * 65536) }

$navy   = RGB 18 53 91
$orange = RGB 232 117 26
$dark   = RGB 31 41 55
$gray   = RGB 107 114 128
$light  = RGB 247 249 252
$white  = RGB 255 255 255
$line   = RGB 209 213 219
$soft   = RGB 235 242 252
$green  = RGB 22 128 61

function Add-Rect {
    param($slide, [double]$left, [double]$top, [double]$width, [double]$height, [int]$fill, [int]$shape = 1, [int]$lineColor = -1)
    $sh = $slide.Shapes.AddShape($shape, $left, $top, $width, $height)
    $sh.Fill.ForeColor.RGB = $fill
    if ($lineColor -ge 0) {
        $sh.Line.ForeColor.RGB = $lineColor
        $sh.Line.Weight = 0.75
    } else {
        $sh.Line.Visible = 0
    }
}

function Add-TextBox {
    param(
        $slide,
        [string]$text,
        [double]$left,
        [double]$top,
        [double]$width,
        [double]$height,
        [double]$size,
        [bool]$bold = $false,
        [int]$color = 0,
        [int]$align = 1,
        [string]$font = 'Microsoft YaHei'
    )
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

function New-Slide {
    param([string]$title)
    $slide = $pres.Slides.Add($pres.Slides.Count + 1, 12)
    Add-Rect $slide 0 0 960 540 $light
    Add-Rect $slide 0 0 960 62 $navy
    Add-Rect $slide 0 62 960 4 $orange
    Add-TextBox $slide $title 40 10 880 42 24 $true $white 1
    $num = [string]$pres.Slides.Count
    Add-TextBox $slide 'RIS 抑制全双工自干扰 | 单篇论文研读：Wu 2023 TWC' 40 508 690 20 10 $false $gray 1
    Add-TextBox $slide $num 895 508 30 20 10 $false $gray 3
    return $slide
}

function Set-Notes {
    param($slide, [string]$text)
    $slide.NotesPage.Shapes.Placeholders.Item(2).TextFrame.TextRange.Text = $text
}

# ================= PowerPoint 初始化 =================
$ppt = New-Object -ComObject PowerPoint.Application
$pres = $ppt.Presentations.Add()
$pres.PageSetup.SlideWidth = 960
$pres.PageSetup.SlideHeight = 540

# ================= 1. 封面 =================
$cover = $pres.Slides.Add(1, 12)
Add-Rect $cover 0 0 960 540 $navy
Add-Rect $cover 80 315 800 3 $orange
Add-TextBox $cover 'RIS 抑制全双工自干扰' 80 170 800 70 34 $true $white 2
Add-TextBox $cover '单篇重点论文研读' 80 250 800 50 22 $false $white 2
Add-TextBox $cover 'Wu et al., IEEE TWC 2023/2024：RIS-Based SIC for Full-Duplex Broadband Transmission' 80 375 800 46 16 $false (RGB 201 219 242) 2
Add-TextBox $cover '汇报人：________    日期：2026-09-17' 80 450 800 28 14 $false (RGB 201 219 242) 2
Set-Notes $cover '封面。今天只讲一篇最相关的论文：Wu 等 2023/2024 年 IEEE TWC 的 RIS-Based Self-Interference Cancellation for Full-Duplex Broadband Transmission。'

# ================= 2. 为什么选这篇 =================
$s = New-Slide '为什么选这篇论文'
$body = @(
    '• 论文：RIS-Based Self-Interference Cancellation for Full-Duplex Broadband Transmission',
    '• 作者：Jiayan Wu, Wenchi Cheng, Jianyu Wang, Jingqing Wang, Wei Zhang',
    '• 期刊：IEEE Transactions on Wireless Communications, 2023/2024',
    '• DOI：10.1109/TWC.2023.3337787',
    '',
    '• 选择理由：它和我现有代码最接近',
    '• 近场 RIS：我的 H_SI 也是近场 Rician 模型',
    '• 宽带信道：我的系统是 OFDM 聚合宽带',
    '• 优化变量：RIS 反射系数 + 发射功率，正好对应我的 θ 和 W',
    '• 算法落地：AO、KKT、RCG、NPP，可直接迁移到 design_precoder.m'
) -join "`r"
Add-TextBox $s $body 50 92 860 380 15 $false $dark 1
Set-Notes $s '这篇论文和现有代码最接近：近场、宽带、RIS 反射系数和发射功率联合优化。今天重点讲它的问题、方法、结论，以及能不能落到我们的代码里。'

# ================= 3. 背景与问题 =================
$s = New-Slide '研究背景与问题'
Add-Rect $s 40 92 880 96 $soft 5
Add-TextBox $s '全双工同时同频收发 → 发射信号直接泄漏到本地接收机 → 强 SI' 60 108 840 28 17 $true $navy 1
Add-TextBox $s 'SI 会压缩 ADC 动态范围，严重时淹没远端有用信号和目标回波。' 60 142 840 28 15 $false $dark 1
$body = @(
    '• 传统做法：模拟 SIC + 数字 SIC，但强 SI 对 ADC 和射频前端要求很高',
    '• 这篇论文的想法：在 FD 设备内部署小型 RIS，用可控反射增强 SIC',
    '• 三个关键挑战：',
    '    1）RIS 在设备内部，是近场，不是远场，不能直接用平面波近似',
    '    2）信道是频率选择性宽带，不是单频窄带',
    '    3）RIS 硬件可能只能调相位，甚至只能取离散相位'
) -join "`r"
Add-TextBox $s $body 40 210 880 240 15 $false $dark 1
Add-Rect $s 40 466 880 44 (RGB 255 244 235) 5
Add-TextBox $s '论文目标：联合优化 RIS 反射系数和发射功率，最大化 SIC 能力。' 60 474 840 28 15 $true $orange 1
Set-Notes $s '先讲问题：全双工 SI 会压缩 ADC 动态范围。这篇论文考虑的是 FD 设备内部的小 RIS，近场、宽带、硬件受限，目标是在这些条件下最大化 SIC 能力。'

# ================= 4. 核心模型 =================
$s = New-Slide '论文核心模型'
$body = @(
    '• 场景：FD 设备内部署小型 RIS，RIS 靠近发射和接收阵列',
    '• SI 信道 = 直接耦合路径 + RIS 反射路径',
    '• RIS 每个单元有一个可调反射系数：幅度和/或相位',
    '• 信道具有频率选择性，每个子载波上的等效 SI 信道不同',
    '• 发射端还有发射功率分配变量',
    '',
    '• 论文把问题抽象为：',
    '    给定近场宽带 SI 信道，优化 RIS 反射系数和发射功率，使残余 SI 最小'
) -join "`r"
Add-TextBox $s $body 50 96 860 250 15 $false $dark 1
Add-Rect $s 50 350 860 120 $white 5 $line
Add-TextBox $s '可以类比到我的代码：' 70 366 820 26 17 $true $navy 1
Add-TextBox $s 'H_SI 不再是固定矩阵，而是与 RIS 相位 θ 相关的 H_SI(θ)；' 70 398 820 26 14 $false $dark 1
Add-TextBox $s '预编码 W 与 RIS 相位 θ 需要联合/交替优化。' 70 428 820 26 14 $false $dark 1
Set-Notes $s '模型核心：近场、宽带、RIS 反射系数可调，同时发射功率也可以分配。对我们的映射就是 H_SI 变成 H_SI(θ)，W 和 θ 联合优化。'

# ================= 5. 优化问题与 AO =================
$s = New-Slide '优化问题与交替优化'
$body = @(
    '• 目标：最大化 SIC 能力，或等价地最小化残余 SI',
    '• 变量：RIS 反射系数、发射功率',
    '• 约束：RIS 硬件约束（理想/连续/离散）、发射功率约束',
    '• 难点：RIS 反射系数和发射功率耦合，问题非凸',
    '• 求解：交替优化（AO）',
    '    固定 RIS 反射系数 → 优化发射功率',
    '    固定发射功率 → 优化 RIS 反射系数',
    '    反复迭代直到收敛'
) -join "`r"
Add-TextBox $s $body 50 96 860 330 16 $false $dark 1
Add-Rect $s 50 444 860 48 $soft 5
Add-TextBox $s '对我的价值：我可以把目标函数换成 SI 泄漏 + CRB/RMSE 约束，继续用 AO 扩展。' 70 456 820 28 15 $true $navy 1
Set-Notes $s '方法核心是 AO：固定一边优化另一边。难点是非凸。对我们的价值是，我们可以把目标函数改成 SI 泄漏加 CRB/RMSE，继续沿用 AO。'

# ================= 6. 三种硬件情况 =================
$s = New-Slide '三种 RIS 硬件情况与算法'
Add-Rect $s 40 100 280 230 $white 5 $line
Add-TextBox $s '① 理想情况' 60 118 240 28 18 $true $navy 1
Add-TextBox $s '幅度和相位连续可调。利用 KKT 条件得到闭式解。' 60 158 240 130 14 $false $dark 1
Add-Rect $s 340 100 280 230 $white 5 $line
Add-TextBox $s '② 连续相位' 360 118 240 28 18 $true $navy 1
Add-TextBox $s '幅度固定为 1，只能调相位。用黎曼共轭梯度（RCG）优化。' 360 158 240 130 14 $false $dark 1
Add-Rect $s 640 100 280 230 $white 5 $line
Add-TextBox $s '③ 离散相位' 660 118 240 28 18 $true $navy 1
Add-TextBox $s '相位只能取离散值。先用连续解，再用最近点投影（NPP）。' 660 158 240 130 14 $false $dark 1
Add-Rect $s 40 360 880 132 $soft 5
Add-TextBox $s '这三种情况几乎覆盖了实际 RIS 硬件：' 60 376 840 26 16 $true $navy 1
Add-TextBox $s '理想 → 理论性能上界；连续相位 → 常见无源 RIS；离散相位 → 低成本/1-bit RIS。' 60 410 840 26 14 $false $dark 1
Add-TextBox $s '如果我们后续做 RIS 硬件方案，可以根据控制精度直接选对应算法。' 60 440 840 26 14 $false $dark 1
Set-Notes $s '三种硬件情况分别对应理论、连续相位和离散相位。RCG 和 NPP 不需要记公式，只要知道它们分别解决什么约束下的优化。'

# ================= 7. 论文结论 =================
$s = New-Slide '论文结论与效果'
$body = @(
    '• 仿真结果验证：该 RIS 辅助 SIC 方案能有效增强 FD 设备的自干扰消除能力',
    '• 方案同时适用于理想、连续相位和离散相位三种硬件情况',
    '• 论文还表明该方案不仅改善 SIC，还能提升系统整体性能',
    '• 注意：论文主要是算法与仿真验证，不是硬件实测',
    '• 因此它的价值在于：给出一套可迁移的近场宽带 RIS-SIC 优化框架'
) -join "`r"
Add-TextBox $s $body 50 110 860 260 16 $false $dark 1
Add-Rect $s 50 390 860 102 $soft 5
Add-TextBox $s '和我现有代码的关系：' 70 406 820 26 17 $true $navy 1
Add-TextBox $s '它解决的是“H_SI 与 RIS 相位联合优化”的问题；' 70 440 820 26 14 $false $dark 1
Add-TextBox $s '我现有代码解决的是“给定 H_SI 下的预编码 + 数字 SIC + 参数估计”。两者正好互补。' 70 470 820 26 14 $false $dark 1
Set-Notes $s '论文主要是仿真结论，不是硬件实测。它的最大价值是提供可迁移的算法框架：近场宽带 RIS-SIC 联合优化。'

# ================= 8. 可行性分析 =================
$s = New-Slide '对我的项目：可行性分析'
Add-Rect $s 40 90 430 340 $white 5 $line
Add-TextBox $s '可直接落地' 60 108 390 30 19 $true $green 1
$left = @(
    '• generate_HSI.m 旁新增 generate_H_RIS.m',
    '• H_SI(θ) = H_direct + H_RIS(θ)',
    '• design_precoder.m 中 W 与 θ 交替优化',
    '• 支持理想/连续/离散相位三种硬件模型',
    '• 纯算法与仿真，改动集中在 H_SI 和优化器'
) -join "`r"
Add-TextBox $s $left 60 150 390 260 14 $false $dark 1
Add-Rect $s 490 90 430 340 $white 5 $line
Add-TextBox $s '主要挑战' 510 108 390 30 19 $true $orange 1
$right = @(
    '• 我的系统是 28 GHz、1.5 GHz 聚合带宽',
    '• RIS 相位在整个宽带内可能不一致',
    '• 离散相位量化会带来性能损失',
    '• 需要 RIS 近场信道与 SI 信道估计',
    '• 计算复杂度比现有预编码更高'
) -join "`r"
Add-TextBox $s $right 510 150 390 260 14 $false $dark 1
Add-Rect $s 40 450 880 58 $soft 5
Add-TextBox $s '综合判断：仿真可行性高，建议先做中心子载波，再扩展到多子载波/子带。' 60 464 840 30 15 $true $navy 1
Set-Notes $s '落地可行性高，主要在仿真与算法；最大挑战是 1.5 GHz 宽带。建议先中心子载波验证，再扩展到多子载波。'

# ================= 9. 下一步计划 =================
$s = New-Slide '下一步验证计划'
$cards = @(
    @{x=40;  t='第 1 步：单频验证'; d='单子载波 RIS 反相消 SI，扫幅度比 ρ 和相位 θ，先回答“能压多少 dB”'},
    @{x=340; t='第 2 步：联合优化'; d='用 AO 联合优化 W 与 θ，与 ZF/nullspace/Lagrange/SIC 对比，看 SINR 和 RMSE'},
    @{x=640; t='第 3 步：宽带扩展'; d='多子载波 OFDM，评估 1.5 GHz 带宽；必要时子带 RIS / 延时 RIS'}
)
foreach ($c in $cards) {
    Add-Rect $s $c.x 110 280 300 $white 5 $line
    Add-Rect $s $c.x 110 280 8 $orange 1
    Add-TextBox $s $c.t ($c.x+22) 132 240 34 18 $true $navy 1
    Add-TextBox $s $c.d ($c.x+22) 180 240 180 15 $false $dark 1
}
Add-Rect $s 40 450 880 58 $soft 5
Add-TextBox $s '预期：中心频点增益明显；1.5 GHz 宽带下增益下降，需要子带或延时 RIS 方案。' 60 464 840 30 15 $true $navy 1
Set-Notes $s '下一步三步：单频验证、联合优化、宽带扩展。先做最小闭环，不要一上来就做全带宽。'

# ================= 10. 总结 =================
$s = New-Slide '总结'
$body = @(
    '• 这篇论文最接近我的代码：近场 + 宽带 + RIS 反射系数/功率联合优化',
    '• 它的核心贡献是给出一套可迁移的 RIS-SIC 优化框架',
    '• 三种硬件情况（理想、连续相位、离散相位）都有对应算法',
    '• 我的项目关键难点不是“能不能压 SI”，而是“1.5 GHz 宽带下能不能保持增益”',
    '• 下一步：先做单子载波 RIS 反相消 SI 仿真，再扩展到多子载波'
) -join "`r"
Add-TextBox $s $body 50 104 860 220 16 $false $dark 1
Add-Rect $s 50 350 860 110 $white 5 $line
Add-TextBox $s '参考文献' 70 364 820 26 16 $true $navy 1
Add-TextBox $s 'J. Wu et al., RIS-Based Self-Interference Cancellation for Full-Duplex Broadband Transmission, IEEE TWC, 2023/2024. DOI: 10.1109/TWC.2023.3337787' 70 396 820 50 12 $false $dark 1
Add-TextBox $s '谢谢！请老师批评指正。' 50 480 860 32 20 $true $orange 2
Set-Notes $s '总结：选这篇是因为它最接近现有代码；下一步先做单子载波仿真，再扩多子载波。请老师批评指正。'

# ================= 保存 =================
$outDir = 'D:\AA 学习项目\AAA 智能反射面辅助通信感知\AAA ZTE_project\RIS_SI_单篇汇报_Wu2023_20260917'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outPath = Join-Path $outDir 'RIS抑制全双工自干扰_单篇论文汇报_Wu2023.pptx'
$pres.SaveAs($outPath)
$pdfPath = Join-Path $outDir 'RIS抑制全双工自干扰_单篇论文汇报_Wu2023.pdf'
$pres.SaveAs($pdfPath, 32)
$pres.Close()
$ppt.Quit()
Write-Output "PPT saved: $outPath"
Write-Output "PDF saved: $pdfPath"
