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
