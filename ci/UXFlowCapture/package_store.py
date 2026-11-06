"""Package unedited XCTest PNGs at their native App Store sizes; standard library only."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import re
import shutil
import struct

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('output', type=Path)
parser.add_argument('exports', type=Path, nargs='+')
args = parser.parse_args()
manifest = []
for export in args.exports:
    for test in json.loads((export / 'manifest.json').read_text()):
        for item in test['attachments']:
            source = export / item['exportedFileName']
            name = re.sub(r'_\d+_[A-Fa-f0-9-]+\.png$', '', item['suggestedHumanReadableName'])
            match = re.fullmatch(r'redesign-(en|ar|tr)-(home|collection|collection-settings|record-new|record-detail|settings)', name)
            if source.suffix != '.png' or not match:
                continue
            data = source.read_bytes()
            if data[:8] != b'\x89PNG\r\n\x1a\n':
                raise ValueError('Expected a native PNG screenshot')
            width, height = struct.unpack('>II', data[16:24])
            family = {(1206, 2622): 'iphone-6.3', (1320, 2868): 'iphone-6.9', (2064, 2752): 'ipad-13'}.get((width, height))
            if not family:
                raise ValueError(f'Unsupported screenshot size: {width} x {height}')
            locale = {'en': 'en-US', 'ar': 'ar-SA', 'tr': 'tr'}[match[1]]
            target = args.output / locale / family / (name + '.png')
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            manifest.append({'file': str(target.relative_to(args.output)), 'locale': locale,
                             'device': family, 'screen': match[2], 'width': width, 'height': height,
                             'sha256': hashlib.sha256(data).hexdigest(), 'fixture': 'fictional records',
                             'source': str(export)})
args.output.mkdir(parents=True, exist_ok=True)
(args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
cards = ''.join(f'<figure><a href="{html.escape(x["file"])}"><img loading="lazy" src="{html.escape(x["file"])}" alt="{html.escape(x["screen"])}"></a><figcaption>{x["locale"]} · {x["device"]} · {x["screen"]}</figcaption></figure>' for x in manifest)
(args.output / 'index.html').write_text('''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Arca build 8 · Store screenshots</title><style>body{margin:2rem;background:#f7f4eb;color:#143d2e;font:17px system-ui}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:1.5rem}figure{margin:0}img{width:100%;border-radius:16px}figcaption{padding:.5rem}a:focus-visible{outline:3px solid #94550e}</style><h1>Arca · Store screenshots</h1><p>Current native UI with fictional records. Original PNGs are unchanged. Click a screenshot to open its upload file.</p><main>''' + cards + '</main></html>')
print(json.dumps({'screenshots': len(manifest), 'devices': sorted({x['device'] for x in manifest})}))
