# Drift v0.4 — Random geographic prototype

New: logarithmic radius slider (0.1–1,000 miles), exact miles input, miles/km display toggle, route-verified random road points, accessibility warning, and starting-country restriction.

This prototype samples geographic coordinates and snaps them to a **driving road network** using public OSRM demo services. It is not a production-safe routing or access validation system. It does not verify pedestrian access, private property, road closures, terrain, border-crossing route legality, or personal safety. Even when the accessibility toggle is off, route verification is required.

The radius is a maximum **route distance**, not a guarantee that a destination can be found. The country restriction checks destination country but does not guarantee the route stays within it. The temporary country lookup uses public Nominatim with limited requests and must be replaced before production. The controls are session-only, not persisted settings.

No APK has been compiled or device-tested here. Replace `lib/main.dart` and `README.md`; existing `pubspec.yaml`, assets and workflow can remain unchanged.
