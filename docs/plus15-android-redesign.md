# Plus 15 — Android Redesign & Product Spec

**Project codename:** Plus 15 (Calgary +15 Navigator)
**Document type:** Full product / design / engineering handoff
**Platform:** Android phones first (Flutter, native-compiled)
**Status:** Implementation-ready spec
**Grounded in repo:** `plus15_navigator` — Flutter + Riverpod + go_router + `flutter_map` + `geolocator`; current content: **107 buildings, 119 bridges, 45 shops, 20 entry points**; current identity: indigo brand `#4F46E5` + skywalk teal `#0EA5B7`, Plus Jakarta Sans / Inter.

---

## Stack assumption (read first)

The prompt asks for "Jetpack Compose." The actual codebase is **Flutter**. Pretending otherwise would produce a spec nobody can build against. My strong recommendation:

> **Keep Flutter as the production stack.** It already exists, it compiles to native ARM (with the Impeller renderer it is genuinely 120 Hz-smooth on modern Android), and it gives you free iOS parity — which the brief explicitly wants ("reference the existing iOS app for parity"). Rebuilding in pure Kotlin/Compose would throw away the working `flutter_map` + A\* pathfinder + Riverpod graph and double your maintenance for no user-visible win.

So **Section 10 is written for Flutter**, with a parallel Compose mapping table for anyone who insists on native Kotlin. Everywhere else, "Android-native feel" means: Material 3 motion, Android predictive-back, edge-to-edge, system haptics, Material You dynamic color opt-in — all reachable from Flutter.

Where I make assumptions, they are flagged **[ASSUMPTION]** with a recommendation.

---

## 1. Product vision

**Plus 15 is the calm, confident way to move through the largest elevated indoor walkway network on earth — Calgary's +15 — without ever guessing where you are.**

Downtown Calgary's +15 is ~16–18 km of skywalk spanning 100+ buildings four storeys up. It is a genuine wayfinding problem: bridges look identical, building names rotate with ownership, GPS is unreliable above-grade and indoors, and signage is inconsistent. People who work downtown have learned a private mental map; everyone else — visitors, new hires, conference-goers, anyone fleeing –30 °C — is lost.

**Who it's for, in priority order:**
1. **The downtown commuter** who walks the +15 daily and wants one-tap repeat routes and to discover lunch.
2. **The first-timer** (visitor, new employee, conference attendee) who needs hand-holding, confidence, and landmarks — not a raw dot on a tile map.
3. **The accessibility-dependent traveller** who must avoid stairs and route elevator-to-elevator.

**Emotional outcome:** the relief of *"I know exactly where I am and exactly where to turn,"* even when the blue dot is jittering. We sell **certainty indoors**, the one thing every generic map app fails to deliver above-grade.

**Why it deserves to exist:** Google/Apple Maps treat the +15 as a black box — they route you outside, at street level, in the cold. The official iOS app is functional but flat, and its reviews flag exactly the right problems: weak labels, missing landmarks, imperfect geolocation. No one has built the *premium, +15-native* companion. Plus 15 is that app: it doesn't pretend to be a city map; it is a purpose-built instrument for one extraordinary network.

---

## 2. Design direction

### Brand attributes
Confident · Calm · Precise · Warm-Nordic · Quietly premium. (Never: loud, gamified, "techy," cluttered.)

### Design keywords
*Glass over a glowing map · luminous lines on deep ink · generous whitespace · one accent at a time · motion that explains, never decorates.*

### Color system
Evolve the existing tokens rather than replace them — the indigo + teal pairing is already good and worth protecting.

| Role | Light | Dark | Notes |
|---|---|---|---|
| Brand / primary | `#4F46E5` | `#818CF8` | Buttons, active route, selection |
| Skywalk (signature) | `#0EA5B7` | `#22D3EE` | The network lines — the soul of the map |
| Origin | `#10B981` | same | Start pin |
| Destination | `#F43F5E` | same | End pin |
| Warning / limited | `#F59E0B` | same | Limited-access bridges |
| Danger / closed | `#EF4444` | same | Closures |
| Ink / text | `#0B1020` | `#F4F5FB` | |
| Ink muted | `#64748B` | `#94A3B8` | |
| Surface | `#F6F7FB` | `#080A14` | App background |
| Card | `#FFFFFF` | `#12141F` | |
| Border (hairline) | `#E7E9F2` | `#222637` | 1px, never heavier |

**Rules:** exactly one saturated accent per screen region; teal is reserved for the network itself and never used for chrome; the brand gradient (`brand → skywalk`) appears only on the primary "Start" action and the active-nav banner — nowhere else. **Ban** multi-stop rainbow gradients and any gradient on text.

### Typography
Keep **Plus Jakarta Sans** (display/headings, weights 700–800, negative tracking on large sizes) + **Inter** (body/UI, 400–700). Add one tabular-figures usage: **Inter with `fontFeatures: ['tnum']`** for all distances, ETAs, and live nav metrics so digits don't jump. Type scale already defined in `app_theme.dart` — formalize it as the only allowed scale (display 34/28, headline 24/20, title 18/16/14, body 16/14, label 14/11).

### Elevation / material language
A two-plane system: **the map plane** (full-bleed, behind everything) and **glass panels** that float over it. Panels use a frosted blur (`BackdropFilter`, ~20σ) + 1px hairline border + a single soft shadow (`y8, blur24, 12% ink`). No Material drop-shadow stacking, no neumorphism. Cards on solid backgrounds (directory, settings) are *flat with hairline borders* (already the repo convention — keep it). Corner radii: panels/sheets 28, cards 20, controls 14, chips/pills 12 — exactly the existing token ladder.

### Iconography
One family, **rounded, 2px stroke, optically balanced at 24dp** (Material Symbols Rounded, or Lucide for a slightly warmer feel — **[ASSUMPTION] recommend Material Symbols Rounded** for zero-cost Android nativeness and existing `Icons.*` usage). Category icons get a soft tinted "chip" background using `categoryColor` at 12% opacity. Custom-draw only three marks: the +15 wordmark, the "you-are-here" puck, and the bridge/skywalk glyph.

### Illustration / photo
Minimal illustration; **no stock photos of generic cities** (kills premium feel). Onboarding uses a single hero: a stylized vector of the +15 graph itself drawing in line-by-line (we already render the real graph — reuse it as art). Business listings use a tinted category glyph as the default avatar; real logos only when a verified business uploads one. Empty states use tiny line spot-illustrations in the muted ink color.

### Motion principles
1. **Motion explains spatial relationships** — sheets rise from where you tapped, the map camera *flies* (eased) between origin and destination so users feel the geography.
2. **Spring, don't ease, for anything the finger touches** (Flutter `SpringDescription`, damping ~0.8).
3. **Standard durations:** micro 120ms, standard 240ms, camera fly 600–900ms. Honor `MediaQuery.disableAnimations` / reduce-motion.
4. **Shared-element transitions** between a business card in the list and its detail sheet (Hero).
5. Nothing loops forever except the live "locating…" pulse.

### Haptic principles
Map to `HapticFeedback`: **selection click** on chip/segment toggle, **light impact** on snapping to a node or recentering, **medium impact** on "route found" and "you've arrived," **heavy/notification** never (too aggressive). Turn-by-turn: one light tick ~30m before each turn, a medium at the turn. All haptics gated behind a Settings toggle (default on).

### Dark mode strategy
**Dark is the hero theme** — the map is a glowing network on deep ink (`#080A14`), which is exactly how a skywalk network *should* feel and what the brief's "cinematic" ask wants. Light mode is fully supported and equally polished (it's for bright +15 glass corridors at noon). Follow system by default; manual override in Settings (already wired via theme). Map tiles swap to a dark CartoDB/vector style in dark mode; skywalk lines brighten to `skywalkBright` so they pop on ink.

### Accessibility strategy
- **Contrast:** all text ≥ 4.5:1; the muted ink on surface already passes — audit teal-on-ink for line labels (use `skywalkBright` in dark to clear 3:1 for the line as a graphical object).
- **Touch targets** ≥ 48dp; map controls 56dp.
- **TalkBack:** every map marker, route step, and CTA has a semantic label ("Bankers Hall, food and retail, 120 metres ahead"). Live nav announces turns via an `AssertiveLive` semantics region.
- **Dynamic type** to 200%; layouts reflow (no fixed-height text rows).
- **Color-independence:** bridge status conveyed by color **and** icon/pattern (dashed = limited, dotted-red = closed) — critical for the colorblind, and for the brief's "legibility" demand.
- **Reduce motion** flattens camera flies to cross-fades; **accessible routing mode** (elevator-only) is a first-class route type, not a buried toggle.

---

## 3. Information architecture

### Navigation pattern — decision
A **3-tab bottom bar + persistent map** model. The map is not a tab you "visit"; it's the substrate. Tabs switch what floats over it. This beats a 5-tab bar (cluttered, un-premium) and a hamburger drawer (un-Android-modern, hides the network).

```
Bottom bar (3):  [ Explore ]   [ Navigate ]   [ Saved ]
Top-left chip:   Alerts (badge) → only appears when closures are live
Top-right:       Profile / Settings avatar
```

- **Explore** = the home/discovery surface over the map (search, businesses, categories, featured, nearby). Absorbs both "Home" and "Businesses" from the brief — they're the same surface at different scroll depths, which is more premium than splitting them.
- **Navigate** = route planning + active turn-by-turn. The "do the thing" tab.
- **Saved** = favorites + recents + routines.
- **Alerts/Closures** is *conditional chrome*, not a tab — it earns a tab's worth of attention only when something is wrong, via a top-left pill with a count. This is the elegant way to "handle live network conditions" without permanently spending a tab on an empty list.
- **Settings / Permissions / Help** live behind the profile avatar (top-right), not in the bar.

### Screen tree
```
App
├─ Splash (brand + graph draw-in, ~800ms or until data ready)
├─ Onboarding (first run only)
│   ├─ 1. What is the +15 (value)
│   ├─ 2. How Plus 15 guides you (confidence promise)
│   └─ 3. Location permission education → system prompt
├─ Main shell (persistent map + bottom bar)
│   ├─ Explore  (default)
│   │   ├─ Collapsed search bar + "you are at <building>" context
│   │   ├─ Quick destinations (washroom, food, transit, exits)
│   │   ├─ Featured / sponsored row
│   │   ├─ Categories grid
│   │   ├─ Nearby businesses (sorted by network distance)
│   │   └─ → Search screen (full)
│   │        └─ → Business detail sheet
│   │             ├─ Navigate here
│   │             ├─ Call
│   │             └─ Website
│   ├─ Navigate
│   │   ├─ From / To picker (From defaults to GPS-nearest node)
│   │   ├─ Route options (Fastest / Accessible / Explorer)
│   │   ├─ Route preview (map fly + step list)
│   │   ├─ Active navigation (turn-by-turn)
│   │   └─ Arrival state
│   └─ Saved
│       ├─ Routines (one-tap launch)
│       ├─ Favorite places
│       └─ Recent searches / routes
├─ Alerts / Closures (modal route from top-left pill)
└─ Profile
    ├─ Settings (theme, haptics, units, accessible-default)
    ├─ Permissions status & re-request
    ├─ Help / how to read the map
    └─ Send feedback / report a closure
```

---

## 4. Signature user journeys

Each journey: **emotional arc → friction in today's app → how we remove it.**

### A. First-time onboarding
*Feeling: curious but wary of "another app that wants my location."* → Three swipeable cards, no account required. Card 3 explains *why* location helps **before** the OS prompt ("So we can show where you are inside the network and guide you turn-by-turn — we never track you in the background"). We remove the cold-prompt friction by earning the permission first. **Skip** is always available; the app works in browse-only mode without GPS.

### B. Granting location permission
*Feeling: "what's the catch?"* → We request **only foreground/while-in-use**, never background. If denied, no dead end: a calm inline banner offers "Pick your starting point manually" and the app stays fully usable. If "approximate only" is granted, we show a wider confidence halo and say so. Re-request is one tap in Profile.

### C. Open app → see current position
*Feeling: "am I even in the right place?"* → On launch we snap the map to the user's **nearest network node** (not raw GPS) and label it: *"You're near Bankers Hall, Level +15."* This single line — building name + level — is the entire fix for the iOS "unclear labels" complaint. If GPS is weak, we show *"Finding you…"* with the last known building, never a spinning void.

### D. Search for a business
*Feeling: hurried, hungry.* → Tap search → keyboard rises, recents + "open now near you" pre-populate **before typing**. Fuzzy match across business name, category, and building. Results show distance *through the network* (not crow-flies) and "open/closed now." Typing "coffee" surfaces Starbucks/Tim Hortons sorted by walking time.

### E. Tap business → detail
*Feeling: deciding.* → Card expands (shared-element) into a sheet: name, category chip, **open-now with today's hours**, the building it's in + level, distance/time, and three primary CTAs — **Navigate here · Call · Website**. A mini-map shows the dot relative to "you." No clutter, no reviews-spam.

### F. Navigate current → business
*Feeling: "don't make me think."* → One tap "Navigate here." Camera flies origin→destination so you *see* the path. Route options appear as three cards; Fastest pre-selected, Accessible one tap away. "Start" is the gradient button. Friction removed: From is pre-filled to your GPS node, so it's literally one decision.

### G. Walking the network, live guidance
*Feeling: trusting but checking.* → Big current-step banner ("Cross the bridge to Bankers Hall → 80 m"), next-step preview beneath, route line ahead in brand color / behind dimmed. Map follows in a gentle heading-up or north-up (user choice). A **confidence chip** ("Strong signal" / "Approximate — follow the highlighted bridge") is always honest. Light haptic before each turn. We remove "wait, did I miss it?" by emphasizing the **named bridge and the building you're entering** at every step, not just "turn left."

### H. Closures / unavailable segments
*Feeling: frustration ("the app sent me to a locked door").* → If a bridge on the route has `status: closed/limited`, the planner **never** routes through it; the closed segment renders dotted-red with a tap-for-why. If a closure appears mid-walk, we proactively reroute with a medium haptic + "Path ahead closed — I've found a way around (+90 m)." This directly serves the City's "service updates and closures" reality.

### I. Save a favorite
*Feeling: "I'll be back."* → A heart on any business/route. First save nudges: "Make this a routine? Launch it in one tap from Saved." Routines surface on the Explore home as quick chips during their typical time-of-day.

### J. Reopen for repeat navigation
*Feeling: efficient, habitual.* → App opens to Explore; if a routine matches the current time/location, a single hero chip reads **"Start: Morning commute → Bankers Hall."** One tap → straight into active nav. This is the daily-commuter payoff.

---

## 5. GPS and walking guidance experience

The governing principle: **never pretend GPS is good downtown; engineer around it and be honest.** Above-grade and indoors, civilian GPS is routinely 20–50 m off with multipath off glass towers. So the network graph is the source of truth, GPS is an *input* we snap and smooth.

- **User location** = a custom "puck": a filled brand dot, a soft accuracy halo whose radius = real reported accuracy, and a heading wedge. The puck is **snapped to the nearest plausible network node/segment** when GPS confidence is low, with the raw position shown as a faint ghost so we never lie about which is which.
- **Heading** from the magnetometer (compass) fused with course-over-ground when moving fast enough; we smooth heavily (the existing `course_tracker.dart` smoothing is the right idea — extend it). Below walking speed we trust compass; we never spin the wedge wildly.
- **Map follow:** "Follow mode" recenters with a lead offset (puck sits low-third so you see ahead). Any manual pan breaks follow and reveals a **Recenter** FAB; tapping it re-engages with a light haptic and a 600ms fly.
- **Step-by-step directions:** a top banner (current step) + a thin "then" line. Each step is phrased around *named bridges and buildings + levels*, e.g. *"Cross the +15 bridge into Bankers Hall (Level +15), then bear right past the food court."* Distance counts down in tabular figures.
- **Rerouting:** off-route detection from `course_tracker` triggers a debounced (don't thrash) recompute on the graph; "Rerouting…" shimmer for <500ms then the new line draws in. Medium haptic.
- **Indoor / elevated ambiguity:** when inside a large building (low confidence, no clear segment), we switch from "metres" to **landmark-relative** guidance ("Walk toward the glass atrium / the down escalators") using landmark nodes, and show a "Inside building — follow signs to +15" hint.
- **Signal uncertainty, gracefully:** a three-state confidence chip — **Strong / Approximate / Searching** — always visible during nav, color-coded and labeled. In Approximate we widen the halo and soften the "you've passed the turn" logic so we don't fire false reroutes.
- **Buildings / sections / landmarks emphasized:** building labels render at appropriate zoom with leader lines; the building you're *in* gets a subtle highlighted footprint; named sections (food courts, atria, the +15 levels) are first-class landmark nodes. This is the explicit fix for the iOS "missing landmarks / section naming" feedback.
- **Closures / detours:** see §4H — closed segments are un-routable and visibly dotted-red; detours announced proactively with the added distance.
- **Arrival:** camera eases in, the destination pin does a single spring-bounce, a success haptic fires, a confetti-free **"You've arrived — Earls Kitchen + Bar, Bankers Hall +15"** card slides up with "Done" and "Save this place." Tasteful, not a party.

---

## 6. Map experience

- **Base map philosophy:** the network is the star; the city is context. Custom vector base (dark CartoDB or a Mapbox/MapLibre style tuned to near-monochrome) so the **teal skywalk lines and building footprints carry all the color.** Streets/blocks desaturated; water/parks barely tinted. The repo already renders the +15 as crisp vector from the bridge graph — keep that; it's the best thing in the current app.
- **Layer hierarchy (bottom→top):** base tiles → building footprints → skywalk lines (status-colored) → landmark/section glyphs → business pins (clustered) → route line (when active) → origin/destination pins → user puck → labels. Labels always on top, collision-managed.
- **Active route styling:** a bright brand-gradient line, 6dp, with a soft outer glow; traversed portion dims to 40%; a subtle animated "flow" pulse travels along the un-walked path (slow, 1 cycle/4s) to imply direction. Off-route alternatives hidden during active nav.
- **Nearby businesses:** small category-tinted dots; tap → label; cluster into a count badge when zoomed out. Never show all 45+ at once at low zoom — declutter aggressively.
- **Landmark styling:** distinct rounded-square glyphs (transit, washroom, escalator, atrium) larger than business dots; these are the wayfinding anchors and stay visible one zoom level longer than businesses.
- **Search & filter UX:** search bar docked top of Explore; filter chips (Food / Open now / Accessible / Washroom / Transit) below; selecting a chip filters both list and map markers in sync with a 240ms cross-fade.
- **Zoom behaviors:** semantic zoom — far: network skeleton + major buildings only; mid: building names + landmarks; near: business pins + section labels + level badges.
- **2D vs 2.5D:** primarily clean 2D. A **subtle 2.5D tilt (≤35°) only during active navigation** to convey "ahead," with extruded building footprints at low opacity. Never an isometric toy-town look — that reads cheap.
- **Floor / elevation context:** the +15 is, by definition, one level — but buildings have ground + +15. A small **level badge** ("+15" / "Ground") on the puck and a one-line "you're on the +15 level" banner handle this without a full floor-switcher (which would over-engineer a single-level network). Design the data model to allow multi-level later (§11).
- **Closures overlay:** toggleable; closed bridges dotted-red, limited bridges dashed-amber, with an "i" tap target.
- **"You are here" orientation mode:** long-press the recenter FAB → a brief AR-free "orient me" mode that rotates the map heading-up and pulses the nearest two named buildings so the user can match the map to what they see.
- **Touch gestures:** one-finger pan, pinch zoom, two-finger rotate (with snap-to-north detent + haptic), two-finger drag to tilt (only in nav), double-tap zoom-in, two-finger tap zoom-out. Edge-swipe reserved for Android predictive back.
- **Recenter FAB:** appears only when follow is broken; shows a "north-up vs heading-up" sub-state.
- **Compass:** a small compass appears whenever the map is rotated off-north; tap snaps back to north with a light haptic; auto-hides at true-north.

---

## 7. Business discovery system

Evolve the Calgary Plus 15 listing concept (map placement + website + phone) into a real, trustworthy discovery layer.

- **Directory model:** every business is filed under exactly one primary `category` (the existing 8: food, retail, services, transit, washroom, hotel, health, entertainment) and lives inside one `building`. The directory is browsable **by category** and **by building** (two lenses on the same data).
- **Categories:** the 8 above, each with a tinted glyph; "Food & Dining" and "Retail" lead because that's the lunchtime intent.
- **Search:** fuzzy across name + category + building; recents and "open now nearby" pre-fill; results carry network-distance + open-state.
- **Featured / promoted:** a single horizontal "Featured on the +15" row on Explore, **capped at 5**, each card clearly tagged with a small "Featured" pill. Sponsored ≠ search-ranking manipulation (see rules below).
- **Nearby:** sorted by **graph distance from your current node**, not lat/lng — the whole point of the +15 is that crow-flies distance lies.
- **Open now:** parse the existing `hours` string (e.g. "Mon-Fri 6:00-20:00, Sat-Sun 8:00-18:00") into structured opening hours and compute open/closed + "closes in 20 min." **[ASSUMPTION]** migrate `hours` from free string to structured `OpeningHours` (§11) — flagged for V1.
- **Business detail page:** hero (logo or category glyph), name, category chip, open-now + today's hours expandable to the week, building + level, network distance/time, description, and the CTA trio.
- **CTAs:** **Navigate here** (primary, gradient — routes from your node), **Call** (`tel:` intent), **Website** (Custom Tab). All three from the iOS source concept, but elevated.
- **Sponsored placement rules (trust-preserving):** sponsored content appears **only** in the labeled Featured row and as an optional "Promoted" tag on a map pin — **never** injected above organic search results, never altering distance sorting, never more than 1 sponsored pin per viewport. A sponsored result that's closed-now is demoted. Transparency tag is non-negotiable.

---

## 8. Home screen concept (Explore)

A glass-over-map home. Content hierarchy, top → bottom, as a draggable sheet over the live map (collapsed to ~45% height, expandable):

1. **Context line (hero state):** *"You're near Bankers Hall · +15 level"* + live confidence dot. If a routine matches now → this becomes a **"Start: Morning commute"** gradient chip (the single most premium moment on the home screen).
2. **Search bar** (tap → full search). Persistent, docked.
3. **Quick destinations:** Washrooms · Food · Transit (CTrain) · Nearest exit — four tappable pills that instantly filter the map + list. These are the real downtown intents.
4. **Live notice (conditional):** a slim amber/red banner only if closures affect nearby paths → taps into Alerts.
5. **Featured on the +15:** max-5 horizontal cards, "Featured" tagged.
6. **Categories grid:** 8 tinted tiles.
7. **Nearby, open now:** vertical list sorted by network distance.
8. **Start navigating** is always reachable via the Navigate tab; on Explore it surfaces contextually (routine chip / after selecting a destination).

**Motion/interaction:** the sheet uses a spring drag with two detents (peek / expanded); pulling it down reveals more map (so the map and content trade space, never fight). Cards stagger-fade in (40ms cadence) on first load only. Pull-to-refresh on the sheet re-syncs closures + open-now. Restrained: nothing moves unless the user or live data moved.

---

## 9. Screen-by-screen breakdown

Format per screen: **Purpose · Components · Interactions · Tone · Empty · Error · Motion.**

**Splash** — *Purpose:* warm cold-start, preload graph/data. *Components:* centered wordmark, the +15 graph drawing in as line art. *Interactions:* none (auto-advance). *Tone:* cinematic, dark. *Empty/Error:* if data load fails, fall to a "Retry" state, never hang. *Motion:* graph strokes draw in 600ms then dissolve into the real map.

**Onboarding** — *Purpose:* explain value + earn permission. *Components:* 3 cards, page dots, Next/Skip, final "Enable location." *Interactions:* swipe/next; Skip → browse mode. *Tone:* friendly, confident. *Empty:* n/a. *Error:* n/a. *Motion:* parallax between cards; the graph art persists across cards (shared element).

**Permission education** — *Purpose:* pre-frame the OS prompt. *Components:* icon, one-paragraph why, "Enable" + "Not now." *Interactions:* Enable → OS dialog; Not now → browse mode + later banner. *Tone:* honest, no dark patterns. *Error:* permanently-denied → deep-link to system settings with instructions.

**Sign-in / guest** — *Decision:* **guest-first, no mandatory account.** Optional sign-in only to sync saved routes across devices (V2). *Tone:* zero-friction. *Empty:* favorites stored locally (Hive) until/unless they sign in.

**Home (Explore)** — see §8. *Empty:* no GPS → "Pick a starting building" CTA + popular destinations. *Error:* data stale → soft banner "Showing last-saved network." *Motion:* sheet spring + stagger-in.

**Map** — see §6 (it's the substrate, not a separate route). *Empty:* tiles failing → cached vector skeleton still renders the network (offline-friendly, see §10). *Error:* "Map tiles offline — network still navigable." *Motion:* camera flies, semantic-zoom label fades.

**Search** — *Purpose:* find anything fast. *Components:* search field, filter chips, recents, results list w/ distance + open-state. *Interactions:* type-ahead fuzzy; chip filters; tap → detail. *Tone:* fast, quiet. *Empty:* pre-type recents + "open now nearby." *No-results:* "No match for 'X' — try a category" + category chips. *Motion:* results reflow 120ms; keyboard-aware sheet.

**Business directory** — *Purpose:* browse by category/building. *Components:* segmented (By category / By building), grouped list. *Interactions:* expand group, tap business. *Tone:* structured, calm. *Empty:* "This building has no listed businesses yet." *Motion:* group expand spring.

**Business detail** — see §7. *Components:* hero, chips, hours, mini-map, CTA trio. *Empty:* missing hours → "Hours not listed" (never fake "open"). *Error:* call/website unavailable → CTA disabled with reason. *Motion:* shared-element from card; CTA trio slides up.

**Route preview** — *Purpose:* choose & confirm a route. *Components:* From/To, 3 option cards (Fastest/Accessible/Explorer) with time + distance + bridge count, step list, "Start." *Interactions:* swap From/To, pick option (camera updates), expand steps. *Tone:* confident. *Empty:* same origin/dest → inline hint. *Error:* no path (all routes closed) → "No open path right now — here's why" → Alerts. *Motion:* camera fly origin↔dest; option switch re-draws line.

**Active navigation** — see §5. *Components:* current-step banner, then-line, confidence chip, recenter FAB, end-nav. *Interactions:* auto-advance steps, reroute, recenter, end. *Tone:* hyper-clear, big type. *Empty:* n/a. *Error:* lost signal → "Searching — keep following the highlighted bridge." *Motion:* step banner cross-fades; turn haptics; 2.5D tilt.

**Arrival** — see §5. *Components:* success card, Save place, Done. *Tone:* warm, brief. *Motion:* pin spring-bounce + success haptic.

**Alerts / Closures** — *Purpose:* live network conditions. *Components:* list of closures/limited segments with affected buildings, time, reason, "Show on map." *Interactions:* tap → map highlights segment. *Tone:* factual, calm. *Empty:* **"All clear — the whole +15 is open right now."** (a delightful empty state). *Error:* feed down → "Couldn't refresh closures — last updated 9:41." *Motion:* none gratuitous.

**Favorites / Saved** — *Purpose:* one-tap repeats. *Components:* Routines, Favorite places, Recents. *Interactions:* tap → preview or instant-launch; swipe to delete; "make routine." *Empty:* "Save a place or route to see it here" + example. *Motion:* swipe spring.

**Settings** — *Components:* theme (system/light/dark), haptics toggle, units, accessible-routing default, heading-up/north-up default, about. *Tone:* tidy. *Motion:* none.

**Help / feedback** — *Components:* "How to read the map" mini-guide, report-a-closure, send feedback (prefilled device/app version). *Tone:* helpful. *Empty:* n/a. *Error:* offline send → queue + "We'll send when you're back online."

---

## 10. Android system design (Flutter-first)

### Recommended stack (production)
- **Flutter 3.2x+, Dart 3.6+**, **Impeller** renderer (smooth on Android), `minSdk 24`, `targetSdk` latest.
- **State:** Riverpod (already in repo) — keep; standardize on `Notifier`/`AsyncNotifier`.
- **Routing:** `go_router` (already) with a `StatefulShellRoute` for the persistent map + 3 tabs.
- **Map:** **`flutter_map` (already in repo)** with a custom vector/dark tile style; evaluate **MapLibre GL (`maplibre_gl`)** for V2 if true vector tiles + tilt are needed (recommend staying on `flutter_map` for V1 — it already draws the network beautifully and avoids a native-view rewrite).
- **Location:** `geolocator` (already) for position; add `flutter_compass` for heading; keep the smoothing in `course_tracker.dart`.
- **Persistence:** `hive_flutter` (already) for saved routes/favorites/recents + offline graph cache.
- **Fonts/anim:** `google_fonts`, `flutter_animate` (already).
- **Add:** `url_launcher` (call/website intents), `package_info_plus` (feedback), `sentry_flutter` (crash), and a thin analytics wrapper.

### Component architecture (feature-first, matches repo)
```
lib/
  core/      theme tokens, router, constants, result/error types
  data/      models, datasources (json→remote later), graph + A* pathfinder
  features/
    explore/   (home + categories + featured + nearby)
    search/
    businesses/ (directory + detail)
    navigate/   (route planner + active nav + arrival)
    map/        (map shell, layers, puck, course_tracker)
    saved/
    alerts/
    settings/  (+ permissions, help, feedback)
  shared/    providers, glass widgets, pills, sheets, shimmer (already present)
```
Each feature = `screen` + `widgets/` + a Riverpod `controller` (Notifier) + a repository it reads. Pure-Dart domain (graph, pathfinder, hours-parser) stays UI-free and unit-tested.

### Navigation architecture
`StatefulShellRoute.indexedStack` keeps the map alive across Explore/Navigate/Saved (no rebuild, instant tab switch). Detail sheets are pushed as `ModalBottomSheetRoute`/Hero. Deep links (below) resolve into the shell.

### State management
- `locationProvider` (AsyncNotifier streaming `geolocator` + compass, smoothed).
- `networkGraphProvider` (loads buildings/bridges, exposes A\*).
- `routeControllerProvider` (origin, dest, mode, computed route, nav state machine: `idle → previewing → navigating → arrived`).
- `closuresProvider` (poll/stream; affects graph edge weights/availability).
- `discoveryProvider` (categories, featured, nearby-by-graph-distance, open-now).
Immutable state classes; `select` to minimize rebuilds; the map listens to `locationProvider` via a `ValueListenable` bridge to avoid full-tree rebuilds at GPS tick rate.

### Maps SDK considerations
Custom dark/light tile theme; marker clustering; semantic zoom layers; keep the route polyline + glow as a custom `Polyline`/painter layer. If tilt/3D becomes a hard requirement, that's the trigger to move the map view to MapLibre GL — isolate map behind a `MapView` interface now so it's swappable.

### Location services
While-in-use only; `LocationSettings` with `distanceFilter` ~3m, `accuracy: high`; battery-aware downgrade when stationary; **never** background. Graceful approximate-mode. All permission flows via `permission_handler` (already).

### Offline caching
Cache the **entire network graph + business directory in Hive** on first load (it's small — 107 buildings/119 bridges/45 shops fits in <1MB). Cache map tiles with `flutter_map`'s tile cache. Result: the network is **fully navigable offline**; only live closures + open-now need connectivity, and they degrade to "last updated" gracefully.

### Performance
- Const widgets, `RepaintBoundary` around the map and the live puck so GPS ticks don't repaint sheets.
- Throttle location → UI at 4–10 Hz; do pathfinding off the UI isolate (`compute`) for large reroutes.
- Pre-warm fonts; lazy-load detail images; cluster markers; cap simultaneous animations.
- Target: cold start < 2s to interactive map, 120fps scroll on the Explore sheet.

### Accessibility implementation
`Semantics` on all markers/steps/CTAs; `LiveRegion` for turn announcements; honor `MediaQuery.textScaler` & `disableAnimations`; 48dp+ targets; contrast-checked tokens; status conveyed by shape+color.

### Motion implementation
`flutter_animate` for entrance/stagger; `AnimatedMapController`-style camera flies; physics springs for sheets/markers; a single `MotionTokens` class (durations + curves) so timing is centralized and reduce-motion can swap curves globally.

### Theming architecture
Single source: `AppPalette` + `AppTheme` (already). Add `MotionTokens`, `Elevation`, `Radii`, `Spacing` token classes. Theme mode from a `settingsProvider` (system/light/dark). Optional Material You dynamic color as an opt-in accent (kept off by default to protect brand).

### Deep linking
`plus15://business/{id}`, `plus15://navigate?to={id}&from={id|me}`, `plus15://alerts`, plus `https://plus15.com/...` App Links. Enables sponsored "Navigate here" links and notifications.

### Analytics events
`onboarding_complete`, `permission_granted/denied/approximate`, `search_performed{query,results}`, `business_viewed{id,category}`, `cta_navigate/call/website{id}`, `route_planned{mode,bridges,distance}`, `nav_started/arrived/aborted`, `reroute{reason}`, `closure_encountered`, `favorite_added`, `routine_launched`. Privacy-first, no PII, opt-out in Settings.

### Crash / error monitoring
`sentry_flutter` with release health, breadcrumbs on nav-state transitions, and a custom `Result<T,E>` so domain errors are typed (no silent catch).

### Feature flagging
A lightweight `FeatureFlags` provider (remote-config backed in V2; const map in V1) gating: sponsored row, 2.5D nav tilt, MapLibre swap, multi-level. Lets you dark-launch the map engine swap.

### Scalability
Datasource interface lets JSON assets be swapped for a CMS/API with zero UI change; graph supports multi-level + new buildings via data only; sponsored/closures are server-driven. Repository pattern + isolated map view = each subsystem evolves independently.

### Compose mapping (only if forced native — not recommended)
| Flutter | Kotlin/Compose equivalent |
|---|---|
| Riverpod | Hilt + ViewModel + StateFlow |
| go_router StatefulShellRoute | Navigation-Compose + nested graphs |
| flutter_map | Google Maps Compose / MapLibre Android |
| geolocator + flutter_compass | FusedLocationProvider + SensorManager |
| Hive | DataStore / Room |
| flutter_animate | Compose `animate*AsState`, AnimatedContent |
| BackdropFilter glass | `Modifier.blur` + `RenderEffect` (API 31+) |

---

## 11. Data model and content model

Entities and key fields (✚ = new/extended vs current repo):

- **Business** *(was Shop)* — `id, name, buildingId, category, ✚categories[], openingHours(structured ✚), phone, website ✚, description, ✚logoUrl, ✚levelNodeId, ✚verified:bool, ✚sponsoredUntil:DateTime?`.
- **Category** — `key (enum: food, retail, services, transit, washroom, hotel, health, entertainment), label, icon, color`.
- **Building** — `id, name, ✚aliases[] (handles ownership renames — fixes "section naming" complaints), lat, lng, address, type, amenities[], ✚levels[], ✚footprint:Polygon ✚`.
- **LocationNode** ✚ *(graph vertex)* — `id, buildingId, level (ground/+15/…), lat, lng, kind (junction|entry|landmark|business), accessible:bool`.
- **PathwaySegment** *(was Bridge, generalized)* — `id, fromNodeId, toNodeId, distanceM, hasElevator, hasStairs, isAccessible, status (open|limited|closed), ✚geometry:LineString, ✚indoor:bool`.
- **Landmark** ✚ — `id, nodeId, name, type (atrium|foodcourt|escalator|washroom|transit|art), ✚visibilityZoom`.
- **Route** — `id, fromNodeId, toNodeId, mode (fastest|accessible|explorer), steps[Step], distanceM, etaMin, ✚bridgeCount`; **Step** — `instruction, segmentId, ✚bridgeName, ✚enterBuildingId, ✚level, distanceM, maneuver`.
- **Closure** ✚ — `id, segmentId(s)[], status, reason, startsAt, endsAt?, source (city|user-report|verified)`.
- **SavedPlace** ✚ — `id, businessId|nodeId, label, createdAt`.
- **SavedRoute** *(exists)* — `id, name, fromId, toId, routeType, createdAt, isRoutine` ✚ `timeWindow? (for routine surfacing)`.
- **RecentSearch** ✚ — `query, resultId?, timestamp`.
- **SponsoredListing** ✚ — `id, businessId, slot (featured|pin), startsAt, endsAt, priority`.
- **Alert / Notification** ✚ — `id, type (closure|event|promo), title, body, deepLink, severity, expiresAt`.

### How the directory and the navigation graph relate
**`buildingId` is the join key, and `LocationNode` is the bridge between commerce and routing.** A Business belongs to a Building and is pinned to a `levelNodeId` on the graph; "Navigate here" resolves Business → `levelNodeId` → nearest graph node, then A\* from the user's snapped node. PathwaySegments form the routable graph; Buildings own their nodes; Landmarks decorate nodes for human-readable steps. This separation means the **discovery layer and the routing layer share geometry but evolve independently** — add businesses without touching the graph, and add bridges/levels without touching the directory.

---

## 12. Admin / content opportunities

- **Updating businesses:** CMS-backed `BusinessRepository` (Firestore/Strapi/Sanity) with the datasource interface from §10; verified-owner self-serve edits for hours/logo/description with moderation.
- **Sponsored listings:** scheduled `SponsoredListing` records (slot + window + priority) honoring §7 trust rules; auto-expire; clearly tagged.
- **Temporary closures:** ingest the **City of Calgary +15 service updates** (manual entry V1, scraped/API V2) into `Closure`; instantly affects routing via edge availability; user "report a closure" feeds a moderation queue.
- **Event popups:** time-boxed `Alert(type: event)` with deep link — e.g. Stampede, conventions at the BMO/convention buildings.
- **Seasonal highlights:** curated Featured sets ("Warm lunch spots," "Stampede route") swapped via CMS.
- **Promotions:** business-attached offers surfaced on detail pages + an optional Featured tag; never injected into search ranking.
- **Analytics dashboard:** funnel (search → view → navigate → arrive), top routes, closure impact, sponsored CTR/arrival-rate — proves commercial value to listing partners.
- **CMS integration:** all of the above behind one content service; app reads via cached repositories so editorial changes appear without an app release.

---

## 13. Mind-blowing details (premium micro-interactions)

1. The +15 network **draws itself in** as line art on splash, then dissolves seamlessly into the live map — your first frame *is* the brand.
2. The "you-are-here" puck has a **breathing halo** sized to real GPS accuracy — it visibly tightens as your fix improves.
3. **Snap-to-node** gives a tiny haptic tick the moment you're confidently inside a building — you *feel* arrival before you read it.
4. Camera **flies the geography** on route preview (origin→dest, eased) so you absorb the path spatially in one glance.
5. A slow **"flow" pulse travels the un-walked route line** — direction without an arrow.
6. The **walked portion of the route dims** behind you in real time — progress you can see.
7. Turn haptics: **one light tick 30m out, one medium at the turn** — eyes-free confidence.
8. **Tabular figures** on every distance/ETA so digits never jump while counting down.
9. **Compass detent**: rotating the map snaps to north with a satisfying click + haptic.
10. **Two-detent home sheet** with a real spring — pull down to reveal map, it trades space, never fights.
11. **Shared-element** business card → detail sheet; the logo flies, nothing pops.
12. **Open-now is alive**: "Closes in 20 min" turns amber as closing nears.
13. **Routine clairvoyance**: at 8:10am near Eau Claire, the home hero pre-loads "Start: Morning commute."
14. **Honest confidence chip** (Strong/Approximate/Searching) — trust through transparency, the opposite of every map that lies.
15. **Landmark-relative guidance indoors** ("walk toward the glass atrium") when metres become meaningless.
16. **"All clear" empty state** on Alerts that genuinely feels good to see.
17. **Arrival**: destination pin does a single spring-bounce + success haptic + a calm card — celebration without confetti.
18. **Proactive reroute**: "Path ahead closed — found a way around (+90 m)" *before* you hit the locked door.
19. **Orient-me mode**: long-press recenter → map goes heading-up and pulses two named buildings so you can match map to reality.
20. **Skeleton-that-matches**: loading shimmers are the exact shape of the content that lands (no layout shift).
21. **Building footprint you're inside gently highlights** — ambient "you are here."
22. **Pull-to-refresh** re-syncs closures + open-now with a teal skywalk-line progress stroke, not a generic spinner.
23. **Dark-mode line glow** brightens to `skywalkBright` so the network literally lights up at night.
24. **Predictive-back** wired so swiping back from a sheet shows the map peeking — native and buttery.
25. **Tappable closed segment** explains itself ("Closed for maintenance until 5pm — City of Calgary") instead of just being red.

---

## 14. UI copy examples

**Onboarding**
- "The +15, finally easy. 16 km of skywalk. 100+ buildings. One calm map."
- "Know exactly where you are — and exactly where to turn. Even four storeys up."
- "Turn on location so we can place you in the network and guide you step-by-step. While-in-use only. Never in the background."

**Permission prompts**
- Enable: "Show me where I am" · Decline: "Not now — I'll browse"
- Denied later (banner): "Location's off. Pick a starting building and you're good to go."
- Approximate granted: "Got an approximate fix — follow the highlighted bridge and we'll tighten it up."

**Empty states**
- Search (pre-type): "Looking for coffee, a washroom, or a way out? Start typing."
- No results: "Nothing matches 'X.' Try a category instead." 
- Alerts: "All clear — the entire +15 is open right now."
- Saved: "Save a place or route and it'll wait for you here."

**Error states**
- No path: "Every route there is closed right now. Here's why →"
- Tiles offline: "Map's offline, but the network's still fully navigable."
- Closures feed down: "Couldn't refresh closures — showing last update, 9:41am."

**Route recalculation**
- "Path ahead closed — I've found a way around (+90 m)."
- "Looks like you took a different turn. Recalculating…"

**Arrival**
- "You've arrived — Earls Kitchen + Bar, Bankers Hall, +15 level."
- Secondary: "Save this place" · "Done"

**Closures**
- "Limited access: TD Square ↔ Hudson's Bay bridge. Elevator out until 5pm."
- "Closed for maintenance until 5:00pm — City of Calgary."

**Business CTA labels**
- "Navigate here" · "Call" · "Visit website" · "Save"

**Search suggestions**
- "Coffee near you" · "Open now" · "Washrooms" · "CTrain access" · "Nearest exit"

---

## 15. Figma-ready design brief

**Goal:** Transform Plus 15 into the unmistakably best digital interface for Calgary's +15 — premium, calm, confidence-inspiring, dark-mode-hero.

**Deliver in Figma:**
- **Foundations page:** color tokens (table in §2), type scale (Plus Jakarta Sans + Inter, with tabular-figures style), radii (28/20/14/12), elevation (glass blur + single soft shadow), spacing (4-pt grid), motion tokens (120/240/600–900ms, spring specs), iconography (Material Symbols Rounded, tinted chips).
- **Components (variants + dark/light):** glass panel, card (flat hairline), pill/chip, segmented control, search bar, category tile, business card + detail sheet, route option card, step row, current-step nav banner, confidence chip, closure banner, FAB (recenter/compass), bottom bar (3 tabs), the location puck (accuracy/heading/level states).
- **Map style:** dark + light vector base (desaturated city, teal network), status line styles (open/limited/closed), pin set (origin/dest/business/landmark/cluster), 2.5D nav tilt mock.
- **Flows (prototype):** onboarding → permission; Explore home (2 sheet detents); search → detail → navigate → active nav → arrival; closure reroute; saved/routine one-tap launch.
- **States:** every screen with empty / loading-skeleton / error per §9.
- **Specs:** 8-pt redlines, 48dp+ targets, contrast annotations, reduce-motion variants.

**Don'ts:** stock city photos, multi-stop gradients, heavy shadows, cluttered all-pins-at-once maps, old-Android visuals.

---

## 16. Engineering handoff

**Modules:** `core` (theme/router/tokens), `data` (models/datasources/graph+A\*), `features/{explore,search,businesses,navigate,map,saved,alerts,settings}`, `shared` (providers/glass widgets).

**Key components:** MapShell + layer painters, LocationPuck, RouteController state machine, A\* pathfinder (exists), OpeningHours parser (new), GlassPanel, BusinessCard/DetailSheet, RouteOptionCard, NavStepBanner, ConfidenceChip, ClosureBanner.

**APIs needed (V1 local JSON → V2 service):**
- `GET /buildings`, `/segments`, `/businesses`, `/landmarks` (seed from current assets)
- `GET /closures` (poll/stream; City of Calgary ingest)
- `GET /featured`, `/sponsored`
- `POST /feedback`, `/closure-report`
- (V2) auth + saved-sync, analytics sink, remote feature flags.

**Data contracts:** §11 entities as JSON schemas; `status` enum (open|limited|closed); structured `OpeningHours`; `Route`/`Step` shape stable for UI.

**Priority phases:** see §17.

**MVP vs V2** — **MVP:** Flutter shell + 3 tabs + persistent map, GPS puck w/ snap + confidence, A\* routes (Fastest/Accessible/Explorer), active turn-by-turn w/ reroute, directory + detail + 3 CTAs, search, saved/recents, manual closures, offline graph cache, full dark/light + a11y. **V2:** account sync, CMS + sponsored, City closures API, events/promos, 2.5D MapLibre engine, multi-level, push notifications, analytics dashboard.

**Key risks:** (1) GPS accuracy above-grade — *mitigation:* graph-snap + confidence honesty + landmark guidance; (2) data freshness (hours/closures) — *mitigation:* structured hours + City ingest + user reports + "last updated"; (3) map engine ceiling for tilt — *mitigation:* `MapView` interface, flag-gated MapLibre swap; (4) sponsored eroding trust — *mitigation:* strict §7 rules; (5) building-name churn — *mitigation:* `aliases[]`.

**QA checklist:** permission grant/deny/approximate/permanently-denied; offline launch navigable; reroute on closure mid-walk; no-path handling; TalkBack reads markers/steps/CTAs; 200% text reflow; reduce-motion; dark/light parity; predictive-back from every sheet; tabular figures don't shift; cold start < 2s; 60–120fps map pan; call/website intents; deep links resolve; battery drain in 20-min nav within budget.

---

## 17. Build plan

**Phase 1 — UX foundations (1–2 wks).** *Objectives:* lock IA (3-tab + persistent map), flows, copy, token classes. *Deliverables:* navigation skeleton (`StatefulShellRoute`), Motion/Radii/Elevation/Spacing tokens, empty/error inventory. *Success:* tap-through prototype of all routes; every screen has defined states.

**Phase 2 — Visual system (1–2 wks).** *Objectives:* implement design language. *Deliverables:* themed components (glass panel, cards, chips, sheets, bottom bar, puck), dark/light, Figma foundations + component library. *Success:* a11y contrast + 48dp audits pass; reduce-motion variants exist.

**Phase 3 — Map & GPS core (2–3 wks).** *Objectives:* the confidence engine. *Deliverables:* custom vector map style, layer hierarchy + semantic zoom, location puck w/ smoothing + graph-snap + confidence chip, follow/recenter/compass, offline graph cache. *Success:* puck stays sane on a real downtown walk; offline launch fully navigable.

**Phase 4 — Business directory (1–2 wks).** *Objectives:* useful, trustworthy discovery. *Deliverables:* directory (category/building), search w/ fuzzy + network-distance + open-now, detail page + 3 CTAs, Featured row w/ trust rules, OpeningHours parser. *Success:* "coffee" → nearest open Starbucks by network distance → Navigate in ≤3 taps.

**Phase 5 — Live navigation polish (2–3 wks).** *Objectives:* the wow. *Deliverables:* route preview camera fly + 3 options, turn-by-turn banner + haptics + landmark guidance, reroute + proactive closure detour, 2.5D nav tilt, arrival moment, routines/quick-launch. *Success:* first-timer completes a multi-bridge route without backtracking; reroute fires before the locked door.

**Phase 6 — Launch prep (1–2 wks).** *Objectives:* ship-ready. *Deliverables:* analytics, Sentry, deep links + App Links, feature flags, store assets, perf pass, full QA matrix, City closures ingest (manual ok for launch). *Success:* cold start < 2s, crash-free > 99.5% in beta, QA checklist green, store listing live.

---

# Final deliverables

### 1. Creative direction statement
Plus 15 is a luminous, glass-over-ink wayfinding instrument built for one extraordinary place — Calgary's +15 — where calm typography, a single glowing teal network, and motion that *explains the geography* turn the most disorienting indoor maze in Canada into a quietly confident walk; it never pretends GPS is perfect above-grade, so it earns trust by being honest, snapping you to named bridges and buildings, and guiding by the landmarks you can actually see, until the app feels less like a map and more like a local who always knows exactly where you are.

### 2. Feature priority table

| Feature | Must Have | Should Have | Nice to Have |
|---|:--:|:--:|:--:|
| 3-tab shell + persistent map | ✅ | | |
| GPS puck w/ graph-snap + confidence chip | ✅ | | |
| A\* routing (Fastest/Accessible/Explorer) | ✅ | | |
| Turn-by-turn + reroute + landmark guidance | ✅ | | |
| Business directory + detail + Navigate/Call/Website | ✅ | | |
| Search (fuzzy, network-distance, open-now) | ✅ | | |
| Saved / recents | ✅ | | |
| Offline graph cache | ✅ | | |
| Full dark/light + accessibility | ✅ | | |
| Manual closures + reroute | ✅ | | |
| Routines / one-tap quick-launch | | ✅ | |
| Structured opening hours | | ✅ | |
| Featured/sponsored (trust-ruled) | | ✅ | |
| City of Calgary closures ingest | | ✅ | |
| 2.5D nav tilt | | ✅ | |
| Account + cross-device sync | | | ✅ |
| Events/promos + push notifications | | | ✅ |
| Multi-level buildings | | | ✅ |
| MapLibre vector engine swap | | | ✅ |
| Partner analytics dashboard | | | ✅ |

### 3. App store positioning line
**"Plus 15 — the calm, confident way to find anything on Calgary's +15, even four storeys up."**
