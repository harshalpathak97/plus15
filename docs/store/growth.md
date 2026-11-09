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

**Status 2026-11-09:** the English listing text is saved in Play Console and the fr-CA listing is filled in, but it is not saved and nothing is sent for review yet. A person has to click Save, then Publishing overview → Send for review. The landing page is live.

**Found on the way:** live 1.0.3 (6) was built with `AI_PROXY_URL=http://10.0.2.2:8787/...` (the emulator's localhost), so Ask +15 is hidden for every user. 1.0.2 had the workers.dev URL. Build 1.0.4 with the `brisbane` or `store-assets` `secrets.json`.

**Next checks:** 2026-11-23 and 2026-12-07. Add a row each time with the same window length.
