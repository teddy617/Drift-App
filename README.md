# Drift — Globe Prototype

Experimental Android Flutter application for the globe-to-map interaction. This is not a finished app.

## Android-only, no computer required

Upload the contents of this folder (not the enclosing folder or ZIP) into the root of your GitHub repository. **Preserve `.github/workflows/android-apk.yml`**. A push to `main` triggers an APK build, or use **Actions → Build Android APK → Run workflow**.

When the workflow succeeds, open its run and download the `drift-android-debug-apk` artifact. Extract the ZIP artifact on Android, then install `app-debug.apk`. Android may ask you to allow installations from your browser/file manager. Install only APKs from your own trusted workflow.

## What is implemented
- Interactive Earth rendered inside a Flutter WebView using Globe.gl and online assets.
- Three exploration mode entry buttons.
- Demo camera descent to a fixed point (40, -76), **not the user's location**.
- Separate OpenStreetMap tile view with draggable panel.

## Not implemented
- Location permission, manual starting-point selection, actual routing, destination generation, authentication, social features, offline use, production map-tile provider, or polished transitions.
- This source has not yet been compiled or tested on a device. The first CI run is the validation step.

## Notes
The GitHub Actions workflow generates Android platform scaffolding with `flutter create` during the build. This keeps the initial mobile upload small. The globe uses external CDN JavaScript and textures, and the map uses OSM's public tile server; both require internet access. These are **prototype-only** choices. Production must replace them with compliant, reliable providers and local/pinned assets.

The first run may take several minutes. A GitHub Actions artifact is a ZIP containing the APK; it is not the APK itself.
