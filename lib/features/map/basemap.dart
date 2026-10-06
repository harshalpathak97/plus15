import 'package:flutter/material.dart';

/// Base map styles under the +15 overlay. All keyless Esri ArcGIS Online
/// tile services (Google's tile servers can't be used directly under their
/// terms); attribution is shown on the map.
enum Basemap {
  map('Map', Icons.map_outlined),
  streets('Streets', Icons.signpost_outlined),
  satellite('Satellite', Icons.satellite_alt_outlined),
  terrain('Terrain', Icons.terrain_outlined);

  final String label;
  final IconData icon;
  const Basemap(this.label, this.icon);

  static const _esri = 'https://server.arcgisonline.com/ArcGIS/rest/services';

  /// "Map" is the quiet grey canvas and follows the app's light/dark theme.
  String url(bool isDark) => switch (this) {
        Basemap.map => isDark
            ? '$_esri/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}'
            : '$_esri/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}',
        Basemap.streets => '$_esri/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
        Basemap.satellite => '$_esri/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        Basemap.terrain => '$_esri/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
      };

  /// Highest zoom with real tiles; the map scales them up beyond this.
  int get maxNativeZoom => this == Basemap.map ? 16 : 19;

  /// Whether +15 overlays should use their light-on-dark styling.
  bool darkSurface(bool isDark) =>
      this == Basemap.satellite || (this == Basemap.map && isDark);

  /// Shown on the map. "Powered by Esri" is required by Esri's terms; the
  /// OpenStreetMap credit also covers the fallback tiles and our door data.
  String get attribution => this == Basemap.satellite
      ? 'Powered by Esri · Maxar, Earthstar Geographics · © OpenStreetMap contributors'
      : 'Powered by Esri · HERE, Garmin · © OpenStreetMap contributors';

  static Basemap fromName(String? name) =>
      Basemap.values.firstWhere((b) => b.name == name, orElse: () => Basemap.map);
}
