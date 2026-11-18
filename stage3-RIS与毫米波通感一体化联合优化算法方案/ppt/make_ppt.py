# -*- coding: utf-8 -*-
from pathlib import Path
from PIL import Image
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR, MSO_AUTO_SIZE
from pptx.enum.shapes import MSO_SHAPE, MSO_CONNECTOR
from pptx.oxml.ns import qn
from pptx.oxml.xmlchemy import OxmlElement

BASE = Path(r"D:\AA 学习项目\AAA 智能反射面辅助通信感知\AAA ZTE_project\stage3-RIS与毫米波通感一体化联合优化算法方案")
OUT = BASE / "ppt"
FIG = OUT / "figures"
DELIV = OUT / "deliverables"
DELIV.mkdir(parents=True, exist_ok=True)

NAVY = RGBColor(0x0B, 0x1F, 0x3A)
NAVY2 = RGBColor(0x12, 0x35, 0x5A)
INK = RGBColor(0x0F, 0x17, 0x2A)
SLATE = RGBColor(0x47, 0x55, 0x69)
MUTED = RGBColor(0x64, 0x74, 0x8B)
TEAL = RGBColor(0x0E, 0x8F, 0x8F)
TEAL_DARK = RGBColor(0x0A, 0x6B, 0x6B)
CYAN = RGBColor(0x22, 0xB8, 0xCF)
ORANGE = RGBColor(0xF5, 0x9E, 0x0B)
ROSE = RGBColor(0xE8, 0x5D, 0x75)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
OFFWHITE = RGBColor(0xF8, 0xFA, 0xFC)
SOFT = RGBColor(0xF1, 0xF5, 0xF9)
PALETEAL = RGBColor(0xE6, 0xFF, 0xFB)
PALEORANGE = RGBColor(0xFF, 0xF7, 0xE8)
PALEBLUE = RGBColor(0xEF, 0xF8, 0xFF)
BORDER = RGBColor(0xE2, 0xE8, 0xF0)
FONT = "Microsoft YaHei"

prs = Presentation()
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)
prs.core_properties.title = "RIS 辅助毫米波通感一体化：目标定位全流程"
prs.core_properties.subject = "Stage-3 RIS / mmWave joint communication and sensing localization pipeline"
prs.core_properties.author = "Code analysis deck"
BLANK = prs.slide_layouts[6]

def set_bg(slide, color):
    fill = slide.background.fill
    fill.solid()
    fill.fore_color.rgb = color

def set_run_font(run, size=16, color=INK, bold=False, font=FONT, italic=False):
    run.font.name = font
    run.font.size = Pt(size)
    run.font.bold = bold
    run.font.italic = italic
    run.font.color.rgb = color
    rPr = run._r.get_or_add_rPr()
    ea = rPr.find(qn('a:ea'))
    if ea is None:
        ea = OxmlElement('a:ea'); rPr.append(ea)
    ea.set('typeface', font)
    cs = rPr.find(qn('a:cs'))
    if cs is None:
        cs = OxmlElement('a:cs'); rPr.append(cs)
    cs.set('typeface', font)

def add_text(slide, x, y, w, h, text, size=16, color=INK, bold=False,
             align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP, line_spacing=1.05,
             font=FONT, margins=(0,0,0,0), italic=False):
    tb = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = tb.text_frame
    tf.word_wrap = True
    tf.auto_size = MSO_AUTO_SIZE.NONE
    tf.margin_left = Inches(margins[0]); tf.margin_right = Inches(margins[1])
    tf.margin_top = Inches(margins[2]); tf.margin_bottom = Inches(margins[3])
    tf.vertical_anchor = anchor
    lines = str(text).split("\n")
    for i, line in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        p.line_spacing = line_spacing
        p.space_before = Pt(0); p.space_after = Pt(0)
        r = p.add_run(); r.text = line
        set_run_font(r, size, color, bold, font, italic)
    return tb

def add_bullets(slide, x, y, w, h, items, size=15, color=INK, bullet_color=TEAL,
                spacing=7, line_spacing=1.05):
    tb = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = tb.text_frame
    tf.word_wrap = True
    tf.auto_size = MSO_AUTO_SIZE.NONE
    tf.margin_left = 0; tf.margin_right = 0; tf.margin_top = 0; tf.margin_bottom = 0
    for i, item in enumerate(items):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = PP_ALIGN.LEFT
        p.line_spacing = line_spacing
        p.space_before = Pt(0); p.space_after = Pt(spacing)
        pPr = p._p.get_or_add_pPr()
        pPr.set('marL', str(int(Inches(0.24))))
        pPr.set('indent', str(int(-Inches(0.24))))
        br = p.add_run(); br.text = "•  "
        set_run_font(br, size, bullet_color, True)
        if isinstance(item, tuple):
            lead, rest = item
            r1 = p.add_run(); r1.text = lead
            set_run_font(r1, size, color, True)
            r2 = p.add_run(); r2.text = rest
            set_run_font(r2, size, color, False)
        else:
            r = p.add_run(); r.text = str(item)
            set_run_font(r, size, color, False)
    return tb

def add_rect(slide, x, y, w, h, fill=WHITE, line=None, radius=None):
    shape_type = MSO_SHAPE.ROUNDED_RECTANGLE if radius is not None else MSO_SHAPE.RECTANGLE
    sh = slide.shapes.add_shape(shape_type, Inches(x), Inches(y), Inches(w), Inches(h))
    sh.shadow.inherit = False
    sh.fill.solid(); sh.fill.fore_color.rgb = fill
    if radius is not None:
        try: sh.adjustments[0] = radius
        except Exception: pass
    if line is None:
        sh.line.fill.background()
    else:
        sh.line.color.rgb = line
        sh.line.width = Pt(0.75)
    return sh

def add_oval(slide, x, y, w, h, fill, line=None):
    sh = slide.shapes.add_shape(MSO_SHAPE.OVAL, Inches(x), Inches(y), Inches(w), Inches(h))
    sh.shadow.inherit = False
    sh.fill.solid(); sh.fill.fore_color.rgb = fill
    if line is None: sh.line.fill.background()
    else:
        sh.line.color.rgb = line; sh.line.width = Pt(0.75)
    return sh

def add_line(slide, x1, y1, x2, y2, color=BORDER, width=0.8):
    sh = slide.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(x1), Inches(y1), Inches(x2), Inches(y2))
    sh.line.color.rgb = color
    sh.line.width = Pt(width)

def add_image_fit(slide, name, x, y, max_w, max_h):
    path = FIG / name
    with Image.open(path) as im:
        ratio = im.width / im.height
    w = max_w
    h = w / ratio
    if h > max_h:
        h = max_h
        w = h * ratio
    left = x + (max_w - w) / 2
    top = y + (max_h - h) / 2
    slide.shapes.add_picture(str(path), Inches(left), Inches(top), Inches(w), Inches(h))
    return left, top, w, h

def add_header(slide, section, title, page):
    set_bg(slide, OFFWHITE)
    add_rect(slide, 0, 0, 13.333, 0.075, TEAL)
    add_rect(slide, 0.55, 0.43, 0.075, 0.72, TEAL)
    add_text(slide, 0.82, 0.34, 8.0, 0.25, section, 9.5, TEAL, True)
    add_text(slide, 0.82, 0.58, 11.8, 0.55, title, 23, NAVY, True)
    add_line(slide, 0.82, 1.27, 12.55, 1.27, BORDER, 0.8)
    add_text(slide, 11.0, 0.37, 1.8, 0.22, "RIS × mmWave", 8.5, MUTED, False, PP_ALIGN.RIGHT)
    add_text(slide, 0.82, 7.18, 8.0, 0.2, "RIS 通感一体化 · 目标定位全流程", 8.5, MUTED)
    add_text(slide, 11.95, 7.17, 0.55, 0.2, f"{page:02d}", 9, TEAL, True, PP_ALIGN.RIGHT)

def add_section_card(slide, x, y, w, h, number, title, body, color=TEAL, fill=WHITE):
    add_rect(slide, x, y, w, h, fill, BORDER, radius=0.08)
    add_oval(slide, x+0.22, y+0.22, 0.38, 0.38, color)
    add_text(slide, x+0.22, y+0.245, 0.38, 0.25, number, 10, WHITE, True, PP_ALIGN.CENTER)
    add_text(slide, x+0.72, y+0.20, w-0.9, 0.30, title, 14, NAVY, True)
    add_text(slide, x+0.22, y+0.72, w-0.44, h-0.82, body, 11.5, SLATE, False, line_spacing=1.08)

def add_table(slide, x, y, w, h, headers, rows, col_widths, font_size=10.5):
    shape = slide.shapes.add_table(len(rows)+1, len(headers), Inches(x), Inches(y), Inches(w), Inches(h))
    table = shape.table
    table.first_row = True
    table.horz_banding = False
    for i, cw in enumerate(col_widths):
        table.columns[i].width = Inches(cw)
    for c, htxt in enumerate(headers):
        cell = table.cell(0, c)
        cell.fill.solid(); cell.fill.fore_color.rgb = NAVY
        cell.margin_left = Inches(0.06); cell.margin_right = Inches(0.06)
        cell.margin_top = Inches(0.04); cell.margin_bottom = Inches(0.04)
        cell.vertical_anchor = MSO_ANCHOR.MIDDLE
        tf = cell.text_frame; tf.word_wrap = True
        p = tf.paragraphs[0]; p.alignment = PP_ALIGN.LEFT
        r = p.add_run(); r.text = htxt
        set_run_font(r, font_size, WHITE, True)
    for ri, row in enumerate(rows, start=1):
        for c, val in enumerate(row):
            cell = table.cell(ri, c)
            cell.fill.solid(); cell.fill.fore_color.rgb = WHITE if ri % 2 else SOFT
            cell.margin_left = Inches(0.06); cell.margin_right = Inches(0.06)
            cell.margin_top = Inches(0.035); cell.margin_bottom = Inches(0.035)
            cell.vertical_anchor = MSO_ANCHOR.MIDDLE
            tf = cell.text_frame; tf.word_wrap = True
            p = tf.paragraphs[0]; p.alignment = PP_ALIGN.LEFT
            r = p.add_run(); r.text = str(val)
            set_run_font(r, font_size, INK, c == 0)
    for ri in range(len(rows)+1):
        table.rows[ri].height = Inches(h/(len(rows)+1))
    return table

# Slide 1: cover
s = prs.slides.add_slide(BLANK)
set_bg(s, NAVY)
add_oval(s, -1.3, 4.7, 7.2, 4.0, RGBColor(0x10, 0x2A, 0x4C))
add_oval(s, 7.7, -1.7, 7.6, 6.8, RGBColor(0x12, 0x35, 0x5A))
add_rect(s, 0.82, 0.58, 0.055, 4.7, TEAL)
add_text(s, 1.05, 0.62, 6.0, 0.28, "STAGE-3 · MATLAB SIMULATION · 28 GHz", 9.5, RGBColor(0x8F,0xE3,0xE3), True)
add_text(s, 1.05, 1.16, 7.1, 1.65, "RIS 辅助毫米波\n通感一体化", 34, WHITE, True, line_spacing=1.0)
add_text(s, 1.05, 2.98, 6.85, 0.75, "目标定位全流程：从直达路径粗估计，到 RIS 四路径联合精估计", 17.5, RGBColor(0xD8,0xE4,0xF2), False, line_spacing=1.10)
add_rect(s, 1.05, 3.98, 1.35, 0.06, ORANGE)
for i, txt in enumerate(["OFDM 12672 子载波", "16×16 RIS", "8×8 Rx"]):
    x = 1.05 + i*2.15
    add_rect(s, x, 4.35, 1.95, 0.42, RGBColor(0x14,0x3A,0x60), RGBColor(0x2B,0x5B,0x86), radius=0.5)
    add_text(s, x, 4.43, 1.95, 0.22, txt, 9, RGBColor(0xD8,0xE4,0xF2), False, PP_ALIGN.CENTER)
add_text(s, 1.05, 6.72, 6.3, 0.30, "基于当前 code/ 实现 · 结构图由 LaTeX / TikZ 生成", 9.5, RGBColor(0x8A,0xA6,0xC3))
add_oval(s, 7.7, 1.15, 5.0, 5.0, RGBColor(0x0E,0x2A,0x4A))
add_image_fit(s, "fig_cover.png", 7.65, 1.15, 5.1, 4.6)
add_text(s, 8.05, 6.20, 4.4, 0.25, "TikZ schematic · not to scale", 8.5, RGBColor(0x8A,0xA6,0xC3), False, PP_ALIGN.CENTER)

# Slide 2: conclusion
s = prs.slides.add_slide(BLANK)
add_header(s, "01 / 先给结论", "这不是一次直接计算，而是两阶段参数估计", 2)
add_rect(s, 0.65, 1.5, 12.0, 1.35, NAVY, None, radius=0.06)
add_text(s, 0.95, 1.68, 11.4, 0.95, "核心不是直接输出坐标，而是估计四参数 [R, v, θ, φ]。\n粗估计给初值，RIS 精估计用多路径联合拟合修正。", 18.5, WHITE, True, line_spacing=1.10)
add_section_card(s, 0.65, 3.12, 3.7, 1.75, "01", "子载波 → 距离", "回波时延转成距离格；\n距离分辨率由带宽决定。", TEAL)
add_section_card(s, 4.80, 3.12, 3.7, 1.75, "02", "符号 → 速度", "慢时间相位旋转转成多普勒；\n速度分辨率由观测时长决定。", CYAN)
add_section_card(s, 8.95, 3.12, 3.7, 1.75, "03", "阵列 → 角度", "比较相邻接收天线的相位差；\n水平 / 垂直方向合成 θ 和 φ。", ORANGE)
add_rect(s, 0.65, 5.20, 12.0, 1.12, PALETEAL, TEAL, radius=0.07)
add_text(s, 0.93, 5.37, 11.45, 0.80, "RIS 不是传感器：它提供位置、朝向和相位都已知的额外反射路径，让同一组目标参数同时解释多条观测。", 13.5, TEAL_DARK, True, line_spacing=1.12)
add_text(s, 0.68, 6.65, 11.9, 0.25, "粗定位 ≠ 最终定位；精定位也不保证成功，它受粗估计锁定和局部搜索窗口约束。", 9.5, MUTED)

# Slide 3: coordinates
s = prs.slides.add_slide(BLANK)
add_header(s, "02 / 坐标与输出", "先统一坐标，再谈定位精度", 3)
add_bullets(s, 0.82, 1.55, 5.0, 2.85, [
    ("R：", "基站到目标的单程距离。"),
    ("θ：", "从 +z 轴量起的极角（代码注释称「俯仰角」）。"),
    ("φ：", "xy 平面内从 +x 轴量起的方位角。"),
    ("输出：", "estimate = [R, v, θ, φ]；xyz 只在评估时转换。"),
] , size=14.5, color=INK, spacing=8)
add_rect(s, 0.82, 4.55, 5.0, 1.42, PALEORANGE, ORANGE, radius=0.07)
add_text(s, 1.02, 4.72, 4.6, 1.05, "注意：θ 不是水平面仰角。\n若论文使用仰角 e，则 e = 90° − θ。", 12.5, RGBColor(0x8A,0x4B,0x00), True, line_spacing=1.12)
add_image_fit(s, "fig_coords.png", 6.15, 1.45, 6.35, 3.0)
add_text(s, 6.15, 4.55, 6.35, 0.25, "侧视 + 俯视：把球坐标拆成两个容易理解的平面", 9.5, MUTED, False, PP_ALIGN.CENTER)
for i, (lead, body) in enumerate([("R", "决定目标离基站多远"), ("θ", "决定偏离天顶多少"), ("φ", "决定水平面内朝哪边")]):
    x = 6.15 + i*2.10
    add_rect(s, x, 4.95, 1.95, 0.90, WHITE, BORDER, radius=0.10)
    add_text(s, x+0.15, 5.05, 1.65, 0.22, lead, 13, TEAL, True, PP_ALIGN.CENTER)
    add_text(s, x+0.10, 5.32, 1.75, 0.35, body, 9.3, SLATE, False, PP_ALIGN.CENTER)
add_text(s, 0.82, 6.35, 11.8, 0.30, "最终三维位置：x = R sinθ cosφ，y = R sinθ sinφ，z = R cosθ。", 10.5, MUTED)

# Slide 4: pipeline
s = prs.slides.add_slide(BLANK)
add_header(s, "03 / 全流程", "一条主链路：粗估计 → RIS 设计 → 四路径精估计", 4)
add_image_fit(s, "fig_pipeline.png", 0.42, 1.45, 12.5, 3.35)
cards = [
    ("粗估计", "2D FFT + 阵列相位差；\n输出四参数与 locked 标志。"),
    ("精估计", "以粗值为初值；\n用四路径模型联合拟合。"),
    ("失败保护", "locked = false → 直接返回粗估计；\n不进入 RIS 精估计。"),
]
for i, (lead, body) in enumerate(cards):
    x = 0.65 + i*4.12
    add_rect(s, x, 5.02, 3.85, 1.35, WHITE, BORDER, radius=0.08)
    add_text(s, x+0.22, 5.15, 3.4, 0.27, lead, 14, NAVY, True)
    add_text(s, x+0.22, 5.50, 3.4, 0.72, body, 10.8, SLATE, False, line_spacing=1.10)
add_text(s, 0.65, 6.62, 11.95, 0.28, "RIS 设计和精估计的局部基都使用粗估计 initial，不使用仿真真值 p.truth。", 9.5, ORANGE, True)

# Slide 5: coarse range/velocity
s = prs.slides.add_slide(BLANK)
add_header(s, "04 / 粗定位 · 距离与速度", "沿两个轴做 FFT：子载波看距离，符号看速度", 5)
add_image_fit(s, "fig_coarse_fft.png", 0.45, 1.42, 12.4, 3.72)
cards = [
    ("① 去 QAM", "接收端知道发射符号；\n先把 16QAM 自己带来的相位去掉。"),
    ("② 距离 FFT", "沿子载波方向看相位斜率；\n斜率对应延迟，延迟对应距离。"),
    ("③ 速度 FFT", "沿符号方向看相位旋转；\n旋转速度对应多普勒，再对应速度。"),
]
for i, (lead, body) in enumerate(cards):
    x = 0.65 + i*4.12
    add_rect(s, x, 5.25, 3.85, 1.35, WHITE, BORDER, radius=0.08)
    add_text(s, x+0.20, 5.38, 3.45, 0.25, lead, 13.5, NAVY, True)
    add_text(s, x+0.20, 5.72, 3.45, 0.72, body, 10.4, SLATE, False, line_spacing=1.10)
add_text(s, 0.65, 6.80, 11.95, 0.22, "峰值之后：三点抛物线插值细化距离 / 速度；NMS 抑制同一目标的重复峰。", 9.2, MUTED)

# Slide 6: angle
s = prs.slides.add_slide(BLANK)
add_header(s, "05 / 粗定位 · 角度与锁定", "角度不是 FFT，而是比较相邻天线的相位差", 6)
add_image_fit(s, "fig_angle.png", 0.45, 1.42, 6.3, 3.75)
add_bullets(s, 7.05, 1.55, 5.55, 3.45, [
    ("波前：", "同一个平面波斜着扫过 8×8 接收阵。"),
    ("水平相位差：", "给一个方向分量 u。"),
    ("垂直相位差：", "给另一个方向分量 v；两者合成 θ, φ。"),
    ("多用户：", "空间快拍做 SVD，提取主空间模式；再做 2 轮空间干扰消除。"),
    ("locked：", "检测到全部目标，且峰值/中位数 > 45，才进入精估计。"),
] , size=13.2, spacing=7)
add_rect(s, 7.05, 5.30, 5.55, 1.05, PALEORANGE, ORANGE, radius=0.07)
add_text(s, 7.25, 5.46, 5.15, 0.72, "locked = false 时，RIS 精估计不会运行；输出就是粗估计。", 12.2, RGBColor(0x8A,0x4B,0x00), True, line_spacing=1.12)
add_text(s, 0.65, 5.25, 5.95, 0.25, "SVD 只负责合并/提纯空间快照，角度仍来自相邻相位差。", 9.2, MUTED, False, PP_ALIGN.CENTER)

# Slide 7: RIS paths
s = prs.slides.add_slide(BLANK)
add_header(s, "06 / RIS 的几何", "RIS 把一条直达路径，扩展成四条可建模路径", 7)
add_image_fit(s, "fig_ris_paths.png", 0.35, 1.42, 6.55, 3.80)
add_table(s, 7.22, 1.55, 5.48, 3.30,
          ["路径", "走法", "关键差异"],
          [["DD", "BS → 目标 → BS", "直达"],
           ["RD", "BS → RIS → 目标 → BS", "发端多一反射"],
           ["DR", "BS → 目标 → RIS → BS", "收端多一反射"],
           ["RR", "BS → RIS → 目标 → RIS → BS", "双程 RIS"]],
          [0.70, 2.55, 1.55], font_size=10.2)
add_rect(s, 7.22, 5.12, 5.48, 1.35, PALETEAL, TEAL, radius=0.07)
add_text(s, 7.42, 5.28, 5.05, 1.00, "接收机看到的是四条路径叠加后的总回波；\n估计器不会把四条路径分别测出来，而是要求同一组 z 同时解释它们。", 11.2, TEAL_DARK, True, line_spacing=1.12)
add_text(s, 0.60, 5.35, 6.0, 0.55, "RIS 位置、朝向、阵元相位码已知；\n这些已知几何把额外路径变成约束。", 10.0, SLATE, False, line_spacing=1.12)

# Slide 8: fine estimator loop
s = prs.slides.add_slide(BLANK)
add_header(s, "07 / 精定位", "精估计不是解公式，而是「预测—比较—修正」", 8)
add_image_fit(s, "fig_fine_loop.png", 0.40, 1.42, 7.75, 3.85)
add_bullets(s, 8.30, 1.55, 4.40, 3.55, [
    ("起点：", "粗估计 [R,v,θ,φ] + 局部窗口。"),
    ("预测：", "候选几何下四条路径的理论回波。"),
    ("消元：", "拟合四条路径的复增益，消掉亮度和整体相位。"),
    ("比较：", "预测总回波 vs 实测总回波，计算残差。"),
    ("修正：", "调整几何参数；变差就步长减半，重复 10 轮。"),
] , size=13.0, spacing=7)
add_rect(s, 8.30, 5.30, 4.40, 1.10, PALETEAL, TEAL, radius=0.07)
add_text(s, 8.48, 5.45, 4.05, 0.78, "四条路径共享同一组几何参数；\n两组 RIS 配置共享同一组路径增益 α。", 10.8, TEAL_DARK, True, line_spacing=1.10)
add_text(s, 0.62, 5.40, 7.35, 0.25, "变量投影：先把路径复增益解掉，再判断几何参数是否匹配。", 9.2, MUTED, False, PP_ALIGN.CENTER)

# Slide 9: constraints
s = prs.slides.add_slide(BLANK)
add_header(s, "08 / 为什么 RIS 能约束", "同一个目标，必须同时解释多条路径", 9)
add_image_fit(s, "fig_constraints.png", 0.35, 1.42, 7.45, 3.85)
add_bullets(s, 8.15, 1.55, 4.55, 3.65, [
    ("DD：", "提供 2R、2v 和目标方向。"),
    ("RD / DR：", "多一段 BS-RIS 与 RIS-目标路程，多普勒也不同。"),
    ("RR：", "双程 RIS，给出额外的路程/多普勒关系。"),
    ("已知量：", "RIS 位置、朝向、每组相位码。"),
    ("未知量：", "四条路径的复增益 α；逐轮最小二乘拟合。"),
] , size=13.0, spacing=7)
add_rect(s, 8.15, 5.32, 4.55, 1.10, PALEORANGE, ORANGE, radius=0.07)
add_text(s, 8.35, 5.46, 4.15, 0.80, "这不是硬几何交会，而是带权重的联合拟合；\n弱路径贡献小，校准误差会带来偏差。", 10.8, RGBColor(0x8A,0x4B,0x00), True, line_spacing=1.10)

# Slide 10: FAS insertion
s = prs.slides.add_slide(BLANK)
add_header(s, "09 / FAS 的位置", "FAS 不改估计器，插在粗估计之后", 10)
add_image_fit(s, "fig_fas.png", 0.35, 1.38, 12.65, 4.05)
for i, (lead, body) in enumerate([
    ("插入点", "粗估后、精估前；\n位置冻结后用于两组 RIS。"),
    ("作用", "改变 Tx 几何与照射；\n精估计器保持不变。"),
    ("代价", "guard = 4 symbols；\n目标函数是 max-min 照射 + SINR。"),
]):
    x = 0.65 + i*4.12
    add_rect(s, x, 5.55, 3.85, 1.05, WHITE, BORDER, radius=0.08)
    add_text(s, x+0.18, 5.66, 3.45, 0.24, lead, 12.8, NAVY, True)
    add_text(s, x+0.18, 5.95, 3.45, 0.52, body, 9.8, SLATE, False, line_spacing=1.08)
add_text(s, 0.65, 6.76, 11.95, 0.25, "FAS 只动发射端，不动接收端；定位角度仍主要受接收阵列孔径限制。", 9.2, ORANGE, True)

# Slide 11: error budget
s = prs.slides.add_slide(BLANK)
add_header(s, "10 / 误差与边界", "为什么定位误差常常卡在角度，而不是距离", 11)
add_image_fit(s, "fig_error.png", 0.45, 1.45, 6.35, 3.25)
add_rect(s, 7.15, 1.55, 5.45, 1.12, PALEORANGE, ORANGE, radius=0.08)
add_text(s, 7.35, 1.68, 5.05, 0.35, "0.1° @ 600 m ≈ 1.05 m", 20, RGBColor(0x8A,0x4B,0x00), True, PP_ALIGN.CENTER)
add_text(s, 7.35, 2.08, 5.05, 0.32, "远距离下，角度误差会被 R 直接放大", 9.5, RGBColor(0x8A,0x4B,0x00), False, PP_ALIGN.CENTER)
add_rect(s, 7.15, 2.90, 2.65, 0.86, WHITE, BORDER, radius=0.10)
add_text(s, 7.22, 2.98, 2.50, 0.25, "9.86 cm", 15, TEAL, True, PP_ALIGN.CENTER)
add_text(s, 7.22, 3.30, 2.50, 0.22, "距离分辨率", 8.5, SLATE, False, PP_ALIGN.CENTER)
add_rect(s, 9.95, 2.90, 2.65, 0.86, WHITE, BORDER, radius=0.10)
add_text(s, 10.02, 2.98, 2.50, 0.25, "8 × 8", 15, TEAL, True, PP_ALIGN.CENTER)
add_text(s, 10.02, 3.30, 2.50, 0.22, "接收阵列", 8.5, SLATE, False, PP_ALIGN.CENTER)
add_bullets(s, 7.15, 4.05, 5.45, 1.85, [
    ("角度：", "由接收阵列孔径决定；FAS 只动 Tx，不能直接提高角度分辨率。"),
    ("粗估：", "locked 门限决定是否进入精估；低 SNR 下可能直接停在粗估计。"),
    ("精估：", "只在粗值附近局部有效；超出窗口就救不回来。"),
] , size=11.8, spacing=5)
add_text(s, 0.65, 5.30, 6.0, 0.55, "距离/速度：宽带 + 长 CPI + 高 SNR；\n角度：孔径 + 阵列校准 + 空间快拍质量。", 9.8, MUTED, False, line_spacing=1.12)
add_text(s, 0.65, 6.30, 12.0, 0.35, "其他边界：同一距离-速度单元的多目标、rank-1 SVD、已知 QAM、远场/匀速模型、无额外多径与无跟踪关联。", 9.0, MUTED)

# Slide 12: code map / summary
s = prs.slides.add_slide(BLANK)
add_header(s, "11 / 代码地图与总结", "把流程落回代码：每个函数只做一件事", 12)
add_table(s, 0.65, 1.50, 7.15, 4.35,
          ["函数", "作用"],
          [["simulate_radar_channel_3d", "生成直达路径回波与观测矩阵"],
           ["joint_estimator_fast", "2D FFT + 阵列相位差，粗估 [R,v,θ,φ]"],
           ["prepare_ris_observation", "用粗估计构造局部投影基 B"],
           ["optimize_ris_joint", "设计发射波束 W 与离散 RIS 相位"],
           ["refine_ris_parameters", "四路径联合精估计（变量投影）"],
           ["evaluate_estimation", "匹配、转 xyz、计算 RMSE"]],
          [2.55, 4.60], font_size=9.5)
summary = [
    ("定位", "参数估计，不是直接读坐标", TEAL),
    ("RIS", "已知几何约束，不是传感器", CYAN),
    ("FAS", "发射几何搜索，不改精估计算法", ORANGE),
]
for i, (lead, body, col) in enumerate(summary):
    y = 1.55 + i*1.35
    add_rect(s, 8.02, y, 4.62, 1.10, WHITE, BORDER, radius=0.09)
    add_oval(s, 8.22, y+0.20, 0.35, 0.35, col)
    add_text(s, 8.70, y+0.14, 3.60, 0.28, lead, 13.5, NAVY, True)
    add_text(s, 8.70, y+0.48, 3.60, 0.45, body, 10.2, SLATE, False, line_spacing=1.08)
add_rect(s, 0.65, 6.02, 12.0, 0.83, NAVY, None, radius=0.06)
add_text(s, 0.90, 6.18, 11.5, 0.50, "粗估计找初值；精估计用四路径模型把同一组参数拟合得更准；最后才转 xyz / RMSE。", 13.2, WHITE, True, PP_ALIGN.CENTER)
add_text(s, 0.65, 6.98, 12.0, 0.18, "源码目录：stage3-RIS与毫米波通感一体化联合优化算法方案/code · TikZ 图源同步保存在 ppt/latex_src", 7.8, MUTED)
ppt_path = DELIV / "RIS_通感一体化_定位全流程.pptx"
prs.save(str(ppt_path))
print("SAVED", ppt_path)
print("slides", len(prs.slides))
