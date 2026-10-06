# Plus15 Navigator — security audit (Android), 2026-10-01

Scope: the Flutter app in this repo (Android release build), its bundled data, the
new Ask AI proxy in `server/ai-proxy/`, and git history. Baseline: OWASP MASVS.

## Executive summary

Plus15 is a public-data navigator. It has no accounts, payments, WebViews of its
own, deep links, file uploads or custom crypto. It has one real secret, the
NVIDIA API key behind Ask AI, and that key **was shipped in plain text inside
every release APK**. The key is now held only by a Cloudflare Worker that limits
what callers can do with it. Release signing, the cleartext setting and the AI
privacy notice were also fixed. The rebuilt release APK contains no secret.

Residual risk is low and mostly about cost: anyone can still call the proxy, but
only in the shape the app uses and within its rate limit.

## Findings

| # | Sev | Finding | Status |
|---|---|---|---|
| F1 | **High** | `NVIDIA_API_KEY` compiled into `libapp.so` through `String.fromEnvironment`. Recovered with `strings` from the release APK (1 match per ABI). The same key is in the local, gitignored `~/Downloads/.../Plus15/plus15-navigator.apk`. Impact: anyone with the APK can use the key, running up your quota and bill or getting it suspended. | **Fixed**, key rotation pending |
| F2 | Medium | Release builds signed with the debug key (`signingConfig = signingConfigs.debug`). | **Fixed** |
| F3 | Low | `android:usesCleartextTraffic="true"`. | **Fixed** (platform layer) |
| F4 | Low | The manifest flag does **not** cover Dart's HTTP client: a release build sent requests to an `http://` proxy URL and got 200 responses. Flutter's `dart:io` cleartext enforcement was reverted in Flutter 2. | **Fixed** for the only configurable endpoint |
| F5 | Low / privacy | Ask AI sends the question, the last 9 turns and an approximate position ("~75 m from door X"; never raw coordinates) to the model provider, with no notice to the user. | **Fixed** (in-app notice) |
| I1 | Info | `allowBackup` is on (default). The backed-up Hive boxes hold only saved routes, saved places and the theme. | Accepted: a useful restore feature, nothing sensitive |
| I2 | Info | `hive` 2.2.3 is unmaintained. It stores no sensitive data here. | Accepted; replace on the next storage change |
| I3 | Info | The release build accepts Flutter shell flags in launch intent extras (`--ez enable-impeller false` worked). Only allow-listed rendering flags are honoured. | Accepted |

### Fixes

- **F1:** `server/ai-proxy/worker.js` holds the key as a Wrangler secret.
  - It accepts only `POST /v1/chat/completions` and rate-limits per IP (20/min) with Cloudflare's built-in limiter.
  - It rebuilds the upstream body from allowed fields only: our 3 models, at most 20 messages, roles system/user/assistant, string content up to 100k characters in total (the real prompt is about 14k), `max_tokens` clamped to 1600 or less, `temperature` clamped to 0–1, `stream` forced on. Extra fields such as `tools` and `n` are dropped.
  - Upstream error bodies are replaced by a bare status code.
  - The app now reads `AI_PROXY_URL` and sends no credentials.
- **F2:** `android/app/build.gradle` signs releases from `android/key.properties` (gitignored, together with `*.jks` and `*.keystore`). Without that file it falls back to the debug key, which Play rejects.
- **F3:** `usesCleartextTraffic="false"`. This covers platform networking (url_launcher's WebViewActivity, Play services).
- **F4:** `KimiAiNotifier.isConfigured` requires `https://` in release, so a misconfigured release build fails closed and shows "isn't set up". Every other URL in the app is a hard-coded https constant (Esri, OSM, Google/Apple Maps).
- **F5:** The intro text in the Ask AI sheet now says questions and approximate +15 position go to an AI service.

## Attack surface

- **Package:** `com.plus15.plus15_navigator`, minSdk 21, targetSdk 35. Flutter (Dart AOT in `libapp.so`), Kotlin shell, no app-owned native code.
- **Exported components:**
  - `MainActivity`: launcher only, `taskAffinity=""`, no VIEW intent filter, so there are no deep links.
  - `ProfileInstallReceiver` (AndroidX): guarded by `DUMP`.
  - Everything else is not exported: `GeolocatorLocationService`, `WebViewActivity`, `GoogleApiActivity`, `InitializationProvider`.
- **Permissions:** INTERNET, fine and coarse location (requested at onboarding or on the locate tap, with denial handled), network state.
- **Storage:** Hive boxes `saved_routes`, `preferences` and `saved_places` in app-private storage. No tokens or PII.
- **Outbound:**
  - App → Worker → `integrate.api.nvidia.com` (AI).
  - `server.arcgisonline.com` and `tile.openstreetmap.org` (tiles).
  - `tel:`, `mailto:feedback@plus15.app`, Google/Apple Maps https links.
  - Shop websites from bundled `shops.json`, all https.
- **Trust boundaries:**
  - The device is untrusted. The Worker is the only component holding a secret.
  - Model output is untrusted. It is shown as plain text, and its only "actions" are `[ACTION:NAVIGATE|…]` / `[ACTION:FOCUS|…]` tags that resolve to known buildings for in-app routing. It cannot open URLs or reach storage.
- **Not present, checked:** auth or sessions (so no IDOR or role tests apply), Firebase or any cloud rules, app WebViews, JS bridges, content providers, file upload/download, crypto, clipboard writes, analytics or crash SDKs, notifications, payments.

## Tests performed

| Area | Test | Result |
|---|---|---|
| Secrets | `strings` of every file in the release APK, before and after the fix, for the real key, `nvapi-`, `Bearer `, `AIza`, private-key headers | Before: key found in all 3 ABIs. After: 0 |
| Secrets | Real key in any git object (all refs, including Conductor checkpoints) | 0. Only the README placeholder `nvapi-...` |
| Secrets | APKs committed to the public GitHub history (`4887496`, `bc2690a`) | No key; they predate Ask AI |
| Proxy | `node server/ai-proxy/test.mjs`: field allow-list, clamps, 11 rejected shapes, 404/405/429/400, key added server-side, upstream body hidden | Pass |
| Proxy | Live `wrangler dev`: GET → 405, wrong path → 404, unknown model → 400, bad JSON → 400, `max_tokens: 99999` → clamped, valid → 200 SSE, burst → 429 after limit | Pass |
| App E2E | Debug build on Android 15 emulator → local Worker → NVIDIA: "Coffee near Bankers Hall" streamed an answer with Go actions | Pass |
| Cleartext | Release build with `http://` proxy URL, before the F4 fix | **Request succeeded** (finding F4) |
| Cleartext | The same, after the fix | "Isn't set up" shown, 0 proxy hits |
| Tiles | Release build with cleartext off: Esri basemap loads | Pass |
| Manifest | `aapt dump xmltree` of the release APK: no `debuggable`, cleartext 0x0, exported set as listed above | Pass |
| Signing | Release build with a throwaway `key.properties` → `apksigner` shows that cert; without it, the debug cert | Pass |
| Regression | `flutter analyze`; `flutter test` (201 tests, including UI overflow) | Clean, all pass |
| Deps | `flutter pub outdated`, pub advisories | No advisories. Majors behind: riverpod 3, go_router 18, geolocator 14, permission_handler 13 |

Not done: rooted-device or Frida instrumentation, and MITM proxying of tile traffic.
With no secrets or sessions on the device, they would find nothing the static pass
missed. Not done either: an iOS or web build audit (the web build cannot call the
proxy without CORS, and none is added).

## Residual risk

- **Proxy abuse:** the Worker URL ends up in the APK, so anyone can call it. They get only our 3 models at 1600 tokens or less, 20 requests per minute per IP. Distributed abuse could still consume quota. Upgrade path: Play Integrity / App Attest tokens checked in the Worker, plus a daily spend cap in NVIDIA.
- **Old key:** the old key exists in `~/Downloads/Coding Projects/Plus15/plus15-navigator.apk` (Sep 3) and in any copy of that APK. It stays valid until it is rotated.
- **Third parties:** NVIDIA and Cloudflare receive user questions and approximate +15 position. The Play Data Safety form should declare "approximate location" and "app interactions / user content" as shared for app functionality.
- **Prompt injection:** a user can make the model say anything to themselves, but it cannot act outside in-app navigation to known buildings.

## Next steps (owner: you)

1. `cd server/ai-proxy && npx wrangler login && npx wrangler secret put NVIDIA_API_KEY && npx wrangler deploy`, then put the `https://…workers.dev/v1/chat/completions` URL in `secrets.json`.
2. Rotate the NVIDIA key: issue a new one and put it only in the Worker, then revoke the old one. Delete `plus15-navigator.apk` from the main checkout.
3. Create an upload keystore and `android/key.properties`, and enrol in Play App Signing.
4. Fill in the Play Data Safety form as above, and set a usage cap or alert in the NVIDIA console.
