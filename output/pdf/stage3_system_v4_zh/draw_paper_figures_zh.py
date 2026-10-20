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
INK = '#202020'
MUTED = '#657587'
LINE = '#D9E1E8'
BLUE = '#365F7D'
ORANGE = '#A26648'
GREEN = '#4F8067'
PURPLE = '#847197'
WHITE = '#FFFFFF'
pdfmetrics.registerFont(TTFont('Times', 'C:/Windows/Fonts/times.ttf', subfontIndex=0))
pdfmetrics.registerFont(TTFont('TimesBold', 'C:/Windows/Fonts/timesbd.ttf', subfontIndex=0))


pdfmetrics.registerFont(TTFont('Song', 'C:/Windows/Fonts/simsun.ttc', subfontIndex=0))
pdfmetrics.registerFont(TTFont('TimesItalic', 'C:/Windows/Fonts/timesi.ttf'))

class Drawing:
    def __init__(self, stem, title, width, height, width_mm=178):
        global W, H
        W, H = width, height
        self.stem = stem
        scale = width_mm * 72 / 25.4 / W
        self.pdf = canvas.Canvas(str(OUT / (self.stem + '.pdf')), pagesize=(W*scale, H*scale))
        self.pdf.scale(scale, scale)
        self.pdf.setTitle(title)
        self.pdf.setAuthor('System diagram based on the supplied stage-3 manuscript')
        self.svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width_mm}mm" height="{width_mm*H/W:.4f}mm" viewBox="0 0 {W} {H}">',
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

    def text(self, x, y, content, size=20, color=INK, bold=False, align='left', bg=False, italic=False):
        is_chinese = any('\u4e00' <= char <= '\u9fff' for char in content)
        font = 'Song' if is_chinese else 'TimesBold' if bold else 'TimesItalic' if italic else 'Times'
        family = 'SimSun, Songti SC, serif' if is_chinese else 'Times New Roman, Times, serif'
        spans = []
        cursor = 0
        anchor = 0
        script_width = 0
        previous_kind = None
        for part in re.split(r'(<sub>.*?</sub>|<sup>.*?</sup>)', content):
            if not part:
                continue
            kind = 'sub' if part.startswith('<sub>') else 'sup' if part.startswith('<sup>') else None
            if kind:
                text = part[5:-6]
                fs = size*.7
                dy = size*.23 if kind == 'sub' else -size*.42
                width = pdfmetrics.stringWidth(text, font, fs)
                if previous_kind and previous_kind != kind:
                    script_width = max(script_width, width)
                else:
                    anchor = cursor
                    script_width = width
                spans.append((anchor, text, fs, dy))
                cursor = anchor+script_width
            else:
                fs, dy, text = size, 0, part
                spans.append((cursor, text, fs, dy))
                cursor += pdfmetrics.stringWidth(text, font, fs)
            previous_kind = kind
        xx = x - (cursor/2 if align == 'center' else cursor if align == 'right' else 0)
        if bg:
            self.rect(xx-3, y-size, cursor+6, size*1.35, WHITE)
        for offset, text, fs, dy in spans:
            self.pdf.setFont(font, fs)
            self.pdf.setFillColor(HexColor(color))
            self.pdf.drawString(xx+offset, H-y-dy, text)
            weight = '700' if bold else '400'
            style = 'italic' if italic else 'normal'
            self.svg.append(f'<text x="{xx+offset:.3f}" y="{y+dy:.3f}" font-family="{family}" font-size="{fs}" font-weight="{weight}" font-style="{style}" fill="{color}">{html.escape(text)}</text>')
        return cursor

    def finish(self):
        self.pdf.showPage()
        self.pdf.save()
        self.svg.append('</svg>')
        (OUT / (self.stem + '.svg')).write_text('\n'.join(self.svg), encoding='utf-8')



# Publication figures: no embedded titles, captions, or explanatory paragraphs.
# A and C use 178 mm width; B uses 85 mm width.

def ris(d, x, y, w=88, h=76):
    def p(u, v): return (x+w*u+12*v, y-15*u+h*v)
    d.polygon([p(0,0),p(1,0),p(1,1),p(0,1)], '#E9E1EF', INK, 1.3)
    for rr in range(4):
        for cc in range(5):
            u0,u1=(cc+.12)/5,(cc+.88)/5
            v0,v1=(rr+.12)/4,(rr+.88)/4
            d.polygon([p(u0,v0),p(u1,v0),p(u1,v1),p(u0,v1)], '#C2B4D0', '#766681', .7)

def phone(d, x, y):
    d.rect(x, y, 24, 41, '#F1F2F2', '#535353', 1.4, 3)
    d.rect(x+3, y+7, 18, 25, WHITE, '#A5ABAD', .6, 1)
    d.line((x+8,y+4),(x+16,y+4), '#535353', .9)
    d.circle(x+12,y+36,1.6, '#535353')

def antenna(d, x, y):
    d.line((x,y+11),(x,y-8),INK,1.5)
    d.path([('M',x-8,y-16),('L',x,y-8),('L',x+8,y-16)], INK, 1.5)
    d.line((x-8,y-16),(x+8,y-16),INK,1.3)
    for rr in (12,18):
        points=[(x+rr*math.cos(t),y-9+rr*math.sin(t)) for t in (-.6,-.3,0,.3,.6)]
        d.path([('M',*points[0])]+[('L',*p) for p in points[1:]], '#A75445', 1)

def target(d, x, y, radius=13):
    d.circle(x,y,radius,'#D9DCDE',INK,1.2)
    d.circle(x,y,3.2,INK)

def block(d,x,y,w,h,label,fill):
    d.rect(x,y,w,h,fill,INK,1.3,4)
    if label in ('OFDM', 'OFDM'):
        d.text(x+w/2,y+h/2+6,label,18,align='center')
    else:
        d.text(x+w/2,y+h/2+6,label,20,align='center')

d = Drawing('A_system_model_zh', '智能反射面辅助通感系统', 1100, 545)
d.rect(0,0,W,H,WHITE)
# One co-located BS. The waveform branch carries a known reference for sensing.
d.path([('M',20,113),('L',455,113),('L',455,462),('L',20,462),('Z',)], '#A4A4A4', 1, dash=[4,4])
d.text(235,491,'基站',23,align='center')
d.text(40,166,'s<sub>i</sub>[l]',22,italic=True)
d.arrow((84,160),(120,160),INK,1.5,size=7)
block(d,120,136,65,48,'W<sub>i</sub>','#D8CEE2')
d.arrow((185,160),(255,160),INK,1.5,size=7)
d.text(218,140,'x<sub>i</sub>[l]',20,align='center',italic=True)
block(d,255,136,100,48,'OFDM','#F6D8AA')
d.arrow((355,160),(424,160),INK,1.5,size=7)
antenna(d,430,160)
d.text(432,201,'N<sub>tx</sub>',21,align='center',italic=True)
d.rect(418,376,26,28,'#D6E2E9',INK,1.2,1)
for row in range(3):
    for col in range(3):
        d.rect(422+col*7,380+row*7,4,4,'#638296')
d.text(432,430,'M<sub>rx</sub>',21,align='center',italic=True)
d.arrow((418,390),(355,390),INK,1.5,size=7)
block(d,255,366,100,48,'OFDM','#BED7EA')
d.arrow((255,390),(210,390),INK,1.5,size=7)
block(d,105,354,105,72,'感知处理','#C3DDBA')
d.circle(220,160,2.4,INK)
d.path([('M',220,160),('L',220,289),('L',157,289),('L',157,354)],INK,1.3)
d.arrow_head((157,354),(157,335),INK,7)
# Wireless topology: the same surface supports outbound and return paths.
tx,rx=(455,160),(455,390)
d.arrow(tx,(661,83),BLUE,1.9,size=9)
d.arrow((671,128),rx,ORANGE,1.8,[6,4],size=9)
d.arrow(tx,(980,198),BLUE,1.9,size=9)
d.arrow((980,219),rx,ORANGE,1.8,[6,4],size=9)
d.arrow((750,77),(983,185),BLUE,1.9,size=9)
d.arrow((981,211),(766,104),ORANGE,1.8,[6,4],size=9)
d.arrow((743,126),(985,406),GREEN,1.8,[8,3,1.5,3],size=9)
d.arrow(tx,(976,440),GREEN,1.8,[8,3,1.5,3],size=9,
        controls=((555,510),(824,510)))
ris(d,661,50)
d.text(709,27,'RIS',22,align='center')
d.text(716,157,'Φ, N<sub>R</sub>',21,align='center',italic=True)
target(d,1000,205,15)
d.text(1000,167,'目标 q',22,align='center')
phone(d,983,411)
d.text(994,485,'用户 k',22,align='center')
# The distinct BS-RIS matrices and communication channels follow Section II.
d.text(552,111,'G<sub>t,i</sub>',22,italic=True,bg=True)
d.text(548,286,'G<sub>r,i</sub>',22,italic=True,bg=True)
d.text(864,329,'h<sup>H</sup><sub>RU,i,k</sub>',22,italic=True,bg=True)
d.text(690,463,'h<sup>H</sup><sub>D,i,k</sub>',22,italic=True,bg=True)
# A compact legend is the only prose outside the nodes.
for xx,col,ds,label in [(604,BLUE,None,'发射'),(747,ORANGE,[6,4],'回波'),(906,GREEN,[8,3,1.5,3],'通信')]:
    d.arrow((xx,523),(xx+42,523),col,1.8,ds,size=7)
    d.text(xx+53,529,label,19)
d.finish()

# B: the angle itself communicates the polar-angle convention.
d = Drawing('B_target_geometry_zh', '目标几何关系', 440, 400, width_mm=85)
d.rect(0,0,W,H,WHITE)
o=(140,225)
pt=(326,89)
projection=(326,298)
d.polygon([o,(47,317),(236,378),(414,282)],'#F4F5F6',None)
d.arrow(o,(46,319),INK,1.2,size=7)
d.arrow(o,(416,282),INK,1.2,size=7)
d.arrow(o,(140,32),INK,1.2,size=7)
d.text(28,340,'x',19,italic=True)
d.text(419,300,'y',19,italic=True)
d.text(135,21,'z',19,italic=True)
d.text(118,252,'b',19,italic=True)
d.line(pt,projection,'#7D7D7D',1.1,[4,4])
d.line(o,projection,'#7D7D7D',1.1,[4,4])
d.arrow(o,pt,BLUE,1.9,size=8)
d.circle(*pt,3.5,INK)
d.text(340,89,'p<sub>q</sub>',20,italic=True)
d.text(234,145,'R<sub>q</sub>',19,italic=True,bg=True)
d.path([('M',140,164),('C',161,164,183,172,190,188)],INK,1.2)
d.text(166,160,'θ<sub>q</sub>',19,italic=True)
d.path([('M',100,265),('C',135,287,175,278,192,245)],INK,1.2)
d.text(143,290,'φ<sub>q</sub>',19,italic=True)
d.finish()

# C: one physical RIS in each triangular path sketch, including RR.
d = Drawing('C_sensing_paths_zh', '四类感知路径', 1120, 244)
d.rect(0,0,W,H,WHITE)
for idx,code in enumerate(['DD','RD','DR','RR']):
    left=idx*280
    bs=(left+39,159)
    tg=(left+241,159)
    rr=(left+140,43)
    if code=='DD':
        d.arrow((bs[0]+14,151),(tg[0]-15,151),BLUE,1.9,size=8)
        d.arrow((tg[0]-15,169),(bs[0]+14,169),ORANGE,1.8,[6,4],size=8)
    elif code=='RD':
        d.arrow((bs[0]+8,146),(rr[0]-20,61),BLUE,1.9,size=8)
        d.arrow((rr[0]+20,61),(tg[0]-8,146),BLUE,1.9,size=8)
        d.arrow((tg[0]-15,165),(bs[0]+14,165),ORANGE,1.8,[6,4],size=8)
    elif code=='DR':
        d.arrow((bs[0]+14,165),(tg[0]-15,165),BLUE,1.9,size=8)
        d.arrow((tg[0]-8,146),(rr[0]+20,61),ORANGE,1.8,[6,4],size=8)
        d.arrow((rr[0]-20,61),(bs[0]+8,146),ORANGE,1.8,[6,4],size=8)
    else:
        d.arrow((bs[0]+3,145),(rr[0]-22,55),BLUE,1.9,size=8)
        d.arrow((rr[0]+22,55),(tg[0]-3,145),BLUE,1.9,size=8)
        d.arrow((tg[0]-17,151),(rr[0]+14,65),ORANGE,1.8,[6,4],size=8)
        d.arrow((rr[0]-14,65),(bs[0]+17,151),ORANGE,1.8,[6,4],size=8)
    d.rect(bs[0]-12,bs[1]-13,24,26,'#C6DAE6',INK,1.1,2)
    for j in range(3):
        d.line((bs[0]-7,bs[1]-7+j*7),(bs[0]+7,bs[1]-7+j*7),'#65849A',1)
    target(d,*tg,13)
    d.text(bs[0],194,'基站',21,align='center')
    d.text(tg[0],194,'目标',21,align='center')
    if code!='DD':
        d.rect(rr[0]-18,rr[1]-15,36,30,'#D8CCE3',INK,1.1,1)
        for j in [-6,6]: d.line((rr[0]+j,rr[1]-15),(rr[0]+j,rr[1]+15),'#8A789A',.8)
        d.line((rr[0]-18,rr[1]),(rr[0]+18,rr[1]),'#8A789A',.8)
        d.text(rr[0],22,'RIS',19,align='center')
    d.text(left+140,233,code,23,align='center')
d.finish()
print('Created three compact publication figures:', OUT)
