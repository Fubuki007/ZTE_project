"""Retrieve public research metadata and selected HTML text; no simulation."""
import argparse
from datetime import datetime, timezone
import json
from html.parser import HTMLParser
from pathlib import Path
import re
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
NS = {'a': 'http://www.w3.org/2005/Atom', 'r': 'http://arxiv.org/schemas/atom'}
QUERIES = {
    'fas_isac': '(ti:"fluid antenna" OR ti:"movable antenna") AND (all:"sensing" OR all:"localization")',
    'ris_unfolding': '(all:"reconfigurable intelligent surface" OR all:"RIS") AND (all:"deep unfolding" OR all:"unrolled") AND (all:"sensing" OR all:"ISAC")',
    'fas_learning': '(all:"sensing" OR all:"ISAC") AND (all:"fluid antenna" OR all:"movable antenna") AND (all:"learning" OR all:"Bayesian")',
    'ris_crb': 'all:"reconfigurable intelligent surface" AND all:"sensing" AND (all:"Cramer" OR all:"CRB")',
    'ris_learning': '(all:"RIS" OR all:"intelligent reflecting surface") AND all:"sensing" AND (all:"learning" OR all:"neural")',
    'wideband_fas': 'all:"wideband" AND (all:"fluid antenna" OR all:"movable antenna")',
}


def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'ZTE-Stage3-LiteratureReview/1.0'})
    with urllib.request.urlopen(req, timeout=35) as response:
        return response.read().decode('utf-8', 'replace')


def save_json(path, obj):
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def parse_feed(raw):
    root = ET.fromstring(raw)
    out = []
    for entry in root.findall('a:entry', NS):
        def field(name):
            value = entry.findtext(name, default='', namespaces=NS)
            return ' '.join(value.split()) or None
        out.append(dict(id=field('a:id'), title=field('a:title'),
                        abstract=field('a:summary'), published=field('a:published'),
                        updated=field('a:updated'), doi=field('r:doi'),
                        journal_ref=field('r:journal_ref'), comment=field('r:comment'),
                        authors=[a.findtext('a:name', namespaces=NS)
                                 for a in entry.findall('a:author', NS)]))
    return out


def search():
    evidence = ROOT/'evidence'
    evidence.mkdir(parents=True, exist_ok=True)
    report = dict(retrieved_at_utc=datetime.now(timezone.utc).isoformat(),
                  scope='Targeted arXiv search, not an exhaustive novelty review', searches=[])
    for index, (label, query) in enumerate(QUERIES.items()):
        if index:
            time.sleep(3.2)  # arXiv API guidance
        url = 'https://export.arxiv.org/api/query?' + urllib.parse.urlencode(
            dict(search_query=query, start=0, max_results=30, sortBy='relevance'))
        raw = get(url)
        (evidence/f'{label}.xml').write_text(raw, encoding='utf-8')
        papers = parse_feed(raw)
        report['searches'].append(dict(label=label, query=query, url=url, papers=papers))
        save_json(ROOT/'search_results.json', report)
        print(label, len(papers), flush=True)
        for p in papers:
            print(p['id'].rsplit('/', 1)[-1], p['published'][:4], p['title'], flush=True)


def metadata(ids):
    url = 'https://export.arxiv.org/api/query?' + urllib.parse.urlencode(
        dict(id_list=','.join(ids), max_results=len(ids)))
    raw = get(url)
    (ROOT/'evidence'/'selected_metadata.xml').write_text(raw, encoding='utf-8')
    papers = parse_feed(raw)
    save_json(ROOT/'selected_metadata.json', dict(retrieved_at_utc=datetime.now(timezone.utc).isoformat(),
                                                source_url=url, papers=papers))
    for p in papers:
        print(json.dumps(p, ensure_ascii=False), flush=True)


def html(ids):
    class TextParser(HTMLParser):
        def __init__(self):
            super().__init__(convert_charrefs=True)
            self.article = False
            self.skip = 0
            self.parts = []

        def handle_starttag(self, tag, attrs):
            if tag == 'article':
                self.article = True
            if not self.article:
                return
            if tag in ('script', 'style', 'annotation'):
                self.skip += 1
            if tag == 'math':
                self.parts.append(' '+dict(attrs).get('alttext', '')+' ')
                self.skip += 1
            if tag in ('p', 'h1', 'h2', 'h3', 'h4', 'figcaption', 'tr'):
                self.parts.append('\n\n')

        def handle_endtag(self, tag):
            if tag == 'article':
                self.article = False
            if tag in ('script', 'style', 'annotation', 'math') and self.skip:
                self.skip -= 1

        def handle_data(self, data):
            if self.article and not self.skip:
                self.parts.append(data)

    out = ROOT/'fulltext'
    out.mkdir(parents=True, exist_ok=True)
    for index, ident in enumerate(ids):
        if index:
            time.sleep(1)
        url = 'https://arxiv.org/html/' + ident
        try:
            raw = get(url)
        except Exception as exc:
            print(ident, 'FETCH_ERROR', type(exc).__name__, str(exc), flush=True)
            with (ROOT/'evidence'/'fetch_errors.txt').open('a', encoding='utf-8') as stream:
                stream.write(f'{url}: {type(exc).__name__}: {exc}\n')
            continue
        parser = TextParser()
        parser.feed(raw)
        paragraphs = [re.sub(r'\s+', ' ', p).strip() for p in ''.join(parser.parts).split('\n\n')]
        text = '\n\n'.join(p for p in paragraphs if p)
        (out/f'{ident}.txt').write_text('Source: '+url+'\n\n'+'\n\n'.join(paragraphs), encoding='utf-8')
        print(ident, 'characters', len(text), 'paragraphs', len(paragraphs), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['search', 'metadata', 'html'])
    parser.add_argument('ids', nargs='*')
    args = parser.parse_args()
    ROOT.mkdir(parents=True, exist_ok=True)
    (ROOT/'evidence').mkdir(exist_ok=True)
    if args.mode == 'search':
        search()
    elif args.mode == 'metadata':
        metadata(args.ids)
    else:
        html(args.ids)
