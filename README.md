# Plus15 Navigator

A navigation app for Calgary's **+15 Skywalk Network**, the world's largest
elevated indoor pedestrian path system. Find your way between 100+ downtown
buildings through the +15, using the City of Calgary's own data.

## What's inside

- **Routing on City of Calgary data.**
  - The graph is built from the City's own +15 walkway footprints and bridge records, then cross-checked against the official +15 map.
  - Every edge cites its source and confidence.
  - Routes follow real walkway geometry, respect published closures and network hours, and avoid stairs-only links in Accessible mode.
  - When the +15 has no connection, routes say so and add a clearly marked outdoor leg.
  - See [`docs/routing.md`](docs/routing.md).
- **Directions from graph transitions.** "Cross the +15 bridge over 9 Ave SW into Gulf Canada Square." "Walk through Bankers Hall to the bridge toward TD Square."
- **Profiles.** Fastest, Accessible, Mostly indoors.
- **Live navigation.** GPS is tracked against the drawn route, and rerouting starts from inside the +15 polygon you're in.
- **Network status.** City closures with dates and sources, network hours, stairs-only links and known data gaps.
- **Debug overlay.** Help → Routing debug overlay shows every node and edge, tappable for sources and confidence.
- **Search, directory and saved routes.** Former building names are matched too.

## Data

| File | What | Source |
|---|---|---|
| `assets/data/network.json` | Buildings, City walkway polygons, nodes, edges, bridges, hours (generated) | `dart run tool/build_network.dart` |
| `assets/data/closures.json` | Closures routing must respect | calgary.ca/plus15 |
| `tool/sources/` | City open-data snapshots | data.calgary.ca `3u3x-hrc7`, `fu7z-c7ar` |
| `tool/curation.json` | Building names, aliases and claims; official-map links; stairs-only links | official +15 map v30 and City records |
| `docs/network-report.md` | Build report: counts, unresolved items, exclusions | generated |

## Architecture

```
lib/
  routing/     network model, conditions (closures/hours), router, directions, validator (pure Dart)
  core/        theme (design tokens + palette), router, constants
  data/        datasources, shop/saved-route models
  features/    map, search, route_planner, saved_routes, alerts, help, map3d
  shared/      Riverpod providers, reusable widgets
tool/          build_network.dart (data pipeline), route.dart (route inspector)
```

## Running

```bash
flutter pub get
flutter run
flutter test                           # integrity, all-pairs, golden routes
dart run tool/build_network.dart       # rebuild network.json from tool/sources
dart run tool/route.dart bankers_hall the_bow fastest 2026-10-15T12:00 --hops
```

Ask AI (Kimi K3 via NVIDIA's API) goes through a small Cloudflare Worker in
`server/ai-proxy/` that holds the NVIDIA key. The key must never be built into
the app: anything in the APK can be extracted. Deploy the proxy once:

```bash
cd server/ai-proxy
npx wrangler login
npx wrangler kv namespace create USAGE   # paste the id into wrangler.toml
npx wrangler secret put NVIDIA_API_KEY   # paste the nvapi-... key
npx wrangler deploy
node test.mjs                            # request-validation checks
```

Then put its URL in a gitignored `secrets.json`
(`{"AI_PROXY_URL": "https://plus15-ai.<you>.workers.dev/v1/chat/completions"}`)
and pass it in:

```bash
flutter run --dart-define-from-file=secrets.json
# Play upload (Flutter 3.47+, targets API 36 with 16 KB-aligned libraries):
flutter build appbundle --release --dart-define-from-file=secrets.json \
  --obfuscate --split-debug-info=build/symbols
```

Keep `build/symbols` for each release to read obfuscated crash stacks. Builds
without a URL still work; every Ask +15 entry point is hidden. The proxy only
accepts the app's models, caps size and tokens, rate-limits per IP, and stops
after `DAILY_CAP` requests a day across all users (`DAILY_CAP = "0"` turns AI
off without an app update). It sends no CORS headers, so Ask AI works in the Android/iOS apps, not the
web build.

Release signing: create an upload keystore and `android/key.properties`
(`storePassword`, `keyPassword`, `keyAlias`, `storeFile`), both gitignored.
Without it, release builds fall back to the debug key, which Play rejects.
