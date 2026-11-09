# Releases

One line per upload so a build on Google Play can be matched to the commit and tests it came from. The AAB is built with:

```
flutter build appbundle --release --dart-define-from-file=secrets.json --obfuscate --split-debug-info=build/symbols
```

Before uploading, check that Ask +15 points at the live proxy and not the emulator. 1.0.3 shipped with `http://10.0.2.2:8787`, which hid Ask +15 for everyone:

```
unzip -p build/app/outputs/bundle/release/app-release.aab base/lib/arm64-v8a/libapp.so | strings | grep -E 'workers\.dev|10\.0\.2\.2'
```

It must print the `workers.dev` URL only.

| Version | Code | Commit | Artifact | SHA-256 | Track |
|---|---|---|---|---|---|
| 1.0.0 | 1 | b49cfd8 | app-release.aab | (not recorded) | Closed testing "Alpha", 2026-10-06 |
| 1.0.1 | 2 | cc5acef | app-release.aab | (not recorded) | Closed testing "Alpha", 2026-10-07 |
| 1.0.2 | 3 | 554c75e (merged to main as f0ddd5d) | `~/Downloads/Plus15-release-1.0.2/plus15-1.0.2-3.aab` (55,569,278 bytes) + `symbols-1.0.2-3.zip` | `9e5acf00bd754502eff2d763633b879d6b1e31429aad6bc4dd11244cd2c313ca` | Production (see PR #12) |
| 1.0.3 | 6 | PR #13, merged to main as d342064; sent for review in Play 2026-10-31 | `~/Downloads/Archives & Installers/Plus15-release-1.0.3/plus15-1.0.3-6.aab` (55,658,774 bytes) + `symbols-1.0.3-6.zip` | `2d3d626350ddaa07057483d696bf7e92bfdbdd8ce6a5a3094c3bf0cdaec50247` | In Google review (full rollout): far-origin handoff, rating prompt, opening hours for 122 of 134 places (Google Maps + official sources 2026-10-31; 10 permanently closed shops removed) |
| 1.0.4 | 7 | PR #16 (Ask fix only) | `superseded/plus15-1.0.4-7-before-far-fix.aab` | `5574e3d662878b1a2672cd293454a3d4d41898d1f5158621de2f8f63f0baeeb3` | In the Play bundle library (uploaded 2026-11-09 4:19 PM), not released. Has no far-start fix; don't ship it. |
| 1.0.4 | 8 | PR #16 + PR #17 + this PR (code bump) | `~/Downloads/Archives & Installers/Plus15-release-1.0.4/plus15-1.0.4-8.aab` (55,666,139 bytes) + `symbols-1.0.4-8.zip` | `98ac76617c418784572cc14632de55f175c1181719734329010a6df450acc851` | Production: sent for review 2026-11-09, full rollout (the release is named "7 (1.0.4)" in Play Console, typed before the bundle was added; the bundle in it is code 8). Turns Ask +15 back on, and Find nearest +15 entrance works more than 3 km out (Transit/Walk/Drive in the maps app). Upload-key signed; 250 tests pass. |
