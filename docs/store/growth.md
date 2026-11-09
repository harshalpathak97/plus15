# Plus 15: growth log

Source: Play Console (Grow users overview, Store listings). The app has no analytics, so Play Console is the only measurement.

Rule from the r/googleplayconsole "17 installs a month" thread: if the listing conversion rate is at or above about 30%, the listing works and the problem is **visibility**; if it's lower, fix the listing first.

| Date | Window | Device impressions | Listing visitors | Install clicks | Listing conversion | Acquisitions | First opens | MAU | What changed |
|---|---|---|---|---|---|---|---|---|---|
| 2026-11-09 | 28 d (Oct 9 – Nov 5) | 25 | 11 | 10 | 91% (46.2% on the default listing row; 92.9% over 90 days) | 9 | 6 | 7 | Baseline. 1.0.3 live since Oct 31. Title "Plus 15: Calgary +15 Navigator". |

**Diagnosis (2026-11-09):** visibility. Only 25 impressions in 28 days, but 9 of every 10 visitors install. Search terms aren't reported at this volume.

**Changes being tested:**
1. Keyword title and short description, a longer description with FAQ, and an fr-CA listing.
2. Screenshots: **kept the live 8-shot set** (`plus15-wayfinding-01..08`, light, from the play-screenshots campaign). With 91% conversion they aren't the bottleneck. Shot 7 still says "141 places"; fix it the next time the art is touched. The new `phone-1..6.png` in this folder are used on the landing page.
3. A landing page at harshalpathak97.github.io/plus15/ for Google web search.
4. Local outreach (see `outreach.md`).

**Status 2026-11-09:** the English and fr-CA listing changes (4 changes) were approved and published the same day. 1.0.4 (8), with Ask +15 back and the far-start fix, is in review. The landing page is live.

**Found on the way:** live 1.0.3 (6) was built with `AI_PROXY_URL=http://10.0.2.2:8787/...` (the emulator's localhost), so Ask +15 is hidden for every user. 1.0.2 had the workers.dev URL. Fixed in 1.0.4 (7), built 2026-11-09 and not yet uploaded (see `docs/releases.md`).

**2026-11-09, later:** preview video v4 fixes the mid-video glitch: frames 7.9–8.5 s flashed wrong-time footage because a tween outlived its cut, and parallel render workers disagreed on it. It's re-uploaded unlisted as https://www.youtube.com/watch?v=xxW7FkKi67I. Screenshots are now 7 Pixel 11 Pro shots (`make_store.py`), replacing the 8-shot set (which said "141 places").

**Next checks:** 2026-11-23 and 2026-12-07. Add a row each time with the same window length.
