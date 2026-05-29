# Plus15 Navigator

A navigation app for Calgary's **+15 Skywalk Network** — the world's largest
elevated indoor pedestrian path system. Find your way between 100+ downtown
buildings without ever stepping outside.

## What's inside

- **Live vector map.** The +15 network is drawn as a crisp, glowing vector
  transit map directly from the real bridge graph — no raster overlays, sharp
  at every zoom level, and fully themed for light and dark. Skywalk lines are
  color-coded by status (open / limited access / closed).
- **Smart routing.** A\* pathfinding across the skywalk graph with three modes —
  Fastest, Accessible (elevator-only), and Explorer (routes you past more
  shops).
- **Live turn-by-turn navigation.** GPS tracking with smoothing, off-route
  detection, automatic rerouting on the network, and "nearest entry point"
  guidance when you're approaching from the street.
- **Search & explore** every shop, washroom, transit link, and amenity in the
  network, grouped by building.
- **Saved & routine routes** for one-tap launching of your daily commute.

## Architecture

```
lib/
  core/        theme (design tokens + palette), router, constants
  data/        models, JSON datasources, graph + A* pathfinder
  features/    map, search, route_planner, saved_routes, settings, shop_detail
  shared/      Riverpod providers, reusable widgets
```

State is managed with **Riverpod**; navigation with **go_router**; the map is
rendered with **flutter_map** over CartoDB base tiles.

## Running

```bash
flutter pub get
flutter run
```
