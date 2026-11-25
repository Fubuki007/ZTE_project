#!/usr/bin/env python3
"""
Build the 7-slide 2026-11-24 plain-Chinese advisor presentation appendix (Slides 21-27) for:
  RIS_通感一体化_定位全流程_结果补充_20261118_v4.pptx

Written in clear, intuitive, presentation-ready Chinese (minimal jargon, plain explanations
paired with rigorous audited numbers) with verbatim speaker scripts in every slide's notes.

Design system matched 1:1 to Slides 1-20 (1280x720 px / 13.333x7.5 in,
Microsoft YaHei, #F8FAFC canvas, #0B1F3A navy, #0E8F8F teal, #D98B00 orange,
#CF4963 rose, #E2E8F0 border).
"""

from __future__ import annotations

import csv
import json
import math
from pathlib import Path
from typing import List, Sequence, Tuple

from PIL import Image
from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.oxml.ns import qn
from pptx.oxml.xmlchemy import OxmlElement
from pptx.util import Inches, Pt


PPT_DIR = Path(__file__).resolve().parent
STAGE3_DIR = PPT_DIR.parent
REPO_ROOT = STAGE3_DIR.parent
CODE_DIR = STAGE3_DIR / "code" / "uav" / "nlos_crb"
FIG_DIR = CODE_DIR / "figures" / "ppt"
RELEASE_SHA = "691743ee8ef239e5aeeefa2adb03b5379b5abb5a"
RESULTS_DIR = REPO_ROOT / "server-results" / "uav-nlos_crb" / RELEASE_SHA
BUILD_DIR = PPT_DIR / ".build-nlos-crb-20261124"
BUILD_DIR.mkdir(parents=True, exist_ok=True)

FONT = "Microsoft YaHei"

C = {
    "bg": RGBColor(0xF8, 0xFA, 0xFC),
    "white": RGBColor(0xFF, 0xFF, 0xFF),
    "navy": RGBColor(0x0B, 0x1F, 0x3A),
    "ink": RGBColor(0x0F, 0x17, 0x2A),
    "slate": RGBColor(0x47, 0x55, 0x69),
    "muted": RGBColor(0x64, 0x74, 0x8B),
    "teal": RGBColor(0x0E, 0x8F, 0x8F),
    "teal_soft": RGBColor(0xE6, 0xF4, 0xF4),
    "orange": RGBColor(0xD9, 0x8B, 0x00),
    "orange_soft": RGBColor(0xFE, 0xF3, 0xC7),
    "rose": RGBColor(0xCF, 0x49, 0x63),
    "rose_soft": RGBColor(0xFD, 0xE8, 0xEC),
    "blue": RGBColor(0x25, 0x63, 0xEB),
    "border": RGBColor(0xE2, 0xE8, 0xF0),
    "row_alt": RGBColor(0xF1, 0xF5, 0xF9),
    "card_border": RGBColor(0xCB, 0xD5, 0xE1),
}


def px(v: float):
    """Convert 1280x720 px coordinates to Inches (96 px = 1 in)."""
    return Inches(v / 96.0)


def set_cell_borders(cell, color_hex: str = "E2E8F0", width_pt: float = 0.7) -> None:
    tcPr = cell._tc.get_or_add_tcPr()
    w = str(int(round(width_pt * 12700)))
    for side in ("lnL", "lnR", "lnT", "lnB"):
        for existing in tcPr.findall(qn(f"a:{side}")):
            tcPr.remove(existing)
        ln = OxmlElement(f"a:{side}")
        ln.set("w", w)
        ln.set("cap", "flat")
        ln.set("cmpd", "sng")
        ln.set("algn", "ctr")
        sf = OxmlElement("a:solidFill")
        clr = OxmlElement("a:srgbClr")
        clr.set("val", color_hex)
        sf.append(clr)
        ln.append(sf)
        prst = OxmlElement("a:prstDash")
        prst.set("val", "solid")
        ln.append(prst)
        tcPr.append(ln)


def set_run_font(run, size_pt: float, color: RGBColor, bold: bool = False) -> None:
    run.font.name = FONT
    run.font.size = Pt(size_pt)
    run.font.bold = bold
    run.font.color.rgb = color
    rPr = run._r.get_or_add_rPr()
    for tag in ("a:ea", "a:cs", "a:latin"):
        for old in rPr.findall(qn(tag)):
            rPr.remove(old)
        el = OxmlElement(tag)
        el.set("typeface", FONT)
        rPr.append(el)


def add_rect(slide, x: float, y: float, w: float, h: float, fill: RGBColor, line_color: RGBColor | None = None, line_pt: float = 0.75, rounded: bool = False):
    shape_type = MSO_SHAPE.ROUNDED_RECTANGLE if rounded else MSO_SHAPE.RECTANGLE
    shp = slide.shapes.add_shape(shape_type, px(x), px(y), px(w), px(h))
    if rounded:
        try:
            shp.adjustments[0] = min(0.08, 10.0 / max(min(w, h), 1.0))
        except Exception:
            pass
    shp.fill.solid()
    shp.fill.fore_color.rgb = fill
    if line_color is not None:
        shp.line.color.rgb = line_color
        shp.line.width = Pt(line_pt)
    else:
        shp.line.fill.background()
    shp.shadow.inherit = False
    return shp


def add_textbox(
    slide,
    text: str,
    x: float,
    y: float,
    w: float,
    h: float,
    size_pt: float = 13.0,
    color: RGBColor = C["ink"],
    bold: bool = False,
    align=PP_ALIGN.LEFT,
    valign=MSO_ANCHOR.TOP,
    line_spacing: float = 1.18,
):
    tb = slide.shapes.add_textbox(px(x), px(y), px(w), px(h))
    tf = tb.text_frame
    tf.word_wrap = True
    tf.vertical_anchor = valign
    tf.margin_left = 0
    tf.margin_right = 0
    tf.margin_top = 0
    tf.margin_bottom = 0
    lines = text.split("\n")
    for idx, line in enumerate(lines):
        p = tf.paragraphs[0] if idx == 0 else tf.add_paragraph()
        p.alignment = align
        p.line_spacing = line_spacing
        run = p.add_run()
        run.text = line
        set_run_font(run, size_pt, color, bold)
    return tb


def add_rich_bullets(
    slide,
    items: Sequence[Tuple[str, str]],
    x: float,
    y: float,
    w: float,
    h: float,
    title_pt: float = 12.0,
    body_pt: float = 11.2,
    title_color: RGBColor = C["navy"],
    body_color: RGBColor = C["ink"],
    space_after_pt: float = 7.0,
):
    tb = slide.shapes.add_textbox(px(x), px(y), px(w), px(h))
    tf = tb.text_frame
    tf.word_wrap = True
    tf.margin_left = 0
    tf.margin_right = 0
    tf.margin_top = 0
    tf.margin_bottom = 0
    for idx, (head, body) in enumerate(items):
        p = tf.paragraphs[0] if idx == 0 else tf.add_paragraph()
        p.line_spacing = 1.24
        p.space_after = Pt(space_after_pt)
        if head:
            r1 = p.add_run()
            r1.text = head
            set_run_font(r1, title_pt, title_color, bold=True)
        if body:
            r2 = p.add_run()
            r2.text = body
            set_run_font(r2, body_pt, body_color, bold=False)
    return tb


def add_picture_fit(slide, img_path: Path, x: float, y: float, max_w: float, max_h: float):
    with Image.open(img_path) as im:
        iw, ih = im.size
    scale = min(max_w / iw, max_h / ih)
    w = iw * scale
    h = ih * scale
    dx = x + (max_w - w) / 2.0
    dy = y + (max_h - h) / 2.0
    return slide.shapes.add_picture(str(img_path), px(dx), px(dy), width=px(w), height=px(h))


def add_table(
    slide,
    rows_data: List[List[str]],
    x: float,
    y: float,
    col_widths_px: List[float],
    row_height_px: float = 38.0,
    font_pt: float = 10.5,
    highlight_last: bool = False,
):
    n_rows = len(rows_data)
    n_cols = len(col_widths_px)
    total_w = sum(col_widths_px)
    total_h = n_rows * row_height_px
    tbl_shape = slide.shapes.add_table(n_rows, n_cols, px(x), px(y), px(total_w), px(total_h))
    tbl = tbl_shape.table
    for ci, cw in enumerate(col_widths_px):
        tbl.columns[ci].width = px(cw)
    for ri in range(n_rows):
        tbl.rows[ri].height = px(row_height_px)
        is_hdr = ri == 0
        is_hl = highlight_last and ri == n_rows - 1
        for ci in range(n_cols):
            cell = tbl.cell(ri, ci)
            cell.vertical_anchor = MSO_ANCHOR.MIDDLE
            cell.margin_left = px(8)
            cell.margin_right = px(7)
            cell.margin_top = px(4)
            cell.margin_bottom = px(4)
            cell.fill.solid()
            if is_hdr:
                cell.fill.fore_color.rgb = C["navy"]
            elif is_hl:
                cell.fill.fore_color.rgb = C["teal_soft"]
            else:
                cell.fill.fore_color.rgb = C["white"] if ri % 2 == 1 else C["row_alt"]
            set_cell_borders(cell, "CBD5E1" if is_hl else "E2E8F0", 0.7)
            tf = cell.text_frame
            tf.word_wrap = True
            p = tf.paragraphs[0]
            p.alignment = PP_ALIGN.LEFT if ci == 0 else PP_ALIGN.CENTER
            p.line_spacing = 1.12
            run = p.add_run()
            run.text = rows_data[ri][ci]
            clr = C["white"] if is_hdr else (C["navy"] if is_hl else C["ink"])
            set_run_font(run, font_pt, clr, bold=(is_hdr or ci == 0 or is_hl))
    return tbl_shape


def new_page(prs: Presentation, section: str, title: str, page_num: int, notes: str):
    blank_layout = prs.slide_layouts[6]
    s = prs.slides.add_slide(blank_layout)
    bg = s.background
    fill = bg.fill
    fill.solid()
    fill.fore_color.rgb = C["bg"]

    # Exact match to Slides 1-20 chrome
    add_rect(s, 0, 0, 1280, 7.2, C["teal"])
    add_rect(s, 52.8, 41.3, 7.2, 69.1, C["teal"])
    add_textbox(s, section, 78.7, 34.0, 920, 24, size_pt=9.5, color=C["teal"], bold=True)
    add_textbox(s, title, 78.7, 56.0, 1140, 48, size_pt=22.5, color=C["navy"], bold=True)
    add_rect(s, 78.7, 121.9, 1126, 1.0, C["border"])
    add_textbox(s, "RIS × mmWave", 1056, 35.5, 173, 22, size_pt=8.5, color=C["muted"], align=PP_ALIGN.RIGHT)
    add_textbox(s, "RIS 通感一体化 · 目标定位全流程", 78.7, 689.3, 770, 20, size_pt=8.5, color=C["muted"])
    add_textbox(s, f"{page_num:02d}", 1147, 688.0, 53, 23, size_pt=9.0, color=C["teal"], bold=True, align=PP_ALIGN.RIGHT)

    s.notes_slide.notes_text_frame.text = notes
    return s


def load_audited_numbers() -> dict:
    audit = json.loads((RESULTS_DIR / "independent_audit.json").read_text(encoding="utf-8"))
    abl = json.loads((RESULTS_DIR / "ablations.json").read_text(encoding="utf-8"))
    g1 = json.loads((CODE_DIR / "gate1_evidence.json").read_text(encoding="utf-8"))
    g2 = json.loads((CODE_DIR / "gate2_evidence.json").read_text(encoding="utf-8"))
    rows = []
    with (RESULTS_DIR / "case_metrics.csv").open("r", encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            rows.append(r)
    nlos30_trials = {
        int(round(float(r["trial"])))
        for r in rows
        if int(round(float(r["rcs_m2"]))) == 30
        and r["method"] == "Proposed_Joint_CRB"
        and float(r["t2_via_ris"]) > 0.5
    }
    t2_cond = {}
    for m in set(r["method"] for r in rows):
        e2 = [
            float(r["err_t2_m"])
            for r in rows
            if int(round(float(r["rcs_m2"]))) == 30
            and r["method"] == m
            and int(round(float(r["trial"]))) in nlos30_trials
            and float(r["captured_both"]) > 0.5
        ]
        t2_cond[m] = math.sqrt(sum(v * v for v in e2) / len(e2)) if e2 else float("nan")
    grp30 = {g["method"]: g for g in audit["groups"] if int(g["rcs_m2"]) == 30}
    boot30 = {b["name"]: b for b in audit["independent_bootstrap_primary_rcs"]}
    return {
        "audit": audit,
        "abl": abl,
        "g1": g1,
        "g2": g2,
        "grp30": grp30,
        "boot30": boot30,
        "t2_cond30": t2_cond,
        "nlos30_n": len(nlos30_trials),
    }


def build_deck() -> Path:
    d = load_audited_numbers()
    prs = Presentation()
    prs.slide_width = px(1280)
    prs.slide_height = px(720)

    # =========================================================================
    # SLIDE 21 (20 / 新阶段进展 · 2026-11-24)
    # =========================================================================
    s21 = new_page(
        prs,
        "20 / 新阶段进展 · 2026-11-24",
        "新场景：高楼遮挡小巷，无人机借墙面 RIS 定位盲区目标",
        21,
        "【汇报讲稿】老师您好，前面 20 页是上轮结果，当时留下两个核心问题：一是大误差离群点怎么治，二是同样位置下 RIS 到底有没有净收益。\n"
        "这一轮我们换了一个更真实的城市高楼街谷场景（右图）：东边是 30 米高的楼，中间夹着一条 12 米窄小巷，目标 2 躲在小巷里被大楼挡住了（纯 NLoS 盲区）。\n"
        "无人机基站必须一边给主干道上的 2 个手机用户稳定供网（SINR ≥ 10 dB），一边给两个目标定位——既飞不过 30 米楼顶，又不能跑偏让手机断网，所以必须借助对面墙上的 32×32（17.1 厘米）无源 RIS，把信号反射拐弯送进小巷里。\n"
        "左表总结了我们相对上轮的 6 项升级：场景更真实、RIS 从 16×16 升级到 32×32、不再浪费 98% 的频段、并加入了“最优固定基站”和“同位置无 RIS”两个最公平的对照组。",
    )
    add_textbox(
        s21,
        "为什么必须“无人机基站 + 墙面 RIS”协同？因为既要保路人手机不断网，又要绕开 30 米高楼看小巷盲区",
        78.7, 134, 1126, 28, size_pt=12.8, color=C["navy"], bold=True,
    )
    table21 = [
        ["对比项", "上一轮做法（11-18）", "本轮升级做法（11-24）"],
        ["测试场景", "200 m 空旷直视，9 个离散悬停点", "300 m 城市高楼街谷 + 12 m 盲区小巷"],
        ["墙面 RIS", "16×16（8.6 cm），双跳回波太弱", "32×32（17.1 cm），依然纯无源省电"],
        ["信号利用率", "只用 2% 频段，能量白白丢掉 99%", "12,672 全频段利用，能量保住 99%"],
        ["盲区测角", "2 组配置分不清左右，常偏几米", "8 组“斜扫”配置，彻底治好左右模糊"],
        ["公平对照", "固定原点，移动与 RIS 收益混在一起", "最优固定站 + 同位置无 RIS，净收益拆清"],
        ["测试规模", "300 组离散选点测试", "900 组全带宽大考 + 5 项压力测试"],
    ]
    add_table(s21, table21, 78.7, 172, [104, 226, 258], row_height_px=57.0, font_pt=9.8, highlight_last=False)
    add_rect(s21, 78.7, 588, 588, 74, C["teal_soft"], C["teal"], 0.9, rounded=True)
    add_textbox(
        s21,
        "严格守住 3 条物理底线（7,200 条记录 100% 实测核验）：总发射功率绝不超 1 W；通信用户 SINR 100% 达标（≥10 dB）；无人机与 RIS 保持 ≥14 m 安全远场距离。",
        94, 597, 558, 58, size_pt=10.3, color=C["navy"], bold=True, line_spacing=1.22,
    )
    add_rect(s21, 686, 172, 518, 490, C["white"], C["border"], 0.9, rounded=True)
    add_picture_fit(s21, FIG_DIR / "ppt_fig1_geometry.png", 694, 178, 502, 478)

    # =========================================================================
    # SLIDE 22 (21 / 核心方法 · 怎么解决的)
    # =========================================================================
    s22 = new_page(
        prs,
        "21 / 核心方法 · 怎么解决的",
        "3 个核心改进：把盲区定位从“瞎猜几米”压到“厘米级”",
        22,
        "【汇报讲稿】这一页讲我们具体动了哪三处“大手术”，全部用最直白的话总结：\n"
        "第一，把丢掉的 98% 信号捡回来。以前为了省算力，把收到的 12,672 个频段扔掉了 98%，稍微估偏半米能量就掉 99%；现在我们全频段都用上，先抵消掉主路上刺眼的直达强干扰，再精准抠出小巷目标前后 1 米窗口的信号，能量保住了 99%！\n"
        "第二，让 RIS 快速“斜扫 8 组配置”，治好左右分不清。以前别人论文里总想把 RIS 死死聚光照亮目标，但波经 RIS 去一趟回一趟是左右对称的，目标往左歪还是往右歪亮度差不多，经常认错到几米外。我们不增加任何额外时间，把时间均分 8 份，让 RIS 左右半边反相斜着扫，目标偏 1 厘米就会露馅，左右分辨难度从 10.9 万倍直接压到 1.17！\n"
        "第三，给无人机装上“防踩坑”联合选位大脑：选位置时同时兼顾通信 SINR 不断网、先稳稳抓到目标、并在大楼拐角周围多查 5 个方位防踩坑。\n"
        "最下面这栏是单场景严格自检：能量保住 99%、盲区误差仅 2.3 厘米，而现有主流方法偏了 5.52 米。",
    )
    add_textbox(
        s22,
        "针对“双跳信号弱、左右分不清、选位易踩坑”三大痛点，逐一给出对应解法并全部通过实测自检",
        78.7, 134, 1126, 26, size_pt=12.8, color=C["navy"], bold=True,
    )

    cards = [
        (
            "改进 1 · 把丢掉的 98% 信号全捡回来",
            C["teal"],
            [
                ("以前卡在哪：", "信号经 RIS 双跳反射回来本来就弱，老程序又扔掉了 98% 的频段，只要距离初估偏半米，能量就白白丢掉 99%。"),
                ("我们怎么改：", "把全部 12,672 个频段都用起来，先抵消主路上刺眼的直达干扰，再精准截取目标前后约 1 米窗口内的真回波。"),
                ("改完什么效果：", "信号能量保留率从 1% 救回到 99%（−0.05 dB），强干扰被压低 84.8 dB，微弱盲区信号清清楚楚浮出来。"),
            ],
        ),
        (
            "改进 2 · 让 RIS“斜扫 8 组”，治好脸盲",
            C["navy"],
            [
                ("以前卡在哪：", "别人论文里总让 RIS 死死照最亮，但双跳回波左右对称，就像闭一只眼看手电筒，分不清目标偏左还是偏右。"),
                ("我们怎么改：", "不加时间也不加耗电，把时间均分 8 份，让 RIS 像两只眼睛一样快速切换 8 组半边反相和斜扫相移去扫目标。"),
                ("改完什么效果：", "左右分辨难度从 10.9 万倍（几乎算不出）直接降到 1.17（接近完美 1.0），彻底消除几米远的假位置。"),
            ],
        ),
        (
            "改进 3 · 给无人机装“防踩坑”选位大脑",
            C["orange"],
            [
                ("以前卡在哪：", "只追求理论最准可能根本抓不到目标；且在大楼拐角处，初始猜的位置偏一两米，就容易误判能直视而失锁。"),
                ("我们怎么改：", "在 1 W 功率和通信 SINR 达标前提下，强制保证先抓到目标；并在大楼拐角周围多查 5 个方位，宁可保守走 RIS 绝不赌运气。"),
                ("改完什么效果：", "无人机在街道上自由连续找最佳悬停点，抓到目标后再把 RIS 波束实时对准实测位置做精细测距测角。"),
            ],
        ),
    ]
    card_w = 358
    gap = 26
    for idx, (heading, accent, bullets) in enumerate(cards):
        cx = 78.7 + idx * (card_w + gap)
        add_rect(s22, cx, 176, card_w, 366, C["white"], C["card_border"], 0.9, rounded=True)
        add_rect(s22, cx, 176, card_w, 42, accent, None, 0, rounded=False)
        add_textbox(s22, heading, cx + 14, 185, card_w - 28, 26, size_pt=11.8, color=C["white"], bold=True)
        add_rich_bullets(
            s22, bullets, cx + 16, 232, card_w - 32, 300,
            title_pt=10.6, body_pt=10.5, title_color=accent if accent != C["orange"] else C["navy"],
            body_color=C["ink"], space_after_pt=9.0,
        )

    # Bottom Gate 1 & Gate 2 Plain-Language Evidence Strip
    add_rect(s22, 78.7, 562, 1126, 102, C["white"], C["teal"], 1.1, rounded=True)
    add_textbox(s22, "算法自检实测验收（上线服务器跑全量前，5 项硬核门槛全部一次性通过）", 96, 570, 960, 22, size_pt=10.6, color=C["teal"], bold=True)
    kpis = [
        ("信号能量保留", "99.0% (-0.05 dB)", "以前仅剩 1% (-20.5 dB)"),
        ("左右分辨难度", "10.9 万 → 1.17", "越接近 1 越清晰不脸盲"),
        ("强直达干扰抑制", "84.8 dB", "主路强光几乎完全消干净"),
        ("无噪声理论误差", "< 0.0001 毫米", "证明定位公式完全无偏"),
        ("单场景盲区实测", "2.3 厘米", "现有论文方法偏了 5.52 米"),
    ]
    kw = 216
    for i, (k_lbl, k_val, k_sub) in enumerate(kpis):
        kx = 96 + i * (kw + 6)
        add_textbox(s22, k_lbl, kx, 594, kw, 18, size_pt=9.2, color=C["muted"], bold=True)
        add_textbox(s22, k_val, kx, 613, kw, 24, size_pt=12.5, color=C["navy"], bold=True)
        add_textbox(s22, k_sub, kx, 639, kw, 18, size_pt=8.5, color=C["slate"])

    # =========================================================================
    # SLIDE 23 (22 / 全量测试 · 900 个随机街景)
    # =========================================================================
    s23 = new_page(
        prs,
        "22 / 全量测试 · 900 个随机街景",
        "900 组大考成绩：无人机移动与墙面 RIS 缺一不可",
        23,
        "【汇报讲稿】我们在 64 核服务器上用全带宽完整跑了 900 个随机城市街景：包括小目标、常规车辆和大目标三档，每档 300 个随机场景，拉了 7 个对手同场比拼，哪怕测失败了也一条不删。\n"
        "看左图的成功率（误差小于 1 米才算成功）：以常规车辆（青绿色柱子）为例，装死不动的固定基站就算带了 RIS 也只有 37.7%；无人机光会飞但不带 RIS 只有 28.3%；只有把“无人机选位 + 墙面 RIS”联合起来，成功率才飙升到 84.0%，大目标更是达到 92.3%！\n"
        "看右图的平均误差（越低越好）：我们三档都压到最低（1.40、1.16、0.95 米），而现有论文里“只管照最亮”的方法因为左右分不清，平均误差直接飙到 8.3–8.4 米（顶部红标）。",
    )
    add_textbox(
        s23,
        "64 核服务器全带宽正式仿真：3 种目标大小 × 300 随机街景 × 8 种方法 = 7,200 条完整记录（失败案例全保留）",
        78.7, 134, 1126, 26, size_pt=12.5, color=C["slate"],
    )
    add_rect(s23, 78.7, 166, 1126, 424, C["white"], C["border"], 0.9, rounded=True)
    add_picture_fit(s23, FIG_DIR / "ppt_fig2_main_rcs.png", 86, 172, 1112, 412)

    callouts23 = [
        ("缺一不可的协同跃升", "常规车辆目标下：固定站带 RIS 仅 37.7%，无人机无 RIS 仅 28.3%；联合优化跃升至 84.0%（大目标 92.3%）。", C["teal_soft"], C["teal"]),
        ("全样本平均误差最低", "三档目标全样本平均误差仅 1.40 / 1.16 / 0.95 m；现有“照最亮”方法因左右模糊高达 8.42 m。", C["row_alt"], C["navy"]),
        ("零作弊、全量审计", "全部 900 组失败样本完整保留在总成绩里，并由独立 Python 程序逐行复核无误。", C["orange_soft"], C["orange"]),
    ]
    cw23 = 360
    for i, (t, b, bg_c, bd_c) in enumerate(callouts23):
        cx = 78.7 + i * (cw23 + 23)
        add_rect(s23, cx, 600, cw23, 72, bg_c, bd_c, 0.9, rounded=True)
        add_textbox(s23, t, cx + 12, 606, cw23 - 24, 20, size_pt=10.2, color=C["navy"], bold=True)
        add_textbox(s23, b, cx + 12, 626, cw23 - 24, 42, size_pt=9.2, color=C["ink"], line_spacing=1.16)

    # =========================================================================
    # SLIDE 24 (23 / 盲区专项 · 既抓得到又测得准)
    # =========================================================================
    s24 = new_page(
        prs,
        "23 / 盲区专项 · 既抓得到又测得准",
        "躲在巷子里的盲区目标：成功率 88.9%，误差仅 3.8 厘米",
        24,
        "【汇报讲稿】老师，只看平均误差容易被失败案例掩盖，所以我们把“能不能抓到”和“抓到后准不准”拆开放在同一张图里看（左图 a）：横轴是成功率、越往右越好；纵轴是抓到后的误差、越往下越好，所以右下角是既稳又准的理想区。\n"
        "可以看到，只有我们那颗绿星稳稳落在右下角！现有论文方法（红叉）和网格选点（橙点）虽然能抓到不少目标，但抓到后误差依然有 1.66 米到 9.46 米。\n"
        "再看中间图 (b) 和右表专门挑出“目标 2 躲在小巷纯盲区”的成绩：常规车辆下我们成功率 88.9%，定位误差只有 3.8 厘米（大目标 97.0%、2.7 厘米），相比现有论文方法的 3.24 米，精度整整提升了 85 倍！",
    )
    add_rect(s24, 78.7, 140, 724, 444, C["white"], C["border"], 0.9, rounded=True)
    add_picture_fit(s24, FIG_DIR / "ppt_fig3_pareto_nlos.png", 84, 148, 712, 428)

    add_textbox(s24, "常规车辆目标（30 m²）完整成绩单", 816, 140, 392, 24, size_pt=11.0, color=C["navy"], bold=True)
    g30 = d["grp30"]
    tc30 = d["t2_cond30"]
    rows24 = [["对比方法", "总误差", "抓到误差", "整体<1m", "盲区<1m", "盲区误差"]]
    short_zh = [
        ("FixedOpt_NoRIS", "固定站无RIS"),
        ("FixedOpt_RIS", "固定站带RIS"),
        ("FixedOpt_RandomRIS", "随机相移RIS"),
        ("OnlineUAV_NoRIS", "无人机无RIS"),
        ("MatchedPos_NoRIS", "同位无RIS"),
        ("GridSelect_RIS", "网格选点RIS"),
        ("Lit_EnergyMax_AO", "现有照最亮"),
        ("Proposed_Joint_CRB", "本文联合法"),
    ]
    for key, zh in short_zh:
        r = g30[key]
        rows24.append([
            zh,
            f"{r['rmse_all_m']:.2f}m",
            f"{r['cond_rmse_m']:.2f}m",
            f"{r['success_1m_rate']*100:.1f}%",
            f"{r['nlos_success_1m_rate']*100:.1f}%",
            f"{tc30[key]*100:.1f}cm" if tc30[key] < 0.2 else (f"{tc30[key]:.2f}m" if math.isfinite(tc30[key]) else "—"),
        ])
    add_table(s24, rows24, 816, 170, [98, 58, 62, 56, 56, 62], row_height_px=46.0, font_pt=9.0, highlight_last=True)

    add_rect(s24, 78.7, 598, 1126, 70, C["teal_soft"], C["teal"], 0.9, rounded=True)
    add_textbox(
        s24,
        "一句话看懂差距：现有论文方法虽然也能抓到近一半目标，但因为分不清左右，盲区目标平均偏 3.24 米；我们的方法把盲区误差压到 3.8 厘米（大目标 2.7 厘米），精度直接提升 85 倍！",
        94, 608, 1096, 52, size_pt=10.8, color=C["navy"], bold=True, line_spacing=1.22,
    )

    # =========================================================================
    # SLIDE 25 (24 / 公平验证 · 到底是谁的功劳)
    # =========================================================================
    s25 = new_page(
        prs,
        "24 / 公平验证 · 到底是谁的功劳",
        "直接回答上轮疑问：纯 RIS 净涨 +69.3%，移动性净涨 +46.3%",
        25,
        "【汇报讲稿】这一页专门回答上轮第 15、20 页留下的最大疑问：“性能变好，到底是靠无人机飞得好，还是靠墙面 RIS 立功，会不会只是碰运气？”\n"
        "我们做了 4,000 次随机配对抽样验证（左图），只要横条完全在 0 虚线右边，就说明 95% 确定是真实提升、绝不是碰运气。6 组拆解对比全部远远甩开 0 线：\n"
        "最上面一行是让无人机停在一模一样的最优位置、只关掉 RIS，成功率暴跌 69.3 个百分点——这就是 RIS 无可争议的纯净收益！\n"
        "第三行是拿我们对比全街挑了最优位置的固定基站（带 RIS），移动性带来 +46.3 个百分点的纯净收益！\n"
        "右图从原理上揭晓为什么我们比现有方法准 85 倍：现有方法只管照最亮，左右分辨难度高达 6.8 万（严重模糊）；而我们 RIS “斜扫 8 组”后中位数稳定在 1.23，几乎跟完美 1.0 一样清晰。",
    )
    add_rect(s25, 78.7, 140, 1126, 444, C["white"], C["border"], 0.9, rounded=True)
    add_picture_fit(s25, FIG_DIR / "ppt_fig4_bootstrap_cond.png", 86, 146, 1112, 432)

    b_ris = d["boot30"]["Proposed_vs_MatchedPos_NoRIS"]
    b_mob = d["boot30"]["Proposed_vs_FixedOpt_RIS"]
    add_rect(s25, 78.7, 598, 1126, 72, C["white"], C["navy"], 1.0, rounded=True)
    add_rich_bullets(
        s25,
        [
            (
                "彻底回答第 15 / 20 页核心悬疑：",
                f"① 同位置有没有 RIS？加上 RIS 成功率净涨 +{b_ris['succ1m_diff_pp']:.1f} 个百分点、总误差降 {b_ris['rmse_gain_pct']:.1f}%；"
                f"② 移动性本身贡献多大？相比全街最优固定站，移动性净涨 +{b_mob['succ1m_diff_pp']:.1f} 个百分点、误差降 {b_mob['rmse_gain_pct']:.1f}%；"
                "③ 全部 6 组拆解验证 95% 可信区间均远大于 0，绝非偶然。",
            )
        ],
        94, 606, 1096, 56, title_pt=10.5, body_pt=10.3, title_color=C["teal"], body_color=C["ink"], space_after_pt=0,
    )

    # =========================================================================
    # SLIDE 26 (25 / 拓展测试 · 回答 5 个实际问题)
    # =========================================================================
    s26 = new_page(
        prs,
        "25 / 拓展测试 · 回答 5 个实际问题",
        "如果实际部署会怎样？5 项压力测试一次性摸清边界",
        26,
        "【汇报讲稿】为了提前回应未来论文审稿人可能会问的 5 个实际工程问题，我们又在服务器上跑了 40 个纯盲区场景的压力测试：\n"
        "图 ① 手机用户要求更高网速怎么办？在 10 dB 以内定位都能保持 4 厘米级别且 100% 可行，逼到 16 dB 高要求时功率紧张，精度才退到 32 厘米，规律非常合理。\n"
        "图 ② 信号多强才能稳稳抓到目标？16 dB 就能达到 99.9% 的发现概率，验证了我们算法里的安全门限设得恰到好处。\n"
        "图 ③ 一开始猜的目标位置偏了怎么办？猜偏 1 到 2 米时都能稳稳抓到 90% 以上，偏到 4 米会掉到 62.5%，清楚标出了能力边界。\n"
        "图 ④ 无人机飞过去那么费电值不值？飞 50 米换个位置只要 5 秒，到位后停在空中工作 30 秒可以连续测 6,500 多次，飞过去那点电只占总耗电的 12.6%，完全划算。\n"
        "下面还补测了两个细节：不用精细宽带模型会多出 25.6% 偏差；工人把墙面 RIS 装歪 5 到 20 厘米，系统也依然稳稳的不会崩。",
    )
    add_textbox(
        s26,
        "提前回应审稿人最关心的 5 个现实疑问（40 个纯盲区场景全带宽实测，每一条都有量化边界）",
        78.7, 134, 1126, 26, size_pt=12.5, color=C["slate"],
    )
    add_rect(s26, 78.7, 168, 1126, 360, C["white"], C["border"], 0.9, rounded=True)
    add_picture_fit(s26, FIG_DIR / "ppt_fig5_ablations.png", 86, 176, 1112, 344)

    a1 = d["abl"]["a1_wideband_squint"]
    a3 = d["abl"]["a3_ris_calibration"]
    add_rect(s26, 78.7, 544, 550, 122, C["teal_soft"], C["teal"], 0.9, rounded=True)
    add_textbox(s26, "补充测试：宽带精细建模的必要性 & RIS 装歪了会不会崩", 94, 552, 520, 22, size_pt=10.6, color=C["navy"], bold=True)
    add_rich_bullets(
        s26,
        [
            ("精细宽带 vs 偷懒简化：", f"盲区中位误差为 {a1['wideband_t2_med_m']*100:.2f} 厘米 vs {a1['narrowband_t2_med_m']*100:.2f} 厘米（用老简化公式会平白多出 25.6% 定位偏差）。"),
            ("RIS 装歪 5~20 厘米：", f"位置误差在 {a3['t2_rmse_m'][0]:.2f} / {a3['t2_rmse_m'][1]:.2f} / {a3['t2_rmse_m'][2]:.2f} / {a3['t2_rmse_m'][3]:.2f} m 间平稳波动，未发散崩溃。"),
        ],
        94, 578, 520, 82, title_pt=9.6, body_pt=9.6, title_color=C["teal"], body_color=C["ink"], space_after_pt=5.0,
    )

    add_rect(s26, 654.7, 544, 550, 122, C["white"], C["card_border"], 0.9, rounded=True)
    add_textbox(s26, "4 项核心工程边界一眼记牢", 670, 552, 520, 22, size_pt=10.6, color=C["navy"], bold=True)
    add_rich_bullets(
        s26,
        [
            ("网速与抓捕门限：", "手机要求 10 dB 内游刃有余（3.9 cm），16 dB 出现折中拐点；信号达 16 dB 即可 99.9% 稳定抓到盲区目标。"),
            ("初始猜测与耗电：", "初始猜偏 ≤2 m 可保 ≥90% 抓捕率；飞 50 m 仅耗 5 秒，占 30 秒悬停服务（6,559 次测量）总耗电仅 12.6%。"),
        ],
        670, 578, 520, 82, title_pt=9.6, body_pt=9.6, title_color=C["navy"], body_color=C["ink"], space_after_pt=5.0,
    )

    # =========================================================================
    # SLIDE 27 (26 / 总结与下一步)
    # =========================================================================
    s27 = new_page(
        prs,
        "26 / 总结与下一步",
        "本阶段收获、局限说明与下一步论文计划",
        27,
        "【汇报讲稿】最后总结一下本阶段的 3 个核心收获和后续安排：\n"
        "第一，我们把上轮遗留的两个关键问题彻底闭环了：同位置加 RIS 净增 +69.3 个百分点，无人机移动比最优固定站净增 +46.3 个百分点；\n"
        "第二，通过捡回全频段能量、RIS “斜扫 8 组”治好左右模糊、以及拐角防踩坑选位，把纯盲区定位压到了 2.7 到 3.8 厘米，比现有论文方法准了 85 倍；\n"
        "第三，900 组全量仿真、5 项压力测试、以及 6 组 IEEE 期刊标准的英文高清矢量图全部已经生成并存档，具备了直接起草 SCI 期刊论文的扎实底子。\n"
        "同时我们也非常清楚当前边界：目前模拟的是静止目标和无人机飞到位后悬停测量，还没做高速移动目标追踪和真实外场硬件测试，这部分会在论文讨论与后续工作中如实说明。请老师批评指正！",
    )

    add_rect(s27, 78.7, 148, 545, 424, C["white"], C["teal"], 1.0, rounded=True)
    add_textbox(s27, "本阶段已经彻底搞定的 3 件事", 102, 164, 500, 30, size_pt=15.0, color=C["teal"], bold=True)
    add_rich_bullets(
        s27,
        [
            ("1. 功劳算得明明白白（不再混淆）\n", "在完全相同位置下，加上无源 RIS 净涨 +69.3 个百分点；相比全街最优固定基站，无人机移动再净涨 +46.3 个百分点，两者缺一不可。"),
            ("2. 彻底治好盲区左右模糊与大误差\n", "捡回 99% 全频段能量 + RIS “斜扫 8 组” + 拐角防踩坑选位，把巷子盲区定位压到 2.7–3.8 厘米（比现有主流方法准 85 倍）。"),
            ("3. 论文级数据与矢量插图已全部就绪\n", "900 组全量测试（7,200 条完整记录）、5 项压力测试与 6 组英文 IEEE 矢量图（PDF/EPS）已全部自动生成并同步备份。"),
        ],
        102, 206, 498, 352, title_pt=11.8, body_pt=10.8, title_color=C["navy"], body_color=C["ink"], space_after_pt=14.0,
    )

    add_rect(s27, 658.7, 148, 546, 424, C["white"], C["card_border"], 1.0, rounded=True)
    add_textbox(s27, "下一步工作与期刊投稿计划", 682, 164, 500, 30, size_pt=15.0, color=C["navy"], bold=True)
    add_rich_bullets(
        s27,
        [
            ("1. 启动英文期刊论文撰写（目标 SCI 2 区/1 区）\n", "瞄准 IEEE TVT / IoT-J / TCOM 等主流期刊，按“真实街谷遮挡动机 → 破除盲区脸盲原理 → 联合选位算法 → 900 组公平验证”主线成稿。"),
            ("2. 图表与实验表格直接入稿\n", "6 组英文期刊高清矢量图均由统一脚本直接从服务器审计数据生成，保证正文数字与图表 100% 一致可复现。"),
            ("3. 后续研究扩展方向（作为下一阶段课题）\n", "从当前“静止目标 + 悬停定位”进一步扩展到“运动车辆连续追踪”，并探索引入实测信道与硬件校准。"),
        ],
        682, 206, 498, 352, title_pt=11.8, body_pt=10.8, title_color=C["navy"], body_color=C["ink"], space_after_pt=14.0,
    )

    add_rect(s27, 78.7, 592, 1126, 74, C["rose_soft"], C["rose"], 1.0, rounded=True)
    add_textbox(
        s27,
        "坦诚说明当前边界：本阶段验证的是城市街谷中“静止目标 + 无人机飞到位后悬停测量”的单次定位效果；"
        "暂未模拟高速移动目标追踪、飞行途中连续测量，也尚未拉真实硬件进行外场实测，汇报与论文中均会如实限定范围。",
        96, 602, 1092, 56, size_pt=10.6, color=C["rose"], bold=True, line_spacing=1.22,
    )

    out_path = BUILD_DIR / "appendix_nlos_crb.pptx"
    prs.save(str(out_path))
    print(f"Built plain-Chinese 7-slide appendix PPTX: {out_path}")
    return out_path


if __name__ == "__main__":
    build_deck()
