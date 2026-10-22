# Releases

One line per upload so a build on Google Play can be matched to the commit and tests it came from. The AAB is built with:

```
flutter build appbundle --release --dart-define-from-file=secrets.json --obfuscate --split-debug-info=build/symbols
```

| Version | Code | Commit | Artifact | SHA-256 | Track |
|---|---|---|---|---|---|
| 1.0.0 | 1 | b49cfd8 | app-release.aab | (not recorded) | Closed testing "Alpha", 2026-10-06 |
| 1.0.1 | 2 | cc5acef | app-release.aab | (not recorded) | Closed testing "Alpha", 2026-10-07 |
| 1.0.2 | 3 | 554c75e (merged to main as f0ddd5d) | `~/Downloads/Plus15-release-1.0.2/plus15-1.0.2-3.aab` (55,569,278 bytes) + `symbols-1.0.2-3.zip` | `9e5acf00bd754502eff2d763633b879d6b1e31429aad6bc4dd11244cd2c313ca` | Production (see PR #12) |
