# Christman Site Progress

A week-by-week record of construction sites from drone photos and videos.

- **Many projects, many buildings** — each project holds its own buildings/areas, with a cover (latest drone photo, your own picture, or an icon), its location, and live counts of buildings, capture dates, photos and videos.
- **Camera views per building** — Front, Back, Side, 45° angle, or your own. Shoot the same angle and elevation every week and each view gets its own timeline.
- **Timeline slider** — every capture sits at its real date on one bar that always fits the window. Drag the handle or click anywhere and it snaps to the nearest capture (or use ← / →); press ▶ to play capture by capture.
- **Overviews** — *All buildings* shows every building side by side with its latest photo and counts; picking a building shows all its camera views left to right, in your sidebar order.
- **Coordinated file names** — files are stored as `Project/Building/View/2026-11-02_Building_View_01.jpg` and renamed automatically when you rename a building or view or change a date. The camera's original name is kept for reference.
- **Share through Google Drive** — Settings › Cloud & sharing moves the library into Google Drive (or OneDrive/Dropbox). Colleagues open the same shared folder and see the same projects; the app merges changes from every computer and checks for updates every 20 seconds.
- **Team use** — everyone enters their name once; every photo shows who added it, and **Team & activity** lists people, when they were last active, and a feed of everything added or changed. A pop-up tells you when a teammate adds photos. People shared as *Viewer* in Google Drive get a view-only app. Each person writes only their own files in `team/`, so Google Drive never sees conflicting edits.
- **Original quality** — every photo and video is copied into the library byte-for-byte. Nothing is resized or recompressed. Photos open at full resolution and zoom to actual pixels.
- **Back-dating** — pick any capture date when adding files, so older history can be added too.
- **Same shot, next week** — in the photo viewer, ↑ / ↓ jumps to the same photo position in the previous/next week (handy for repeat drone waypoints).
- **Compare Progress** — before/after slider, side by side, or overlay with transparency for each photo. Each photo has its own week slider, and zoom is linked.
- **Videos** — per-week videos, or *Play all weeks in order* as one continuous playlist.
- **Make Timelapse** — turn a building/view's weekly photos into an MP4 (720p–4K, 16:9, 1:1 or 9:16) with a live preview. Overlay the date, week, day counter, building, view, project name and notes; zoom and pan with a camera path that carries over from week to week (set the start and end areas right on the preview); add a turning clock, flipping calendar or hourglass, a progress bar of capture dates, a title card, your logo and background music.
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

## Third-party

Timelapse export uses [FFmpeg](https://ffmpeg.org) (GPL build from [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds)), shipped as a separate `ffmpeg\ffmpeg.exe` next to the app with its license.
