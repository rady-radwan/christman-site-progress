# Christman Site Progress

A week-by-week record of construction sites from drone photos and videos.

- **Many projects, many buildings** — each project holds its own buildings/areas.
- **Timeline bar** — every capture date is a stop on the bar along the bottom. Click a week (or use ← / →) to see the site as it was then; press ▶ to play week by week.
- **Original quality** — every photo and video is copied into the library byte-for-byte. Nothing is resized or recompressed. Photos open at full resolution and zoom to actual pixels.
- **Back-dating** — pick any capture date when adding files, so older history can be added too.
- **Same shot, next week** — in the photo viewer, ↑ / ↓ jumps to the same photo position in the previous/next week (handy for repeat drone waypoints).
- **Compare weeks** — before/after slider or side by side.
- **Videos** — per-week videos, or *Play all weeks in order* as one continuous playlist.
- **Export originals** — any photo, selection, or whole date to a folder of your choice.

## Install (Windows)

Download `ChristmanSiteProgress-Setup-x.y.z.exe` from the latest **Release** and run it. No admin rights needed.

Your library lives in `Documents\Christman Site Progress` (changeable in Settings). Uninstalling the app does not delete it. To back up, copy that folder.

## Build

Built with Flutter so the same code can later ship to Android and iOS.

```
flutter pub get
flutter build windows --release
```

Every push to `main` builds the Windows installer with GitHub Actions and attaches it to the release for the version in `pubspec.yaml`. Bump `version:` there to publish a new release.
