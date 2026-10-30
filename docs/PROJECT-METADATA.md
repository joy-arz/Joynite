# Bundled Yu-Gi-Oh! client metadata

These entries describe community clients; they do not claim that the clients are official Konami products or provide a compatibility runtime.

| Entry | Project source | Artwork source |
| --- | --- | --- |
| EDOPro | [Project Ignis](https://projectignis.github.io/) and [client repository](https://github.com/edo9300/edopro) | Project Ignis site logo |
| YGOPro | [Fluorohydride/ygopro](https://github.com/Fluorohydride/ygopro) | Client repository menu/deck backgrounds |
| YGOPro Percy | [Project Ignis FAQ](https://projectignis.github.io/faq.html) | YGOPro upstream backgrounds; legacy client kept distinct from EDOPro |
| YGOPro 2 | [N-Field/ygopro2](https://github.com/N-Field/ygopro2) | Client repository Android application icon |
| KoishiPro | [KoishiPro](https://koishi.pro/koishipro/) and [client repository](https://github.com/purerosefallen/ygopro) | Project-site duel/deck screenshots |
| YGO Omega | [Duelists Unite](https://omega.duelistsunite.org/) and [official guide](https://forum.duelistsunite.org/t/ygo-omega-guide/519) | Project-site Omega logo |
| MDPro3 | [Project repository](https://code.moenext.com/sherry_chaos/MDPro3) | Native application icon when installed, or custom artwork; no unrelated cover is substituted |

Source descriptions are paraphrased and bundled for offline use. Artwork URLs point to project assets; images enter the existing per-game cache after download. Links are not download/install commands. Release dates are omitted where an authoritative date has not been established.

Matching ignores case and punctuation using explicit aliases, including Project Ignis, edopro.exe, ygopro_percy.exe, YGOPro2, YGO Omega (Mac), OmegaUpdater and MDPro3.exe. Similar names such as YGOPro Soundtrack and YGO Omega Server do not match. Metadata application preserves launch routes and custom overrides. A catalog entry does not install a game or promise that an old client's online servers remain available.

`desktop/src-tauri/publishers.json` is the maintained source. Run `python3 scripts/sync-publisher-catalog.py --write` after edits, then run the same script without arguments to validate the generated native catalog. CI performs that check for both editions.
