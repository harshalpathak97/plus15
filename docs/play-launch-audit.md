# Plus 15: Google Play launch audit, 2026-10-06

Scope: the whole Android app (security, Play policy, crashes and broken flows, UI, UX,
accessibility), plus the Ask +15 proxy. It builds on the Android security audit in
`docs/security-audit.md`; findings fixed there aren't repeated here. iOS findings are at the
end (out of scope: Play only).

How it was checked: three code audits (security/policy, crashes, UI/UX); `flutter analyze`
(clean); `flutter test` (204 pass); `node server/ai-proxy/test.mjs`; release APK/AAB checks
with `aapt2`, `zipalign -P 16`, `llvm-objdump` and `strings`; and a hands-on pass on the
Android emulator (API 35) in light, dark, 200% text, location denied/granted, offline, and
Ask +15 against a local proxy.

Status: **Fixed**, or **You** (needs an action only you can take).

## Blockers (Play would reject, or the app breaks)

| # | Finding | Status |
|---|---|---|
| B1 | Target API 35. Play has required **API 36** for new apps since 2026-08-31. Flutter 3.27 couldn't target it. | Fixed: Flutter 3.47.6, AGP 9.1, Gradle 9.3, Kotlin 2.4, compile/target SDK 36. `aapt2` reports targetSdk 36. |
| B2 | Native libraries not **16 KB-aligned** (required since Nov 2025). | Fixed by B1. All 64-bit `.so` files are aligned to 64 KB; `zipalign -P 16` passes. |
| B3 | **Crash:** starting a route whose start and destination share a building/concourse called `double.infinity.round()` on the first GPS fix, and the whole nav sheet turned into a grey error box. | Fixed: zero-hop routes start as "You've arrived"; the tracker never reports infinity. Verified on the emulator and covered by a test. |
| B4 | **No privacy policy** anywhere (Play requires one in the listing and in the app). | Fixed: `docs/privacy.html`, linked from Settings → About and the Ask +15 consent. **You:** turn on GitHub Pages (below). |
| B5 | **Ask +15 sent data to a third-party AI with no consent**, including saved places and the step-free preference, and opening it from Search/Navigate sent a question straight away. | Fixed: a one-time consent screen explains that a third-party AI service answers and lists everything sent. Nothing is sent until the user agrees. |
| B6 | **No way to report a bad AI answer** (Play AI-Generated Content policy). | Fixed: a Report button on every answer opens an email with the question and answer. |
| B7 | **Ask +15 is broken in release builds**: `secrets.json` points at the emulator's localhost, the proxy was never deployed, but every Ask button still showed. | Fixed: every entry point hides when no https proxy is configured. **You:** deploy the proxy to ship AI (below). |

## High

| # | Finding | Status |
|---|---|---|
| H1 | The OS location prompt fired as soon as the map opened, even after "Not now" in onboarding. | Fixed: it's only asked from a tap (onboarding button, My location, Start from my location). |
| H2 | Location denied, denied forever, or turned off left no way back. | Fixed: a "Turn on" action opens the right system screen, and the app picks up location on return. Verified. |
| H3 | Android back on any tab closed the app. | Fixed: other tabs go back to the map; the map closes a selected building or previewed route first. Verified. |
| H4 | A corrupt Hive box left the app stuck on the splash screen; one unreadable saved route broke the Saved tab. | Fixed: bad boxes are reset; bad entries are skipped. |
| H5 | Navigation: arrival fired on one stray fix and flipped back and forth; progress jumped forward; reroutes used vague indoor fixes, swapped in "preview only" routes, and "re-routing" could stay up forever. | Fixed: 2 close fixes to arrive and it sticks; progress only moves forward; reroute needs accuracy ≤ 25 m; failures say why. |
| H6 | AI proxy usable as a free model endpoint with no global budget. | Fixed: daily cap across all users (`DAILY_CAP`, `0` = off switch), 40k character limit. **You:** create the KV namespace (below) and set a budget alert for the Gemini key. |
| H7 | Looks official: City +15 sign as the icon, "official City map" wording, no disclaimer. | Fixed: "Not affiliated with or endorsed by The City of Calgary" in Settings → About. **You:** use the new icon from the `honiara` workspace, and put the same line in the store description. |
| H8 | 100+ third-party brand logos (Starbucks, TD, KFC…) bundled without permission. | You kept them (decision). Fixed: a trademark notice in About. Remove a logo if its owner objects. |
| H9 | Missing data credits: City of Calgary Open Government Licence wording, OpenStreetMap (ODbL), "Powered by Esri". | Fixed: in About and in the map caption. The caption wraps instead of cutting off at large text. |
| H10 | Developer content in release: "Routing debug overlay" switch, raw data-issue text, "Kimi is busy on NVIDIA's servers", "Answered by fallback model", Reasoning toggle, `Error: <exception>`. | Fixed: debug builds only; users see plain copy with Try again. |

## Medium

| # | Finding | Status |
|---|---|---|
| M1 | Kimi's first token took 30–70 s, so Ask felt broken. | Fixed: Ask +15 now runs on Gemini (`gemini-3.5-flash-lite`, then `gemini-flash-lite-latest`, then `gemini-3.8-flash`): first token in about 1 s through the live proxy. The consent screen says "a third-party AI service"; the privacy policy names Google. |
| M2 | Action tags only parsed in one field order, and malformed tags showed as raw `[ACTION:…]`. | Fixed: any order; leftover tags are removed. |
| M3 | Switching dark/light mode in Settings left the map blank until you panned it (found on the emulator). | Fixed: tiles show without the fade animation. |
| M4 | Snackbars with an action (Undo, Turn on) never went away on Flutter 3.47. | Fixed. |
| M5 | Text clipped at large system text: search bar, filter pills, brand carousel, shop/street button rows, onboarding, header chip. | Fixed: they grow or stack; the floating map controls cap text at 130%, the rest scales fully. Verified at 200%. |
| M6 | Contrast: "Open" green (3.5:1) and amber warning text (2.4:1) failed WCAG AA on white. | Fixed: darker text shades (5.3:1 and above) in light mode. |
| M7 | Screen readers: map markers were unlabeled with 12 px tap targets; icon-only buttons in 3D, Directory and Alerts had no labels; the bell read "3"; route cards read twice. | Fixed: labeled 44 px markers, tooltips, "3 closures", one label per route card. |
| M8 | Looping animations (location pulse, arrived pin, shimmer) ignored "Remove animations". | Fixed. |
| M9 | Onboarding said the +15 is "four storeys up" (it's 15 feet) and never said what the +15 is. | Fixed. |
| M10 | "Save route" on the arrival card silently did nothing for trips from My location. | Fixed: it saves from the first +15 building, or says why it can't. |
| M11 | 3D view repainted every frame forever (battery/heat), and kept the old route after you cleared it. | Fixed: it idles after 30 s and resets when the route is cleared. |
| M12 | "Next opening" labels and holiday dates used `Duration(days:)`, which is wrong on DST nights in some device time zones. | Fixed: calendar arithmetic. |
| M13 | Unused `permission_handler` and `ACCESS_NETWORK_STATE`. | Removed. The APK asks only for internet and location. |
| M14 | OSM fallback tiles sent the wrong user agent. | Fixed. |

## Lower (fixed)

- Navigate starts from your location when it's already known, and shows a spinner (12 s limit) while finding it. Swap is disabled for "My location".
- Building cards say whether the +15 is open now.
- Saved routes have a visible ⋯ menu for Rename/Delete, not just long-press and swipe.
- Load errors have "Try again".
- Search has Entertainment.
- The map legend explains building dot colours.
- The Search box follows queries set from the map.
- The map header refreshes every minute.
- One name, "Plus 15", for the launcher label and in the app.
- Bundled Inter on every platform.
- Mailto subjects no longer show "+" for spaces.

## Not done (with reason)

- **Closures are bundled** (checked 2026-09-30) and will go stale after release. The Alerts screen shows the "checked" date. Fetching them remotely is a feature; do it before the next closure season.
- **No offline tile cache.** The +15 overlay and routing work offline (verified); the base map needs a connection.
- **Building-level opening hours** aren't in any data source; the app shows +15 network hours.
- Dialog `TextEditingController`s aren't disposed. Harmless (garbage-collected); disposing them right after the dialog closes can crash on the exit animation.
- Hard-coded corner radii and `Colors.white/black` in map/3D code: cosmetic.
- `hive` is unmaintained. It stores nothing sensitive; replace it on the next storage change.

## Launch checklist (status 2026-10-06)

- [x] AI proxy deployed: `https://plus15-ai.harshalpathak.workers.dev` (KV daily cap, rate limit). `secrets.json` points at it.
- [x] Privacy policy live: https://harshalpathak97.github.io/plus15/privacy.html
- [x] Upload keystore created: `~/development/keys/plus15-upload.jks` (password in `~/development/keys/plus15-key.properties`). **Back both up somewhere safe (a password manager)**; Play App Signing can reset a lost upload key, but it takes days.
- [x] Signed release built: `~/Downloads/Plus15-release-1.0.0/` (`.aab` for Play, `.apk` for sideload testing, debug symbols zip for crash stacks).
- [ ] **Revoke the old NVIDIA key** at build.nvidia.com (it leaked in an earlier APK; the proxy no longer uses it). Set a usage cap / budget alert for the Gemini key in Google AI Studio or Cloud billing. If the Gemini key is on the free tier, Google may use prompts to improve its products; use a paid key to avoid that.
- [ ] Check that developer@harshalpathak.com receives mail.
- [ ] Play Console:
  - Create the app, enroll in Play App Signing, and upload the `.aab`.
  - Personal account: run a closed test with 12 testers for 14 days.
  - Content rating: declare the AI chatbot.
  - Data safety: answers below.
  - Store listing: add the "not affiliated with The City of Calgary" line.
- [ ] New icon in an update (the current one resembles the City's +15 sign).

Rebuild with Flutter 3.47.6 (`~/development/flutter-3.47`):
`flutter build appbundle --release --dart-define-from-file=secrets.json --obfuscate --split-debug-info=build/symbols`.
Bump `version:` in `pubspec.yaml` (e.g. `1.0.1+2`) for every upload.

## Data safety form answers

- **Collects or shares user data:** yes.
- **Location, approximate:** shared, only when the user uses Ask +15 (a phrase like "about 75 m from the Bankers Hall door"). Purpose: app functionality. Optional. Not collected by the developer otherwise; precise location never leaves the device.
- **App activity → Other user-generated content** (Ask +15 questions, saved place names, step-free preference): shared with Google (Gemini API) for app functionality. Optional.
- **Collected vs shared:** the proxy forwards and keeps nothing, so declare it as **shared** (to Google's Gemini API); it was also entered as collected but processed ephemerally.
- **Encrypted in transit:** yes.
- **Users can request deletion:** not applicable (nothing is stored on a server); say so.
- **No** analytics, ads, account, contacts, photos, financial or health data.

## iOS findings (out of scope: Play only)

If you ship to the App Store later, you'll need to:
- Remove `NSLocationAlwaysUsageDescription` (the app never asks for Always).
- Add `ITSAppUsesNonExemptEncryption = false`.
- Set the deployment target to 13 or higher and adopt the scene lifecycle.
- Build with Xcode 26.
- Answer Apple's privacy label as above.
- Expect stricter review of the brand logos (5.2.1).
