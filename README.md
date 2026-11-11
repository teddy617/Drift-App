# Drift v0.5 — Journey Mode (prototype)

Based on the working v0.4 refinement. New features:
- Glowing route preview and glowing full-screen journey route.
- Separate external Google Maps directions link.
- Start Journey opens Drift's full-screen map, with foreground GPS updates, compass heading, map rotation, recenter and north-up toggle.
- Local notes for each destination, saved using shared_preferences.
- Pause/resume, Phone Away overlay, End Journey, and manually confirmed arrival.
- Accessibility warning remains visible in journey mode.

## Limitations
- This is a prototype; it has **not** been compiled or device-tested in this environment. Use GitHub Actions to build and test.
- Journey GPS is foreground-only and may stop when the phone sleeps or the app backgrounds. Phone Away is a screen overlay, not background tracking.
- Compass quality varies by device and calibration. The heading sensor may be unavailable; north-up can be selected manually.
- Distance remaining is straight-line distance, not route distance. No turn-by-turn navigation or automatic rerouting is provided.
- Route verification does not guarantee legal access, safe conditions, or pedestrian routes.
- Notes are local to the device and not yet synced to a user account.

## Install
Upload `lib/main.dart`, `pubspec.yaml`, `README.md` and keep the supplied workflow and assets. Commit once. Build with GitHub Actions.

## v0.5.1 visual refinements
- Globe descent now continues to near-surface altitude over 3.8 seconds before map transition.
- Random panel collapses to a ~3.8% screen-height handle, including after destination generation.
- Journey immediately requests high-accuracy GPS and starts at street-level zoom 18; live follow and recenter use that zoom.
- GPS may need several seconds to acquire a fix; map cannot accurately center on the user until permission and location are available.

## v0.6 Intention Mode (development build)

Hybrid category + optional description, OSM geographic influences, adaptive point sampling,
OSRM routing, and weighted selection. Intention destinations remain unmarked points rather
than POI entrances. The existing Random and Journey flows are retained.

**Limitations:** Public Overpass/OSRM services can be slow or unavailable. The geographic
context query is capped at 20 km around the start even when the user chooses a larger
radius; this means long-range intention coverage is incomplete. Time-of-day currently
uses the device's local clock, not the destination time zone. Social activity is only
heuristically estimated. No dedicated legal-access or wheelchair-access checks are added.
This build has not been compiled or device-tested in this environment.
