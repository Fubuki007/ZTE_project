from PIL import Image, ImageDraw, ImageFont
import os
OUT = r'D:\AA 学习项目\AAA 智能反射面辅助通信感知\AAA ZTE_project\RIS_定位_汇报_20260917\slides'
os.makedirs(OUT, exist_ok=True)
W, H = 1920, 1080
NAVY=(18,53,91); ORANGE=(232,117,26); DARK=(31,41,55); LIGHT=(247,249,252)
WHITE=(255,255,255); GRAY=(107,114,128); SOFT=(235,242,252)
T = ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc', 62)
B = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 38)
BS = ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc', 40)
S = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 30)
def wrap(d, text, font, maxw):
    lines=[]; cur=''
    for ch in text:
        if d.textlength(cur+ch, font=font) <= maxw:
            cur+=ch
        else:
            lines.append(cur); cur=ch
    if cur: lines.append(cur)
    return lines
def draw_slide(idx, title, bullets, image=None):
    img=Image.new('RGB',(W,H),LIGHT); d=ImageDraw.Draw(img)
    d.rectangle([0,0,W,120], fill=NAVY); d.rectangle([0,120,W,130], fill=ORANGE)
    d.text((80,26), title, font=T, fill=WHITE)
    y=180
    for text,color in bullets:
        font=B if not text.startswith('@') else BS
        if text.startswith('@'): text=text[1:]
        lines=wrap(d, text, font, 1680)
        for line in lines:
            d.text((90,y), line, font=font, fill=color); y+=52
        y+=10
    if image and os.path.exists(image):
        im=Image.open(image).convert('RGBA')
        maxw=W-180; maxh=H-y-100
        scale=min(maxw/im.width, maxh/im.height)
        nw,nh=int(im.width*scale), int(im.height*scale)
        im=im.resize((nw,nh), Image.LANCZOS)
        img.paste(im, ((W-nw)//2, y+10), im)
    d.text((80,H-55), 'RIS 辅助定位：通俗解释与系统关系', font=S, fill=GRAY)
    d.text((W-100,H-55), str(idx), font=S, fill=GRAY)
    img.save(os.path.join(OUT, f'slide{idx}.png'))
img=Image.new('RGB',(W,H),NAVY); d=ImageDraw.Draw(img)
d.rectangle([160,620,1760,630], fill=ORANGE)
d.text((160,330),'RIS 辅助定位：把复杂问题讲简单',font=ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc',78),fill=WHITE)
d.text((160,470),'基站、RIS、用户/目标的关系与定位原理',font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',44),fill=WHITE)
d.text((160,760),'汇报人：________    日期：2026-09-17',font=S,fill=(210,225,245))
img.save(os.path.join(OUT,'slide1.png'))
draw_slide(2,'一句话讲清 RIS 辅助定位',[
('@RIS 是一面位置已知、可以编程的镜子。',NAVY),
('它不主动发信号，也不主动测距，只负责把基站信号反射到目标/用户。',DARK),
('• 被定位的是用户/目标，不是 RIS 自己',DARK),
('• 信号路径：基站 → RIS → 用户/目标',DARK),
('• 接收端测量时延、角度、多普勒，反推出位置',DARK)])
draw_slide(3,'先分清两件事',[
('@RIS 自己的位置',(22,128,61)),
('• 固定安装：安装时用测量、图纸、BIM 标定，之后当成已知锚点',DARK),
('• RIS 是无源器件，不能主动报告我在哪',DARK),
('• 如果是无人机/车载移动 RIS：用 GPS/IMU，或与用户位置联合估计',DARK),
('@被定位目标/用户的位置',ORANGE),
('• 基站位置已知，RIS 位置和朝向已知，目标位置未知',DARK),
('• 通过基站到 RIS 到目标的反射路径来定位',DARK),
('• 测量量：时延→距离，角度→方向，多普勒→速度',DARK)])
draw_slide(4,'生活中的比喻：黑屋、手电筒和镜子',[
('• 你在黑屋里想找一个人',DARK),
('• 手电筒是基站，镜子是 RIS，人是目标',DARK),
('• 光绕了多久 → 人离镜子有多远',DARK),
('• 光从哪个方向回来 → 人在镜子的哪个方向',DARK),
('• 距离给一个圈，方向给一条线，圈和线相交就是位置',NAVY)])
draw_slide(5,'系统关系图：基站、RIS、用户/目标',[
('• 基站 BS：已知位置，负责发射信号',DARK),
('• RIS：已知位置和朝向，像可控镜子',DARK),
('• 用户/目标：未知位置，是定位对象',DARK),
('• 直射路径可能被遮挡，RIS 提供虚拟视距',DARK)],
r'D:\AA 学习项目\AAA 智能反射面辅助通信感知\AAA ZTE_project\RIS_定位_汇报_20260917\ris_system_relation.png')
draw_slide(6,'定位原理：距离圈加方向线',[
('• 距离来自信号时延，给出一个距离圈',DARK),
('• 方向来自 RIS 阵列或波束扫描，给出一条方向线',DARK),
('• 距离圈和方向线相交，就确定目标位置',NAVY)],
r'D:\AA 学习项目\AAA 智能反射面辅助通信感知\AAA ZTE_project\RIS_定位_汇报_20260917\ris_positioning_principle.png')
draw_slide(7,'为什么一个 RIS 往往不够？',[
('• 单次测量可能有两个对称位置都满足条件，这叫镜像模糊',DARK),
('• 例如只知道目标在 RIS 右边 20 米，但可能在右上或右下',DARK),
('• 解决办法：多放几个 RIS，每个给一个距离圈',DARK),
('• 基站或用户移动，多测几次；利用运动连续测量',DARK),
('• 多 RIS、多测量、多天线、多子载波 → 解模糊、提精度',NAVY)])
draw_slide(8,'远场和近场，用大白话说',[
('@远场',(31,111,235)),
('• RIS 离目标很远，就像看远处的星星',DARK),
('• 只能判断方向，很难判断具体多远',DARK),
('@近场',(22,128,61)),
('• RIS 很大，目标离 RIS 很近',DARK),
('• 不同部位看到的距离不一样，像两只眼睛看近处',DARK),
('• 除了方向，还能判断远近：大 RIS 加近场是提升精度的重要方向',NAVY)])
draw_slide(9,'RIS 自定位 vs RIS 辅助定位',[
('@RIS 辅助定位',NAVY),
('• 基站或网络侧负责接收，通过 RIS 反射路径定位用户/目标',DARK),
('• 适合蜂窝网、ISAC 感知场景',DARK),
('@RIS 自定位',ORANGE),
('• 用户设备自己接收 RIS 反射信号，判断自己在哪',DARK),
('• 适合室内、无 GPS、零接入点场景',DARK),
('• 共同点：RIS 位置都当作已知锚点，区别在谁接收、谁定位',NAVY)])
draw_slide(10,'可以直接对老师说的总结',[
('老师，RIS 辅助定位可以这样理解：',NAVY),
('RIS 本身位置已知，是一面可编程的镜子，也是定位锚点。',DARK),
('基站发信号，经 RIS 反射到目标；接收端测这条路径的时延和方向。',DARK),
('时延告诉我们目标离 RIS 多远，方向告诉我们目标在 RIS 的哪个方向。',DARK),
('距离给一个圈，方向给一条线，圈和线相交，就确定目标位置。',DARK),
('一个 RIS 可能有模糊，多个 RIS 或多次测量可以解决。',DARK),
('如果 RIS 是移动的，才需要 GPS 或和用户位置联合估计。',DARK)])
print('slides done')
