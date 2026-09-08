#!/usr/bin/env python3
"""Download original, explicitly reusable photographs and preserve provenance.

Build-time tool only. Photographs are always available offline in Sokak.
"""
import hashlib
import html
import json
from pathlib import Path
import re
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
SCENES = json.loads((ROOT / 'scripts/scene_catalog.json').read_text())

def reusable_license(name):
    return name == 'CC0' or re.fullmatch(r'CC BY(?:-SA)? [1-4]\.0(?: [a-z]{2})?', name) is not None

HEADERS = {'User-Agent': 'SokakPhotoCuration/1.6 (https://github.com/biblo454647/sokak)'}

def fetch(url):
    for attempt in range(2):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=90).read()
        except urllib.error.HTTPError as error:
            if error.code != 429 or attempt == 1:
                raise
            delay = max(30, int(error.headers.get('Retry-After', '45')))
            if delay > 60:
                raise
            print(f'Commons requested a pause; waiting {delay}s before one retry.', flush=True)
            time.sleep(delay)

def plain(value):
    return html.unescape(re.sub('<[^>]+>', '', value)).strip()

def main():
    folder = ROOT / 'Resources' / 'Scenes'
    folder.mkdir(parents=True, exist_ok=True)
    manifest = []
    for scene in SCENES:
        ident, title, subtitle, source = (scene[k] for k in ['id', 'title', 'subtitle', 'source'])
        winter = 'snow' in scene['conditions']
        query = urllib.parse.urlencode({'action': 'query', 'format': 'json', 'titles': source,
                                       'prop': 'imageinfo', 'iiprop': 'url|size|extmetadata'})
        pages = json.loads(fetch('https://commons.wikimedia.org/w/api.php?' + query))['query']['pages']
        info = next(iter(pages.values()))['imageinfo'][0]
        meta = info['extmetadata']
        license_name = plain(meta['LicenseShortName']['value'])
        assert reusable_license(license_name), license_name
        url = info['url'].split('?')[0]
        extension = Path(urllib.parse.urlparse(url).path).suffix.lower()
        assert extension in {'.jpg', '.jpeg', '.png'}, extension
        path = folder / (ident + extension)
        if not path.exists():
            time.sleep(16)  # Original image downloads are deliberately paced.
            path.write_bytes(fetch(url))
        row = dict(id=ident, title=title, subtitle=subtitle, winter=winter,
                   filename=path.name, width=info['width'], height=info['height'],
                   author=plain(meta['Artist']['value']), license=license_name,
                   licenseURL=meta.get('LicenseUrl', {}).get('value', '').replace('http://', 'https://'),
                   sourceURL=info['descriptionurl'], originalURL=url,
                   description=plain(meta.get('ImageDescription', {}).get('value', '')),
                   sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                   conditions=scene['conditions'], city=scene['city'], country=scene['country'],
                   modifications='Original file unchanged. The app temporarily crops, dims, defocuses and refracts the photograph behind a weather overlay.')
        assert path.stat().st_size == info['size'], f'{ident}: incomplete original download'
        manifest.append(row)
        print(f'{ident}: {row["width"]} × {row["height"]}; {row["license"]}; {row["description"][:140]}', flush=True)
    # Only remove obsolete, generated catalogue assets after every download succeeds.
    expected = {row['filename'] for row in manifest}
    for path in folder.iterdir():
        if path.suffix.lower() in {'.jpg', '.jpeg', '.png'} and path.name not in expected:
            path.unlink()
    (ROOT / 'Resources' / 'scenes.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    credits = ['# Photograph credits', '', 'The photographs are separate licensed works. Original files are bundled unchanged. Display cropping, dimming, defocus, refraction and weather effects are temporary. Each photograph retains the license linked below; CC BY-SA adaptations remain under that license. App source is separately licensed.', '']
    for row in manifest:
        credits += [f'## {row["title"]} — {row["subtitle"]}', '', f'Photo: **{row["author"]}**, [{row["license"]}]({row["licenseURL"]}). [Source and original]({row["sourceURL"]}).', '', f'{row["city"]}, {row["country"]}. {row["width"]} × {row["height"]} pixels. `{row["filename"]}`. {row["modifications"]}', '']
    (ROOT / 'Resources' / 'PHOTO-CREDITS.md').write_text('\n'.join(credits))

if __name__ == '__main__':
    main()
