#!/usr/bin/env python3
"""Download original, explicitly reusable photographs and preserve provenance.

Build-time tool only. Sokak itself makes no network requests.
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
SCENES = [
    ('balat', 'Balat', 'An ordinary afternoon', False, 'File:Balat Street (1).jpg'),
    ('balat-lane', 'Balat', 'A neighbourhood café', False, 'File:Balat (Fatih, Istanbul) 09.jpg'),
    ('istiklal-snow', 'İstiklal Caddesi', 'Snow on the avenue', True, 'File:Istanbul photos by J.Lubbock 2015 471.jpg'),
    ('istiklal-winter', 'İstiklal Caddesi', 'A winter walk', True, 'File:Istanbul photos by J.Lubbock 2015 473.jpg'),
    ('sultanahmet-snow', 'Sultanahmet', 'The Blue Mosque in snow', True, 'File:Blue Mosque. Snow.jpg'),
    ('bagcilar-evening', 'Bağcılar', 'A snowy evening', True, 'File:A snowy evening in Bağcılar, Istanbul.jpg'),
    ('bagcilar-night', 'Bağcılar', 'After the city falls quiet', True, 'File:A snowy evening in Istanbul.jpg'),
    ('bagcilar-park', 'Bağcılar', 'Molla Gürani Park in snow', True, 'File:A snowy day in Bağcılar, Istanbul.jpg'),
    ('bagcilar-centre', 'Bağcılar', 'An everyday street', False, 'File:Town center of Bağcılar, Istanbul.jpg'),
    ('bahcelievler', 'Bahçelievler', 'The city passing by', False, 'File:Cars and Streets of Istanbul, Turkey 47.jpg'),
    ('goztepe-rain', 'Göztepe', 'A rainy neighbourhood street', False, 'File:Another Rainy Day - panoramio.jpg'),
]
HEADERS = {'User-Agent': 'SokakSceneResearch/1.1 (open-source desktop app; attribution research)'}

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
    for ident, title, subtitle, winter, source in SCENES:
        query = urllib.parse.urlencode({'action': 'query', 'format': 'json', 'titles': source,
                                       'prop': 'imageinfo', 'iiprop': 'url|size|extmetadata'})
        pages = json.loads(fetch('https://commons.wikimedia.org/w/api.php?' + query))['query']['pages']
        info = next(iter(pages.values()))['imageinfo'][0]
        meta = info['extmetadata']
        license_name = plain(meta['LicenseShortName']['value'])
        assert license_name.startswith(('CC BY', 'CC0', 'Public domain')), license_name
        url = info['url'].split('?')[0]
        path = folder / (ident + '.jpg')
        if not path.exists():
            time.sleep(16)  # Original image downloads are deliberately paced.
            path.write_bytes(fetch(url))
        row = dict(id=ident, title=title, subtitle=subtitle, winter=winter,
                   filename=path.name, width=info['width'], height=info['height'],
                   author=plain(meta['Artist']['value']), license=license_name,
                   licenseURL=meta.get('LicenseUrl', {}).get('value', ''),
                   sourceURL=info['descriptionurl'], originalURL=url,
                   description=plain(meta.get('ImageDescription', {}).get('value', '')),
                   sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                   modifications='Original file unchanged. The app crops to fill the display and adds a temporary weather overlay.')
        manifest.append(row)
        print(f'{ident}: {row["width"]} × {row["height"]}; {row["license"]}; {row["description"][:140]}', flush=True)
    (ROOT / 'Resources' / 'scenes.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    credits = ['# Photograph credits', '', 'The photographs are separate licensed works. Original files are bundled unchanged. Display cropping and weather effects are temporary. Each photograph retains the license linked below; CC BY-SA adaptations remain under that license. App source is separately licensed.', '']
    for row in manifest:
        credits += [f'## {row["title"]} — {row["subtitle"]}', '', f'Photo: **{row["author"]}**, [{row["license"]}]({row["licenseURL"]}). [Source and original]({row["sourceURL"]}).', '', f'{row["width"]} × {row["height"]} pixels. `{row["filename"]}`. {row["modifications"]}', '']
    (ROOT / 'Resources' / 'PHOTO-CREDITS.md').write_text('\n'.join(credits))

if __name__ == '__main__':
    main()
