#!/usr/bin/env python3
"""Verify exactly the photographed sources that the app ships."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
from fetch_scenes import SCENES, reusable_license

root = Path(__file__).resolve().parents[1]
scenes = json.loads((root / 'Resources/scenes.json').read_text())
assert {s['id'] for s in scenes} == {s['id'] for s in SCENES}
assert len({s['id'] for s in scenes}) == len(scenes)
catalogue = {s['id']: s for s in SCENES}
assert sum(s['winter'] for s in scenes) >= 6
assert len({s['city'] for s in scenes if 'rain' in s['conditions']}) >= 6
assert len({s['city'] for s in scenes if s['winter']}) >= 4
assert {p.name for p in (root / 'Resources/Scenes').iterdir() if not p.name.startswith('.')} == {s['filename'] for s in scenes}
for scene in scenes:
    curated = catalogue[scene['id']]
    assert scene['conditions'] == curated['conditions'] and scene['conditions']
    assert scene['winter'] == ('snow' in scene['conditions'])
    assert scene['city'] == curated['city'] and scene['country'] == curated['country']
    assert scene['sourceURL'].startswith('https://commons.wikimedia.org/wiki/File:')
    assert scene['licenseURL'].startswith(('https://creativecommons.org/licenses/', 'https://creativecommons.org/publicdomain/zero/'))
    assert reusable_license(scene['license']) and scene['author']
    assert Path(scene['filename']).name == scene['filename']
    path = root / 'Resources/Scenes' / scene['filename']
    assert hashlib.sha256(path.read_bytes()).hexdigest() == scene['sha256'], path.name
    result = subprocess.run(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', str(path)], capture_output=True, text=True, check=True)
    assert f'pixelWidth: {scene["width"]}' in result.stdout
    assert f'pixelHeight: {scene["height"]}' in result.stdout
plist = plistlib.loads((root / 'Resources/Info.plist').read_bytes())
assert plist['LSUIElement'] and plist['LSMinimumSystemVersion'] == '13.0'
assert not any(key.endswith('UsageDescription') for key in plist)
assert set(p.name for p in (root / 'Resources/Audio').glob('*.m4a')) == {'rain.m4a', 'snow.m4a', 'mist.m4a'}
print(f'Passed: {len(scenes)} original image hashes/dimensions/licenses, weather matching, winter library, menu-bar bundle, no privacy prompts, 3 audio beds.')
