# Google Play screenshots: copy and sequence

Deck: 8 phone screenshots, 1080 × 1920 (`phone-1.png` … `phone-8.png`), plus `feature-graphic.png` (1024 × 500).
Source of truth: the editor project in `marketing/play-screenshots/` (`app-store-screenshots.json`).
Direction: **Swiss Wayfinding** (chosen in Style Lab, see `style-comparison.png`). The deck uses paper and ink grounds, Inter Tight 800, a hairline column grid, and the app's teal route line running through the deck as a thread.

Story: the +15 is confusing, and this app fixes that. Screens 1–3 carry the whole pitch: what it is, why you need it, and what it does.

| # | Headline | Supporting copy | Feature shown (real capture) | Why it sits here |
|---|---|---|---|---|
| 1 | Never get lost in the +15 | Calgary’s indoor skywalks, mapped. | Live route from Bankers Hall to The Bow on the map (11 min · 800 m) | The hook. It names the place (+15, Calgary) and the pain (getting lost), and the route proves the fix. |
| 2 | Find where you’re going | (none) | Search for “bank”: buildings (Bankers Hall, Royal Bank Building, Bankers Court) and places with real logos | Shows you just search for a destination; you don't have to learn the network first. |
| 3 | Your route. Clearly mapped. | (none) | A 10-bridge route from Eau Claire Tower to Bankers Hall, on a large crop | The core promise: a clear line from A to B across downtown. |
| 4 | Stay inside. Skip the cold. | (none, by choice) | Route choices with the **Mostly indoors** card magnified (999 m · 9 bridges) | The Calgary-winter reason to use the +15. We only claim the Mostly indoors option itself, since some routes still have short outdoor legs. |
| 5 | Know every turn | Every bridge, by name. | Live step list (“Cross the +15 bridge over 8 Ave SW into The CORE Shopping Centre”) | Confidence at each transition between buildings. |
| 6 | See what’s connected | (none) | Bankers Hall building card: +15 hours, food court, shopping, “Directions through the +15”, 16 places inside | Each building is a destination worth knowing about. |
| 7 | Built for downtown Calgary | 109 buildings · 141 places | Network map with street names and the “Calgary’s 16 km of heated skywalks” sheet, plus the Directory | Local proof. Both numbers come from the app's own data. |
| 8 | Downtown just got easier. | Navigate Calgary’s +15 with confidence. | App icon, name and the hero route screen | A closing brand frame, not another feature slide. |

Feature graphic: “Never get lost in the +15” and “Calgary’s indoor skywalks, mapped.”, with the icon, the name, the hero screen, and the route thread running into the phone.

## Claims deliberately avoided
- “Without stepping outside”: Mostly indoors routes can still include short outdoor walks.
- “Open now” for all places: only 25 of 144 places have opening hours. (`listing.txt` still says “141 shops … with … open-now status”, which overstates this.)
- Any mention of an AI provider.

## Captures
Captured on the Android emulator (API 35, 1080 × 2400) from a release build of `main`, with status-bar demo mode on (9:41, full battery, no notifications). The +15 was open at capture time, and the location was set inside the real buildings.
