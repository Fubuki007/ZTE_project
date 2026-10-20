"""Editable vector system diagram, based on Section II of the supplied PDF.

Run with the Codex bundled Python (reportlab). No simulation is performed.
All geometry is schematic. SVG text remains editable; PDF embeds its fonts.
"""
from pathlib import Path
import math
import re
import html
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.colors import HexColor

OUT = Path(__file__).resolve().parent
W, H = 1800, 1140
INK = '#203247'
MUTED = '#657587'
LINE = '#D9E1E8'
BLUE = '#2166A6'
ORANGE = '#C87527'
GREEN = '#237E63'
PURPLE = '#775996'
WHITE = '#FFFFFF'
pdfmetrics.registerFont(TTFont('YaHei', 'C:/Windows/Fonts/msyh.ttc', subfontIndex=0))
pdfmetrics.registerFont(TTFont('YaHeiBold', 'C:/Windows/Fonts/msyhbd.ttc', subfontIndex=0))


class Drawing:
    def __init__(self):
        self.pdf = canvas.Canvas(str(OUT / 'system_model_v1.pdf'), pagesize=(W, H))
        self.pdf.setTitle('RIS-assisted MIMO-OFDM ISAC system - model-consistent draft v1')
        self.pdf.setAuthor('System diagram based on the supplied stage-3 manuscript')
        self.svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
                    '<title>RIS 辅助毫米波 MIMO-OFDM 通感一体化系统</title>',
                    '<desc>一个基站、一个无源RIS、K个通信用户、Q个目标；四类感知路径为DD、RD、DR、RR。theta从z轴量起。</desc>']

    def style(self, stroke=None, fill=None, width=2, dash=None):
        self.pdf.setLineWidth(width)
        self.pdf.setLineCap(1)
        self.pdf.setLineJoin(1)
        self.pdf.setDash(dash or [])
        if stroke:
            self.pdf.setStrokeColor(HexColor(stroke))
        if fill:
            self.pdf.setFillColor(HexColor(fill))
        ds = ' stroke-dasharray="' + ','.join(map(str, dash)) + '"' if dash else ''
        return f'stroke="{stroke or "none"}" fill="{fill or "none"}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"{ds}'

    def rect(self, x, y, w, h, fill=None, stroke=None, width=1.5, radius=0):
        s = self.style(stroke, fill, width)
        self.pdf.roundRect(x, H-y-h, w, h, radius, fill=bool(fill), stroke=bool(stroke))
        self.svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" {s}/>')

    def path(self, commands, stroke=INK, width=2, fill=None, dash=None):
        s = self.style(stroke, fill, width, dash)
        p = self.pdf.beginPath()
        pieces = []
        for c in commands:
            op, *a = c
            pieces.append(op + ' ' + ' '.join(str(round(v, 3)) for v in a))
            if op == 'M': p.moveTo(a[0], H-a[1])
            elif op == 'L': p.lineTo(a[0], H-a[1])
            elif op == 'C': p.curveTo(a[0], H-a[1], a[2], H-a[3], a[4], H-a[5])
            elif op == 'Z': p.close()
        self.pdf.drawPath(p, stroke=bool(stroke), fill=bool(fill))
        self.svg.append(f'<path d="{" ".join(pieces)}" {s}/>')

    def line(self, a, b, color=INK, width=2, dash=None):
        self.path([('M', *a), ('L', *b)], color, width, dash=dash)

    def polygon(self, points, fill, stroke=None, width=1):
        self.path([('M', *points[0])] + [('L', *p) for p in points[1:]] + [('Z',)], stroke, width, fill)

    def circle(self, x, y, r, fill=None, stroke=None, width=2):
        s = self.style(stroke, fill, width)
        self.pdf.circle(x, H-y, r, fill=bool(fill), stroke=bool(stroke))
        self.svg.append(f'<circle cx="{x}" cy="{y}" r="{r}" {s}/>')

    def arrow_head(self, tip, prev, color, size=12):
        dx, dy = tip[0]-prev[0], tip[1]-prev[1]
        n = math.hypot(dx, dy)
        ux, uy = dx/n, dy/n
        self.polygon([tip, (tip[0]-size*ux+size*.43*uy, tip[1]-size*uy-size*.43*ux),
                      (tip[0]-size*ux-size*.43*uy, tip[1]-size*uy+size*.43*ux)], color)

    def arrow(self, a, b, color=INK, width=2.8, dash=None, size=12, controls=None):
        if controls:
            self.path([('M', *a), ('C', *controls[0], *controls[1], *b)], color, width, dash=dash)
            prev = controls[1]
        else:
            self.line(a, b, color, width, dash)
            prev = a
        self.arrow_head(b, prev, color, size)

    def text(self, x, y, content, size=22, color=INK, bold=False, align='left', bg=False):
        """Baseline coordinates; <sub> and <sup> make editable, positioned spans."""
        font = 'YaHeiBold' if bold else 'YaHei'
        parts = []
        for part in re.split(r'(<sub>.*?</sub>|<sup>.*?</sup>)', content):
            if not part: continue
            if part.startswith('<sub>'):
                parts.append((part[5:-6], size*.68, size*.27))
            elif part.startswith('<sup>'):
                parts.append((part[5:-6], size*.68, -size*.43))
            else:
                parts.append((part, size, 0))
        widths = [pdfmetrics.stringWidth(t, font, s) for t, s, dy in parts]
        total = sum(widths)
        xx = x - (total/2 if align == 'center' else total if align == 'right' else 0)
        if bg:
            self.rect(xx-6, y-size-3, total+12, size*1.5, WHITE, radius=3)
        for (t, s, dy), ww in zip(parts, widths):
            self.pdf.setFont(font, s)
            self.pdf.setFillColor(HexColor(color))
            self.pdf.drawString(xx, H-y-dy, t)
            weight = '700' if bold else '400'
            self.svg.append(f'<text x="{xx:.3f}" y="{y+dy:.3f}" font-family="Microsoft YaHei, Noto Sans CJK SC, sans-serif" font-size="{s}" font-weight="{weight}" fill="{color}">{html.escape(t)}</text>')
            xx += ww
        return total

    def finish(self):
        self.pdf.showPage()
        self.pdf.save()
        self.svg.append('</svg>')
        (OUT / 'system_model_v1.svg').write_text('\n'.join(self.svg), encoding='utf-8')


d = Drawing()
d.rect(0, 0, W, H, WHITE)
d.text(58, 57, 'RIS 辅助毫米波 MIMO–OFDM 通感一体化系统', 31, bold=True)
d.text(1740, 55, '系统模型 · 第一版', 18, MUTED, align='right')
d.line((58, 83), (1740, 83), LINE, 1.5)
d.text(58, 125, '(a) 系统场景与信号传播', 23, bold=True)
d.line((1280, 115), (1280, 790), LINE, 1.2)

# Main scene. Every path is drawn before equipment and labels.
# Separate transmit and receive arrays belong to the same co-located BS.
tx, rx = (332, 478), (332, 588)
target = (1090, 282)
ris_tx, ris_rx = (574, 270), (596, 310)
d.arrow(tx, ris_tx, BLUE, 3.4)
d.arrow(ris_rx, rx, ORANGE, 3.1, [10, 7])
d.arrow((706, 239), (1050, 267), BLUE, 3.4)
d.arrow((1051, 298), (729, 279), ORANGE, 3.1, [10, 7])
d.arrow(tx, (1053, 286), BLUE, 3.4)
d.arrow((1061, 309), rx, ORANGE, 3.1, [10, 7])
d.arrow((703, 300), (1080, 629), GREEN, 3.2, [12, 5, 2, 5],
        controls=((867, 347), (1037, 469)))
d.arrow(tx, (1058, 664), GREEN, 3.2, [12, 5, 2, 5],
        controls=((560, 736), (822, 754)))

# RIS tile with perspective, one passive surface, unit-modulus coefficients.
def tile_point(u, v):
    return (566 + 143*u + 19*v, 191 - 25*u + 131*v)
d.polygon([tile_point(0,0), tile_point(1,0), tile_point(1,1), tile_point(0,1)], '#F4EDF9', PURPLE, 2.5)
for row in range(6):
    for col in range(7):
        u0, v0 = (col+.13)/7, (row+.13)/6
        u1, v1 = (col+.87)/7, (row+.87)/6
        d.polygon([tile_point(u0,v0), tile_point(u1,v0), tile_point(u1,v1), tile_point(u0,v1)],
                  '#DCCCEB' if (col+row)%3 else '#C1ACD7', PURPLE, .65)
d.text(645, 156, '无源 RIS · 位置 r', 25, bold=True, align='center')
d.text(645, 351, 'N<sub>R</sub> 个反射单元 · Φ<sub>s</sub>', 22, PURPLE, align='center', bg=True)

# Base-station enclosure and antenna tower.
d.rect(58, 412, 278, 297, '#F6F9FC', '#CFDCE8', 1.5, 16)
d.text(73, 395, '通感基站 BS · 位置 b', 25, bold=True)
d.line((132, 464), (94, 629), INK, 3)
d.line((132, 464), (170, 629), INK, 3)
d.line((88, 630), (176, 630), INK, 3)
for y in [510, 552, 591]:
    left = 132-(y-464)*38/165
    right = 132+(y-464)*38/165
    next_y = min(y+41, 629)
    next_left = 132-(next_y-464)*38/165
    next_right = 132+(next_y-464)*38/165
    d.line((left,y), (right,y), MUTED, 1.8)
    d.line((left,y), (next_right,next_y), MUTED, 1.5)
    d.line((right,y), (next_left,next_y), MUTED, 1.5)
d.circle(132, 456, 7, BLUE)
for rr in [19, 31]:
    for sign in [-1,1]:
        pts = [(132+sign*rr*math.cos(t),456+rr*math.sin(t)) for t in [-.8,-.6,-.4,-.2,0,.2,.4,.6,.8]]
        d.path([('M', *pts[0])] + [('L', *p) for p in pts[1:]], BLUE, 2)

# Transmit array: generic array, not an imposed planar-array assumption.
d.line((281, 448), (281, 510), BLUE, 2)
for yy in [451, 469, 487, 505]:
    d.circle(289, yy, 5.5, '#C9DFEF', BLUE, 1.6)
    d.line((295, yy), (309, yy), BLUE, 1.5)
d.text(222, 441, '发射阵列 N<sub>tx</sub>', 18, BLUE)
d.line((309,478),tx,BLUE,3.4)

# Receive UPA explicitly drawn as a two-dimensional grid.
d.rect(245, 553, 68, 59, '#E6EEF5', BLUE, 1.6, 2)
for rr in range(3):
    for cc in range(4):
        d.rect(251+cc*15, 560+rr*16, 9, 9, '#6F9ABB', WHITE, .5)
d.line((313,588),rx,ORANGE,3.1,[10,7])
d.text(214, 641, '接收面阵 M<sub>rx</sub>', 18, BLUE)
d.text(197, 682, '共用 OFDM 波形', 18, INK, align='center')

# Generic moving point target; no aircraft/vehicle-specific model is implied.
d.circle(*target, 31, '#F6F8FA', INK, 2.3)
d.circle(*target, 18, None, MUTED, 1.4)
d.circle(*target, 6, INK)
for dx,dy in [(-1,0),(1,0),(0,-1),(0,1)]:
    d.line((target[0]+dx*25,target[1]+dy*25),(target[0]+dx*40,target[1]+dy*40), INK, 2)
d.text(1090, 190, 'Q 个感知目标', 25, bold=True, align='center')
d.text(1090, 225, '示出目标 q，位置 p<sub>q</sub>', 19, align='center')
d.text(1090, 351, '(R<sub>q</sub>, v<sub>q</sub>, θ<sub>q</sub>, φ<sub>q</sub>)', 23, align='center', bg=True)
d.arrow((1155, 385),(1075, 417),INK,2.1,size=10)
d.text(1160, 417, 'v<sub>q</sub> > 0', 19, align='center')
d.text(1095, 451, '沿基站径向运动，接近为正', 16, MUTED, align='center')

# Representative single-antenna communication terminal.
d.rect(1081, 614, 47, 77, '#EEF7F3', GREEN, 2.4, 7)
d.rect(1087, 626, 35, 47, WHITE, '#B6D7C8', 1, 2)
d.line((1096,620),(1113,620),GREEN,1.7)
d.circle(1104, 683, 3, GREEN)
d.circle(1170, 632, 11, '#B3CBBE')
d.path([('M',1149,678),('C',1148,646,1191,646,1191,678),('Z',)],None,1,'#B3CBBE')
d.text(1146, 539, 'K 个通信用户', 25, bold=True, align='center')
d.text(1146, 573, '示出用户 k', 18, MUTED, align='center')
d.text(1124, 731, '接收信号 y<sub>i,k,s</sub>[l]', 21, GREEN, align='center')

# Link annotations. White-backed labels reserve clear visual space.
d.text(390, 335, 'G<sub>t,i</sub>  共享发射链路', 20, BLUE, bg=True)
d.text(461, 474, 'G<sub>r,i</sub>', 22, ORANGE, bg=True)
d.text(503, 298, 'd<sub>BR</sub>', 21, MUTED, bg=True)
d.text(843, 215, 'R<sub>R,q</sub>', 22, MUTED, align='center', bg=True)
d.text(810, 349, '直达照射', 21, BLUE, bg=True)
d.text(717, 469, '目标回波', 21, ORANGE, bg=True)
d.text(550, 398, 'R<sub>B,q</sub> = R<sub>q</sub>', 23, INK, bg=True)
d.text(974, 480, 'h<sup>H</sup><sub>RU,i,k</sub>', 23, GREEN, bg=True)
d.text(707, 691, 'h<sup>H</sup><sub>D,i,k</sub>', 23, GREEN, bg=True)
d.text(650, 769, 'x<sub>i,s</sub>[l] = W<sub>i,s</sub> s<sub>i,s</sub>[l]   ·   同一发射信号兼顾通信与感知', 23, align='center')

# Geometry inset: theta is measured from z, not above the horizontal plane.
d.text(1320, 125, '(b) 目标角度定义', 23, bold=True)
o = (1435, 383)
pxy = (1634, 460)
pt = (1634, 231)
d.polygon([o,(1341,477),(1535,549),(1729,454)],'#F6F8FA',None)
d.arrow(o,(1337,481),MUTED,1.8,size=9)
d.arrow(o,(1723,438),MUTED,1.8,size=9)
d.arrow(o,(1435,183),MUTED,1.8,size=9)
d.text(1317,505,'x',21,MUTED)
d.text(1732,448,'y',21,MUTED)
d.text(1426,171,'z',21,MUTED)
d.text(1415,411,'b',21)
d.line(pt,pxy,MUTED,1.4,[5,5])
d.line(o,pxy,MUTED,1.5,[5,5])
d.arrow(o,pt,BLUE,3,size=12)
d.circle(*pt,5,BLUE)
d.text(1650,229,'p<sub>q</sub>',22,BLUE)
d.text(1549,283,'R<sub>q</sub>',21,BLUE,bg=True)
d.path([('M',1435,323),('C',1454,321,1476,332,1483,346)],PURPLE,2.4)
d.text(1463,318,'θ<sub>q</sub>',22,PURPLE)
d.path([('M',1395,423),('C',1430,446,1472,440,1491,405)],PURPLE,2.4)
d.text(1442,451,'φ<sub>q</sub>',22,PURPLE)
d.text(1325,562,'θ<sub>q</sub>：与 z 轴的夹角（极角）',21)
d.text(1325,599,'φ<sub>q</sub>：xy 平面的方位角',21)
d.text(1325,636,'水平面仰角 = π/2 − θ<sub>q</sub>',20,MUTED)

# Legend: distinguish propagation role with both color and line style.
for yy, col, ds, label in [
    (687,BLUE,None,'发射 / 目标照射'),
    (725,ORANGE,[10,7],'感知回波返回基站'),
    (763,GREEN,[12,5,2,5],'用户通信链路')]:
    d.arrow((1325,yy-7),(1385,yy-7),col,2.8,ds,size=10)
    d.text(1401,yy,label,20,col)

# Four ordered paths: each node order exactly matches equations (15)-(21).
d.line((58, 805), (1740, 805), LINE, 1.5)
d.text(58, 847, '(c) 每个目标的四类感知路径', 23, bold=True)
d.text(1740, 847, '第一字母：去程；第二字母：回程。D = 直达，R = 经 RIS', 18, MUTED, align='right')

specs = [
    ('DD','直达去程 / 直达回程',['BS','目标','BS'],1,'τ<sub>DD,q</sub> = 2R<sub>B,q</sub> / c'),
    ('RD','经 RIS 去程 / 直达回程',['BS','RIS','目标','BS'],2,'τ<sub>RD,q</sub> = (d<sub>BR</sub> + R<sub>R,q</sub> + R<sub>B,q</sub>) / c'),
    ('DR','直达去程 / 经 RIS 回程',['BS','目标','RIS','BS'],1,'τ<sub>DR,q</sub> = τ<sub>RD,q</sub>'),
    ('RR','经 RIS 去程 / 经 RIS 回程',['BS','RIS','目标','RIS','BS'],2,'τ<sub>RR,q</sub> = 2(d<sub>BR</sub> + R<sub>R,q</sub>) / c'),
]
for idx,(code,caption,nodes,target_index,delay) in enumerate(specs):
    x = 58+idx*426
    d.rect(x,872,404,208,'#FAFBFD',LINE,1.2,10)
    d.text(x+20,910,code,26,INK,bold=True)
    d.text(x+78,908,caption,18,MUTED)
    xs = [x+36+j*332/(len(nodes)-1) for j in range(len(nodes))]
    yy=961
    for j in range(len(nodes)-1):
        col,ds = (BLUE,None) if j<target_index else (ORANGE,[6,4])
        d.arrow((xs[j]+23,yy),(xs[j+1]-23,yy),col,2.5,ds,size=8)
    for xx,label in zip(xs,nodes):
        if label=='RIS':
            d.rect(xx-22,yy-18,44,36,'#F0EAF7','#B19AC8',1.2,3)
            d.text(xx,yy+6,label,15,PURPLE,align='center')
        elif label=='目标':
            d.circle(xx,yy,21,'#EDF1F5','#95A4B3',1.2)
            d.text(xx,yy+5,label,14,INK,align='center')
        else:
            d.rect(xx-22,yy-18,44,36,'#EAF2F8','#95B6D0',1.2,4)
            d.text(xx,yy+6,label,16,BLUE,align='center')
    d.text(x+202,1023,delay,17 if code=='RD' else 19,align='center')
    if code=='RR': d.text(x+202,1056,'两个 RIS 标记表示同一 RIS 的两次反射',14,MUTED,align='center')
    if code=='DD': d.text(x+202,1056,'关闭 RIS 时仅保留该项',15,MUTED,align='center')

d.text(58,1115,'示意图不按实际距离绘制；阵元数量为示意。RIS 相位按 b<sub>R</sub> 位量化，反射系数模值为 1。',17,MUTED)
d.text(1740,1115,'依据：原文第 II 节，式 (1)–(27)',16,MUTED,align='right')
d.finish()
print(OUT / 'system_model_v1.pdf')
print(OUT / 'system_model_v1.svg')
