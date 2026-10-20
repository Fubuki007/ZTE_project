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
pdfmetrics.registerFont(TTFont('Arial', 'C:/Windows/Fonts/arial.ttf', subfontIndex=0))
pdfmetrics.registerFont(TTFont('ArialBold', 'C:/Windows/Fonts/arialbd.ttf', subfontIndex=0))


class Drawing:
    def __init__(self, stem, title, width, height):
        global W, H
        W, H = width, height
        self.stem = stem
        self.pdf = canvas.Canvas(str(OUT / (self.stem + '.pdf')), pagesize=(W, H))
        self.pdf.setTitle(title)
        self.pdf.setAuthor('System diagram based on the supplied stage-3 manuscript')
        self.svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
                    f'<title>{html.escape(title)}</title>',
                    '<desc>Model-consistent vector illustration based on Section II of the supplied manuscript.</desc>']

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
        font = 'ArialBold' if bold else 'Arial'
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
            self.svg.append(f'<text x="{xx:.3f}" y="{y+dy:.3f}" font-family="Arial, Helvetica, sans-serif" font-size="{s}" font-weight="{weight}" fill="{color}">{html.escape(t)}</text>')
            xx += ww
        return total

    def finish(self):
        self.pdf.showPage()
        self.pdf.save()
        self.svg.append('</svg>')
        (OUT / (self.stem + '.svg')).write_text('\n'.join(self.svg), encoding='utf-8')


# A: stand-alone scene diagram.
d = Drawing('A_system_model_en', '(A) RIS-assisted mmWave MIMO-OFDM ISAC system', 1320, 930)
d.rect(0, 0, W, H, WHITE)
d.text(58, 57, '(A) RIS-assisted mmWave MIMO-OFDM ISAC system', 30, bold=True)
d.line((58, 83), (1262, 83), LINE, 1.5)
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
d.text(645, 156, 'Passive RIS at r', 25, bold=True, align='center')
d.text(655, 350, 'N<sub>R</sub> reflecting elements · Φ<sub>s</sub>', 20, PURPLE, align='center', bg=True)

# Base-station enclosure and antenna tower.
d.rect(58, 412, 278, 297, '#F6F9FC', '#CFDCE8', 1.5, 16)
d.text(73, 395, 'ISAC base station at b', 25, bold=True)
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
d.text(222, 441, 'Tx array: N<sub>tx</sub>', 18, BLUE)
d.line((309,478),tx,BLUE,3.4)

# Receive UPA explicitly drawn as a two-dimensional grid.
d.rect(245, 553, 68, 59, '#E6EEF5', BLUE, 1.6, 2)
for rr in range(3):
    for cc in range(4):
        d.rect(251+cc*15, 560+rr*16, 9, 9, '#6F9ABB', WHITE, .5)
d.line((313,588),rx,ORANGE,3.1,[10,7])
d.text(214, 641, 'Rx UPA: M<sub>rx</sub>', 18, BLUE)
d.text(197, 682, 'Shared OFDM waveform', 18, INK, align='center')

# Generic moving point target; no aircraft/vehicle-specific model is implied.
d.circle(*target, 31, '#F6F8FA', INK, 2.3)
d.circle(*target, 18, None, MUTED, 1.4)
d.circle(*target, 6, INK)
for dx,dy in [(-1,0),(1,0),(0,-1),(0,1)]:
    d.line((target[0]+dx*25,target[1]+dy*25),(target[0]+dx*40,target[1]+dy*40), INK, 2)
d.text(1090, 190, 'Q sensing targets', 25, bold=True, align='center')
d.text(1090, 225, 'Target q at p<sub>q</sub>', 19, align='center')
d.text(1090, 351, '(R<sub>q</sub>, v<sub>q</sub>, θ<sub>q</sub>, φ<sub>q</sub>)', 23, align='center', bg=True)
d.arrow((1155, 385),(1075, 417),INK,2.1,size=10)
d.text(1160, 417, 'v<sub>q</sub> > 0', 19, align='center')
d.text(1134, 459, 'Radial motion; approaching BS is positive', 14, MUTED, align='center')

# Representative single-antenna communication terminal.
d.rect(1081, 614, 47, 77, '#EEF7F3', GREEN, 2.4, 7)
d.rect(1087, 626, 35, 47, WHITE, '#B6D7C8', 1, 2)
d.line((1096,620),(1113,620),GREEN,1.7)
d.circle(1104, 683, 3, GREEN)
d.circle(1170, 632, 11, '#B3CBBE')
d.path([('M',1149,678),('C',1148,646,1191,646,1191,678),('Z',)],None,1,'#B3CBBE')
d.text(1070, 539, 'K communication users', 19, bold=True)
d.text(1090, 573, 'Representative user k', 18, MUTED)
d.text(1124, 731, 'Received signal y<sub>i,k,s</sub>[l]', 21, GREEN, align='center')

# Link annotations. White-backed labels reserve clear visual space.
d.text(350, 335, 'G<sub>t,i</sub>  Shared Tx link', 18, BLUE, bg=True)
d.text(461, 474, 'G<sub>r,i</sub>', 22, ORANGE, bg=True)
d.text(503, 298, 'd<sub>BR</sub>', 21, MUTED, bg=True)
d.text(843, 215, 'R<sub>R,q</sub>', 22, MUTED, align='center', bg=True)
d.text(550, 427, 'Direct illumination', 19, BLUE, bg=True)
d.text(717, 469, 'Target echo', 21, ORANGE, bg=True)
d.text(550, 398, 'R<sub>B,q</sub> = R<sub>q</sub>', 23, INK, bg=True)
d.text(974, 480, 'h<sup>H</sup><sub>RU,i,k</sub>', 23, GREEN, bg=True)
d.text(707, 691, 'h<sup>H</sup><sub>D,i,k</sub>', 23, GREEN, bg=True)
d.text(650, 769, 'x<sub>i,s</sub>[l] = W<sub>i,s</sub> s<sub>i,s</sub>[l]   ·   One transmit signal for communication and sensing', 23, align='center')


d.line((58, 799), (1262, 799), LINE, 1.2)
for xx, col, ds, label in [
    (80, BLUE, None, 'Transmit / target illumination'),
    (500, ORANGE, [10, 7], 'Sensing echo return'),
    (910, GREEN, [12, 5, 2, 5], 'User communication')]:
    d.arrow((xx, 830), (xx+60, 830), col, 2.8, ds, size=10)
    d.text(xx+76, 836, label, 20, col)
d.text(58, 880, 'Passive RIS: unit-modulus reflection coefficients and b<sub>R</sub>-bit phase quantization.', 18, MUTED)
d.text(58, 909, 'Schematic geometry and element counts. Rx UPA: uniform planar receive array.', 18, MUTED)
d.finish()

# B: independent three-dimensional angle-definition diagram.
d = Drawing('B_target_geometry_en', '(B) Target angle definitions', 640, 680)
d.rect(0, 0, W, H, WHITE)
d.text(40, 55, '(B) Target angle definitions', 28, bold=True)
d.line((40, 80), (600, 80), LINE, 1.2)
o = (235, 313)
pxy = (434, 390)
pt = (434, 161)
d.polygon([o, (141, 407), (335, 479), (529, 384)], '#F6F8FA', None)
d.arrow(o, (137, 411), MUTED, 1.8, size=9)
d.arrow(o, (523, 368), MUTED, 1.8, size=9)
d.arrow(o, (235, 113), MUTED, 1.8, size=9)
d.text(117, 435, 'x', 23, MUTED)
d.text(532, 378, 'y', 23, MUTED)
d.text(226, 101, 'z', 23, MUTED)
d.text(210, 341, 'b', 23)
d.line(pt, pxy, MUTED, 1.4, [5, 5])
d.line(o, pxy, MUTED, 1.5, [5, 5])
d.arrow(o, pt, BLUE, 3, size=12)
d.circle(*pt, 5, BLUE)
d.text(450, 159, 'p<sub>q</sub>', 24, BLUE)
d.text(349, 213, 'R<sub>q</sub>', 23, BLUE, bg=True)
d.path([('M', 235, 253), ('C', 254, 251, 276, 262, 283, 276)], PURPLE, 2.4)
d.text(263, 248, 'θ<sub>q</sub>', 24, PURPLE)
d.path([('M', 195, 353), ('C', 230, 376, 272, 370, 291, 335)], PURPLE, 2.4)
d.text(242, 381, 'φ<sub>q</sub>', 24, PURPLE)
d.text(52, 530, 'θ<sub>q</sub>: polar angle measured from the z-axis', 22)
d.text(52, 570, 'φ<sub>q</sub>: azimuth angle in the xy-plane', 22)
d.text(52, 610, 'Elevation above the xy-plane = π/2 − θ<sub>q</sub>', 21, MUTED)
d.text(52, 650, 'R<sub>q</sub> = R<sub>B,q</sub>: distance from the BS to target q', 20, MUTED)
d.finish()

# C: complete ordered paths for one physical target and one physical RIS.
d = Drawing('C_four_sensing_paths_en', '(C) Four sensing paths for each target', 1800, 430)
d.rect(0, 0, W, H, WHITE)
d.text(58, 49, '(C) Four sensing paths for each target', 28, bold=True)
d.text(58, 85, 'First letter: outbound path. Second letter: return path. D = direct; R = via RIS.', 21, MUTED)
for xx, col, ds, label in [(1280, BLUE, None, 'Outbound'), (1530, ORANGE, [8, 5], 'Return')]:
    d.arrow((xx, 75), (xx+65, 75), col, 2.8, ds, size=10)
    d.text(xx+80, 81, label, 20, col)
specs = [
    ('DD', 'Direct outbound / direct return', ['BS', 'Target', 'BS'], 1,
     'τ<sub>DD,q</sub> = 2R<sub>B,q</sub> / c'),
    ('RD', 'Via RIS outbound / direct return', ['BS', 'RIS', 'Target', 'BS'], 2,
     'τ<sub>RD,q</sub> = (d<sub>BR</sub> + R<sub>R,q</sub> + R<sub>B,q</sub>) / c'),
    ('DR', 'Direct outbound / via RIS return', ['BS', 'Target', 'RIS', 'BS'], 1,
     'τ<sub>DR,q</sub> = τ<sub>RD,q</sub>'),
    ('RR', 'Via RIS outbound / via RIS return', ['BS', 'RIS', 'Target', 'RIS', 'BS'], 2,
     'τ<sub>RR,q</sub> = 2(d<sub>BR</sub> + R<sub>R,q</sub>) / c'),
]
for idx, (code, caption, nodes, target_index, delay) in enumerate(specs):
    x = 58 + idx*426
    d.rect(x, 116, 404, 231, '#FAFBFD', LINE, 1.2, 10)
    d.text(x+20, 154, code, 27, INK, bold=True)
    d.text(x+78, 151, caption, 17, MUTED)
    xs = [x+36+j*332/(len(nodes)-1) for j in range(len(nodes))]
    yy = 220
    for j in range(len(nodes)-1):
        col, ds = (BLUE, None) if j < target_index else (ORANGE, [6, 4])
        d.arrow((xs[j]+23, yy), (xs[j+1]-23, yy), col, 2.5, ds, size=8)
    for xx, label in zip(xs, nodes):
        if label == 'RIS':
            d.rect(xx-22, yy-18, 44, 36, '#F0EAF7', '#B19AC8', 1.2, 3)
            d.text(xx, yy+6, label, 16, PURPLE, align='center')
        elif label == 'Target':
            d.circle(xx, yy, 23, '#EDF1F5', '#95A4B3', 1.2)
            d.text(xx, yy+5, label, 13, INK, align='center')
        else:
            d.rect(xx-22, yy-18, 44, 36, '#EAF2F8', '#95B6D0', 1.2, 4)
            d.text(xx, yy+6, label, 17, BLUE, align='center')
    d.text(x+202, 284, delay, 18 if code=='RD' else 20, align='center')
    if code=='RR':
        d.text(x+202, 322, 'Both RIS symbols denote the same physical surface.', 15, MUTED, align='center')
    if code=='DD':
        d.text(x+202, 322, 'Only DD remains when the RIS is off.', 16, MUTED, align='center')
d.text(58, 389, 'All four echoes arise from the same target q. The BS transmits the waveform and receives the echoes.', 20, MUTED)
d.finish()
print('Created A, B, and C as separate English PDF and SVG figures in:', OUT)
