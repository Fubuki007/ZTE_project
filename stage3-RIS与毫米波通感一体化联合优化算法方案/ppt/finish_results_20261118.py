"""Patch custom confidence intervals and audit the combined PPTX without pptx dependencies."""
import hashlib
import json
import math
import re
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

BASE = Path(__file__).resolve().parent
BUILD = BASE / '.build-results-20261118'
NS = {'c': 'http://schemas.openxmlformats.org/drawingml/2006/chart',
      'a': 'http://schemas.openxmlformats.org/drawingml/2006/main',
      'p': 'http://schemas.openxmlformats.org/presentationml/2006/main'}


def patch():
    evidence = json.loads((BUILD / 'evidence.json').read_text(encoding='utf8'))
    count = 0
    with zipfile.ZipFile(BUILD / 'appendix.raw.pptx') as source, zipfile.ZipFile(BUILD / 'appendix.pptx', 'w', zipfile.ZIP_DEFLATED) as out:
        for item in source.infolist():
            data = source.read(item.filename)
            if re.fullmatch(r'ppt/(?:slides/)?charts/chart\d+\.xml', item.filename):
                root = ET.fromstring(data)
                series = root.findall('.//c:scatterChart/c:ser', NS)
                # Only the RMSE chart has values greater than one. Coverage is [0,1].
                if series and any(float(v.text) > 1.1 for s in series for v in s.findall('./c:yVal//c:v', NS)):
                    assert len(series) == 3
                    for s, rcs in zip(series, (10, 100, 1000)):
                        rows = [r for r in evidence['curves'] if r['rcs_m2'] == rcs and r['ris_fine_cases'] > 0]
                        bars = ET.Element(f"{{{NS['c']}}}errBars")
                        for tag, value in [('errDir', 'y'), ('errBarType', 'both'), ('errValType', 'cust'), ('noEndCap', '0')]:
                            ET.SubElement(bars, f"{{{NS['c']}}}{tag}", val=value)
                        for sign, field in [('plus', 'ci95_upper_deg'), ('minus', 'ci95_lower_deg')]:
                            literal = ET.SubElement(ET.SubElement(bars, f"{{{NS['c']}}}{sign}"), f"{{{NS['c']}}}numLit")
                            ET.SubElement(literal, f"{{{NS['c']}}}formatCode").text = '0.0000'
                            ET.SubElement(literal, f"{{{NS['c']}}}ptCount", val=str(len(rows)))
                            for i, row in enumerate(rows):
                                delta = abs(row[field] - row['angle_rmse_deg'])
                                assert math.isfinite(delta) and delta >= 0
                                ET.SubElement(ET.SubElement(literal, f"{{{NS['c']}}}pt", idx=str(i)), f"{{{NS['c']}}}v").text = repr(delta)
                        properties = ET.SubElement(bars, f"{{{NS['c']}}}spPr")
                        line = ET.SubElement(properties, f"{{{NS['a']}}}ln", w='11000')
                        color = s.find('./c:spPr/a:ln/a:solidFill/a:srgbClr', NS)
                        fill = ET.SubElement(line, f"{{{NS['a']}}}solidFill")
                        ET.SubElement(fill, f"{{{NS['a']}}}srgbClr", val=color.get('val') if color is not None else '64748B')
                        children = list(s)
                        insert = next(i for i, child in enumerate(children) if child.tag in (f"{{{NS['c']}}}xVal", f"{{{NS['c']}}}yVal"))
                        s.insert(insert, bars)
                        count += 1
                    data = ET.tostring(root, encoding='utf-8', xml_declaration=True)
                    ET.fromstring(data)
            out.writestr(item, data)
    assert count == 3, count
    print(json.dumps({'custom_CI_series': count, 'output': str(BUILD / 'appendix.pptx')}))


def audit(target):
    target = Path(target)
    with zipfile.ZipFile(target) as z:
        slide_names = sorted((n for n in z.namelist() if re.fullmatch(r'ppt/slides/slide\d+\.xml', n)), key=lambda n: int(re.search(r'(\d+)\.xml', n).group(1)))
        assert len(slide_names) == 18, len(slide_names)
        charts = [n for n in z.namelist() if re.fullmatch(r'ppt/charts/chart\d+\.xml', n)]
        assert len(charts) == 5, len(charts)
        errorbars = sum(len(ET.fromstring(z.read(n)).findall('.//c:errBars', NS)) for n in charts)
        assert errorbars == 3, errorbars
        for n in charts:
            root = ET.fromstring(z.read(n))
            for series in root.findall('.//c:scatterChart/c:ser', NS):
                smooth = series.find('c:smooth', NS)
                assert smooth is None or smooth.get('val') in ('0', 'false')
        tables = []
        for i, name in enumerate(slide_names, 1):
            root = ET.fromstring(z.read(name))
            if root.findall('.//a:tbl', NS):
                tables.append(i)
        assert all(i in tables for i in [12, 16, 17]), tables
        new_text = '\n'.join(''.join(ET.fromstring(z.read(n)).itertext()) for n in slide_names[11:])
        for text in ['70.62%', '77.67%', '8,100', '未定义', '实测信道', '覆盖率']:
            assert text in new_text, text
        source_png = BUILD / 'source'
        final_png = BUILD / 'final'
        from PIL import Image, ImageChops
        original_diffs = []
        def pngs(folder):
            return sorted(folder.glob('*.PNG'), key=lambda p: int(re.search(r'(\d+)', p.stem).group(1)))
        original = pngs(source_png)
        final = pngs(final_png)
        assert len(original) == 11 and len(final) == 18, (len(original), len(final))
        for i, (a, b) in enumerate(zip(original, final[:11]), 1):
            diff = ImageChops.difference(Image.open(a).convert('RGB'), Image.open(b).convert('RGB'))
            original_diffs.append({'slide': i, 'unchanged': diff.getbbox() is None})
        assert all(d['unchanged'] for d in original_diffs), original_diffs
        montage = Image.new('RGB', (1280, 480), (222, 228, 234))
        # Contact sheet is only for inspecting native PowerPoint renders.
        for j, file in enumerate(final[11:]):
            montage.paste(Image.open(file).convert('RGB').resize((316, 178)), ((j % 4) * 320, (j // 4) * 240))
        montage.save(BUILD / 'results-contact.png')
        receipt = {'file': str(target), 'sha256': hashlib.sha256(target.read_bytes()).hexdigest(), 'slides': 18, 'native_charts': len(charts), 'custom_CI_series': errorbars, 'native_table_slides': tables, 'original_slides_pixel_identical': original_diffs}
        (BUILD / 'delivery-audit.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding='utf8')
        print(json.dumps(receipt, ensure_ascii=False))


if __name__ == '__main__':
    if sys.argv[1] == 'patch':
        patch()
    elif sys.argv[1] == 'audit':
        audit(sys.argv[2])
    else:
        raise ValueError('Use patch or audit')
