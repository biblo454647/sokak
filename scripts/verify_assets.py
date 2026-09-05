#!/usr/bin/env python3
"""Verify exactly the photographed sources that the app ships."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess

root = Path(__file__).resolve().parents[1]
scenes = json.loads((root / 'Resources/scenes.json').read_text())
assert len(scenes) == 11 and len({s['id'] for s in scenes}) == 11
assert sum(s['winter'] for s in scenes) >= 5
for scene in scenes:
    assert scene['sourceURL'].startswith('https://commons.wikimedia.org/wiki/File:')
    assert scene['licenseURL'].startswith('https://creativecommons.org/licenses/')
    assert scene['license'].startswith('CC BY') and scene['author']
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
print('Passed: 11 original image hashes/dimensions/licenses, winter library, menu-bar bundle, no privacy prompts, 3 audio beds.')
