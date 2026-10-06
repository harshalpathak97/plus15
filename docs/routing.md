# +15 routing: data, engine and verification

Routing is built on the City of Calgary's own +15 data. It is cross-checked against the official +15 map, and every edge records where it came from. The engine never infers a connection because two things are close together.

The generated build report, [`network-report.md`](network-report.md), lists what is resolved and what isn't.

## Why this was rebuilt (audit, 2026-09-30)

| Area | Before | Problem |
|---|---|---|
| Data | `bridges.json`: 119 hand-made "bridges" between building points | The City lists 86 bridges. Distances were round guesses, about 28% short. About half didn't match any City bridge. Links like Hyatt ↔ Telus Sky joined the core to the east side, which the City data and official map show as separate networks. City Hall and Harry Hays had no bridges. |
| Buildings | `buildings.json` with coordinates on a 0.0002° grid | Up to about 200 m off. One address was in Edmonton. |
| Model | Buildings were nodes, bridges were edges | Every bridge into a building connected to every other bridge through it, with no interior topology. |
| Geometry | Centroid → invented L-corner → centroid, then Catmull-Rom smoothed | The route line didn't match the network or the real walkway, and GPS tracking used yet another geometry. |
| Directions | A list of building names | There were no instructions. |
| Closures | `status != 'open'` on one bridge | No dates, no source, no City feed. |
| Time | None | Routed at 3 a.m. or on Christmas Day. |
| Accessibility | A 999,999 penalty, not an exclusion | Accessible routes could still use stairs. The flags were boilerplate. |
| Entry points | 20 points equal to building centroids | Not real doors. |

Everything in that table has been deleted and replaced.

## Sources (in order of authority)

1. **City "Plus 15 Bridges", [`fu7z-c7ar`](https://data.calgary.ca/d/fu7z-c7ar).** Each bridge record has its number, the buildings at each end (`location`), the crossing street, the connection type and a polygon.
2. **City "Plus 15", [`3u3x-hrc7`](https://data.calgary.ca/d/3u3x-hrc7).** 238 walkway footprints: bridges, plus the interior +15 walkways inside buildings (`Enclosed`), and open-air walkways.
3. **Official +15 Skywalk Network map v30 (2025)** ([PDF](https://www.calgary.ca/content/dam/www/transportation/roads/documents/plus-15-skywalk-network-map.pdf), sha256 `cd38a346…`). Used for building names, the building sequence, food court/shopping/hotel icons, "no elevator to street" and "route has stairs only".
4. **[calgary.ca/plus15](https://www.calgary.ca/plus15).** Network hours, and the construction and closure table.
5. **OpenStreetMap building entrances** (© OpenStreetMap contributors, ODbL), via Overpass. Street-level public doors (`entrance=main|yes|secondary`, not private, not `level=1` +15 doors) on the outline of the OSM building that contains each +15 building. Refresh with `dart run tool/build_network.dart --refresh-osm`.

Snapshots of sources 1, 2, 4 and 5 are in `tool/sources/`. Hand-curated facts are in `tool/curation.json`, and every entry there cites its source.

## How the graph is built (`tool/build_network.dart`)

- **Regions are the City walkway polygons.** A polygon is space a pedestrian can walk in. Polygons share exact boundaries: the connected components are identical at 0.5 m and 2 m tolerance.
- **Nodes are portals.** A node is the middle of each shared boundary between two polygons (`bridge_end` or `junction`), or the free end of a dead-end bridge (`terminal`).
- **Edges connect every pair of nodes on the same polygon.** Each edge follows the shortest path inside the polygon (a visibility graph over its vertices). So a route can't cut a corner, cross a street without a bridge, or walk through a wall the footprint doesn't contain. Two bridges into the same building connect only if the City's walkway inside that building connects them.
- **Zones and buildings.**
  - A zone is a set of interior polygons connected without crossing a bridge.
  - Buildings claim polygons (`regions` in the curation file).
  - The build **fails** if any City bridge record names a building that isn't on that bridge's own polygon. One hop through an unnamed City connector polygon is allowed.
  - This check caught several curation mistakes, including First Canadian Centre ↔ TD Square and the 700 Sixth / 639 Fifth access points.
- **Official-map cross-check.**
  - The build derives building-to-building adjacency from the graph and compares it with the links transcribed from the official map, in both directions.
  - Today the result is **0 official-map links missing from City data** and **0 City links not on the map** (after documented exclusions).
- **Street doors and transfers.**
  - A building's street doors are its mapped OSM doors (up to 4, at least 15 m apart), each joined to the nearest +15 node of the building. The stairs, escalator or elevator inside is not mapped. About a third of buildings have mapped doors today; the rest get one estimated street point on their OSM outline (the side facing the other +15 network), labelled as unmapped.
  - Buildings in different zones that are 250 m apart or less are joined by a straight outdoor edge between their closest pair of doors.
  - These edges are labelled `estimate` and used **only** when no +15 route exists.
  - Even then, an outdoor hop is allowed only between places that have **no** +15 connection under the current closures and profile. A route never steps outside to shortcut a +15 path that exists.

### Confidence

| Level | Meaning | Routing |
|---|---|---|
| `verified` | Inside a City walkway polygon, and the buildings it joins are linked on the official map (or named together by a City bridge record) | normal cost |
| `likely` | Shown on the official map but not in City walkway data (the Castell Building ↔ Bow Valley College South link) | ×1.25 cost, and the route says so |
| `unverified` | Anything else | never routed (none exist today) |
| `estimate` | Street exits and outdoor transfers | only when no +15 route exists, ×2.5 cost |

### What routing respects

- **Closures** (`assets/data/closures.json`).
  - A closed edge is **removed** from the search, not just flagged.
  - "Bridges connected to X" resolves to every bridge touching X's +15 nodes.
  - Routes say what a closure costs, e.g. "Avoids closure: … (adds about 2,000 m)".
  - After an *estimated* reopening date, routes warn that the reopening isn't confirmed.
- **Hours.**
  - A route that would not finish before closing (walked at 1.2 m/s) carries a warning.
  - Weekdays 6–21. Weekends and Alberta general holidays 9–19 (Good Friday is computed from Easter). Closed Dec 25.
  - While the network is closed, there is no route: the app shows when it opens and offers to plan for that time.
- **GPS starts.**
  - A fix inside a building's City walkway polygon starts there, and a fix inside the destination's polygon means you've already arrived.
  - Anywhere else, including under a bridge (usually street level), the route starts outdoors: a dotted straight-line walk to a street door, then up to the +15. Doors of every building within max(300 m, nearest door + 250 m) are candidates, and the search picks the one that makes the whole trip cheapest (outdoor metres ×2.5), which is the nearest door in your direction. For buildings without mapped doors, the point of the outline nearest you stands in. Beyond 3 km the app says how far away the +15 is and offers transit directions. The route screen links the walk to the door to the phone's maps app.
- **Accessibility.**
  - The Accessible profile excludes the official map's stairs-only links (bridges 1527 and 1522, into the Westin).
  - For GPS starts, it never goes up through a building the map marks "no elevator to street". A start or end at such a building gets a warning.
  - It also excludes street exits at buildings the map marks "no elevator to street".
  - Elevator locations aren't public, so street access is never claimed as step-free.
- **Profiles.** `fastest` (distance), `accessible` (the exclusions above), `mostlyIndoors` (open-air ×3). The weights are constants in `RouteWeights` and covered by `test/routing/router_test.dart`.

## Directions (`lib/routing/directions.dart`)

Directions are built from graph transitions, never from polyline angles:

- start
- walk through {building} to the bridge toward {next}
- cross the +15 bridge over {City crossing street} into {next}
- lane link
- stairs-only warning
- map-only link
- exit / walk outdoors / enter
- arrive

Every step lists the hops it covers, and the validator checks that the steps cover the route exactly.

**Street names.** A crossing street is named only for bridge hops of at least 15 m. Shorter connectors in the same chain (for example the 9 m link into the Bankers Hall West Parkade) are links, and links under 12 m merge into the bridge step that follows.

**Turn words.** "Turn left/right" or "continue straight" is used only when one bridge leads almost directly (under 15 m) into the next, using the bridges' own axes. Inside larger spaces the City footprints don't show walls, so the step names the next bridge instead of guessing a turn.

**Landmarks.** These are the official map's building icons (food court, shopping, hotel), shown as facts about a building. The app never says "pass the food court".

**Destinations.** A destination is every +15 node of the building, so the router picks the best entrance for your approach. You arrive when you enter the building at +15 level. Buildings that share one City polygon say so ("in the Calgary Tower / Palliser One concourse").

## Verification (`flutter test`)

- **`test/routing/network_integrity_test.dart`** checks:
  - orphan and duplicate nodes
  - edges with no source or confidence
  - edge geometry that leaves its City polygon (sampled every metre)
  - indoor edges longer than 250 m
  - geometries in different polygons that cross without a shared node
  - bridges with fewer than two ends
  - closure targets that don't exist
  - stairs-only links

  The known-unresolved items are pinned, so a new gap fails the test.
- **`test/routing/route_validation_test.dart`** routes every building to every building, both directions, with all three profiles, on a clear day and on a closure day: about 71,000 routes.

  Each route is checked for:
  - consecutive edges that share a node
  - no closed, unverified or out-of-hours edges
  - starting at an origin node and ending at a destination node
  - no geometry jumps
  - steps covering the hops
  - no stairs on accessible routes

  It also checks that A→B and B→A cost the same, and that buildings joined by one bridge never take a large detour.
- **`test/routing/golden_routes_test.dart`** runs 37 journeys from the official map (`golden_routes.json`), in both directions. They include:
  - The CORE, Bankers Hall, Calgary Tower, TELUS Convention Centre, City Hall, Bow Valley Square, Brookfield Place, The Bow, Suncor, City Centre, Eau Claire and the 4 Street CTrain link
  - same building, a shared concourse, adjacent buildings, opposite sides of The CORE
  - a cross-network trip
  - closure-day and reopened-day variants
- **`test/routing/conditions_test.dart`, `directions_test.dart`, `router_test.dart`, `test/course_tracker_test.dart`** cover hours, holidays, closures, accessibility, wording, weights and GPS progress.

**Debug overlay.** Help → Routing debug overlay.
- Every node and edge is drawn on the map; tap one for its type, City polygon, bridge record, buildings, closure state, confidence, sources and coordinates.
- Each route also gets a "Why this route" panel with the per-edge cost breakdown.

**Command line.**
- `dart run tool/route.dart <from> <to> [profile] [ISO time] [--hops]` prints any route with its steps and costs.
- From GPS coordinates: `dart run tool/route.dart 51.0453,-114.0688 the_bow`.

## Refreshing the data

1. `dart run tool/build_network.dart --refresh` re-downloads the City datasets into `tool/sources/`.
2. Read `docs/network-report.md`.
   - Any build error (for example, a bridge record whose named building no longer sits on its polygon) stops the build. Fix `tool/curation.json` against the official map.
   - New City polygons appear as unclaimed or isolated regions.
3. Update `assets/data/closures.json` from the calgary.ca/plus15 table, and set `retrieved`.
4. Run `flutter test`. Golden routes and pinned issues flag any routing change.

## Known limits

- **Floors.** Every node is "+15". The public data has no finer floor information, no doors, and no elevator or escalator locations, so the app never says "take the elevator".
- **Paths inside a polygon** are the shortest paths within the City's walkway footprint. The footprint doesn't show furniture, gates or interior walls.
- **Per-bridge hours** aren't published. On weekends and holidays every route carries the City's caveat.
- **Unresolved.**
  - London House and 520 Fifth are on the official map but have no identifiable +15 entry in City data, so they aren't routable.
  - The Castell Building ↔ Bow Valley College South link is from the map only.
- **Name changes.** Several buildings have been renamed since the City records were written (for example Devon Tower → 400 Third, Shell Centre → 400 4th, BP Centre → KPMG Tower, Sun Life Plaza → The Ampersand, Telus House → First Tower). The current names come from map v30, and the old names are kept as aliases, which search also matches.
- **Outdoor transfers and GPS approaches** are straight-line estimates. They are always drawn dashed and labelled "not +15".
- **Shops** have a building but no location inside it.
- **Estimated reopenings.** After a City-estimated reopening date the bridge is routable again, with a "reopening not confirmed" warning for 60 days. Update `closures.json` when the City confirms.
- **Long indoor detours.** When closures force a long indoor detour around a short street gap, the route stays indoors, because outdoor legs are only for missing +15 links. On closure days Life Plaza ↔ 736 Sixth is about 2.2 km indoors for a gap of about 100 m. An optional, clearly labelled "short outdoor shortcut" route would be the next step if that trade-off should be offered.
- **Adversarial review (2026-10-01).** About 85,000 routes plus a GPS grid all passed the validator. The behaviour defects it found are fixed and pinned in `test/routing/review_regressions_test.dart`.
