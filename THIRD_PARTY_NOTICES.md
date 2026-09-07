# Licenses and attribution

Sokak's source code, app icon, documentation (except the photograph preview), and original synthesized audio are available under the MIT license. The full text is in `LICENSE` in the repository and `LICENSE.txt` inside the app's Resources folder.

## Photographs

The fifteen bundled photographs are separate works. They are **not covered by Sokak's MIT license**. Each retains its original Creative Commons Attribution-ShareAlike license, author attribution, and source link. Original image files are bundled unchanged.

See [Photograph Credits](https://github.com/biblo454647/sokak/blob/main/Resources/PHOTO-CREDITS.md) and [the asset manifest](https://github.com/biblo454647/sokak/blob/main/Resources/scenes.json) for each image's author, exact license, resolution, original URL, and checksum. Both files are also bundled offline as `PHOTO-CREDITS.md` and `scenes.json` inside the app's Resources folder. Distributed adaptations of these photographs retain their applicable ShareAlike licenses.

The repository's `docs/preview.png` adapts Maurice Flesier's [A snowy evening in Bağcılar, Istanbul](https://commons.wikimedia.org/wiki/File:A_snowy_evening_in_Ba%C4%9Fc%C4%B1lar,_Istanbul.jpg) with display cropping, dimming, and rendered snowfall. The preview is [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).

Starting in 1.3, `docs/rain-window.gif` and the release's `rain-window.mp4` adapt Furkan Akkurt's [Rainy night Galata Bridge area Istanbul 2026](https://commons.wikimedia.org/wiki/File:Rainy_night_Galata_Bridge_area_Istanbul_2026.jpg) with cropping, dimming, defocus, refraction, droplets and animated rain. These adaptations are [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). The earlier 1.2 rain preview adapts M. PINARCI's [Another Rainy Day](https://commons.wikimedia.org/wiki/File:Another_Rainy_Day_-_panoramio.jpg) under [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/).

The motion previews in `docs/snow-window.gif` and the release's `snow-window.mp4` adapt Maurice Flesier's Bağcılar photograph linked above with cropping, dimming, frost and animated snow. These adaptations are [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). The 1.4 rain MP4 includes original synthesized ambience and contact sounds (MIT); its adapted photograph/video retains CC BY-SA 4.0. GIFs and the snow MP4 are silent. The original source photographs remain unchanged in the app.

## Platform components

Sokak uses Apple system frameworks supplied with macOS, subject to Apple's applicable licenses.

The app bundles [Sparkle 2.9.6](https://github.com/sparkle-project/Sparkle/releases/tag/2.9.6), the open-source macOS update framework. Sparkle and its bundled components retain the copyright notices and MIT, BSD and other license terms in `Resources/SPARKLE-LICENSE.txt` in the source and inside the app. The dependency archive is fetched from the official Sparkle release and verified against its pinned SHA-256 by `scripts/fetch_sparkle.sh`.
