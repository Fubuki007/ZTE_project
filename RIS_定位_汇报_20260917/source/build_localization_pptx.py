import zipfile, os, re, shutil
base = r'D:\AA 学习项目\AAA 智能反射面辅助通信感知\AAA ZTE_project'
tpl = os.path.join(base, r'RIS_SI_单篇汇报_Wu2023_20260917\RIS抑制全双工自干扰_单篇论文汇报_Wu2023.pptx')
out = os.path.join(base, r'RIS_定位_汇报_20260917\RIS辅助定位_通俗汇报.pptx')
slide_dir = os.path.join(base, r'RIS_定位_汇报_20260917\slides')
def slide_xml(rid):
    return f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr><p:pic><p:nvPicPr><p:cNvPr id="2" name="Picture 1"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed="{rid}"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="12192000" cy="6858000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>'''
zin = zipfile.ZipFile(tpl, 'r')
zout = zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED)
for item in zin.infolist():
    fn = item.filename
    if item.is_dir():
        continue
    if fn == '[Content_Types].xml':
        ct = zin.read(fn).decode('utf-8')
        if 'Extension="png"' not in ct:
            ct = ct.replace('</Types>', '<Default Extension="png" ContentType="image/png"/></Types>')
        zout.writestr(fn, ct)
        continue
    if re.match(r'ppt/slides/slide\d+\.xml$', fn) or re.match(r'ppt/slides/_rels/slide\d+\.xml\.rels$', fn):
        continue
    zout.writestr(fn, zin.read(fn))
for i in range(1, 11):
    img_name = f'ppt/media/slide{i}.png'
    img_path = os.path.join(slide_dir, f'slide{i}.png')
    zout.write(img_path, img_name)
    old_rels = zin.read(f'ppt/slides/_rels/slide{i}.xml.rels').decode('utf-8')
    m = re.search(r'Target="([^"]*slideLayout[^"]*)"', old_rels)
    layout = m.group(1) if m else '../slideLayouts/slideLayout1.xml'
    rels = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="{layout}"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/slide{i}.png"/></Relationships>'''
    zout.writestr(f'ppt/slides/slide{i}.xml', slide_xml('rId2'))
    zout.writestr(f'ppt/slides/_rels/slide{i}.xml.rels', rels)
zin.close(); zout.close()
print('pptx built:', out)
