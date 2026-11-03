import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../library_store.dart';
import '../appearance.dart';
import '../theme.dart';
import '../models.dart';
import '../util.dart';

const appVersion = '1.5.0';

/// Cloud folders synced to this PC by their desktop apps.
List<(String, String)> detectCloudFolders() {
  final out = <(String, String)>[];
  if (!Platform.isWindows) return out;
  final env = Platform.environment;
  for (var c = 'D'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++) {
    final letter = String.fromCharCode(c);
    for (final sub in ['My Drive', 'Shared drives']) {
      final path = '$letter:\\$sub';
      try {
        if (Directory(path).existsSync()) out.add(('Google Drive · $sub', path));
      } catch (_) {}
    }
  }
  final home = env['USERPROFILE'] ?? '';
  for (final (label, path) in [
    ('Google Drive', p.join(home, 'Google Drive')),
    ('Google Drive', p.join(home, 'My Drive')),
    ('OneDrive', env['OneDriveCommercial'] ?? ''),
    ('OneDrive (personal)', env['OneDriveConsumer'] ?? ''),
    ('Dropbox', p.join(home, 'Dropbox')),
  ]) {
    if (path.isEmpty) continue;
    try {
      if (Directory(path).existsSync() && !out.any((e) => p.equals(e.$2, path))) out.add((label, path));
    } catch (_) {}
  }
  return out;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _moving = false;
  int _done = 0;
  int _total = 0;

  Future<void> _useCloud(String cloudRoot, String label) async {
    final target = p.join(cloudRoot, appFolderName);
    await _changeFolder(target: target, title: 'Use $label?');
  }

  Future<void> _changeFolder({String? target, String title = 'Change library folder?'}) async {
    final store = context.read<LibraryStore>();
    final dir = target ?? await getDirectoryPath(confirmButtonText: 'Use this folder');
    if (dir == null || !mounted) return;
    final shared = File(p.join(dir, libraryFileName)).existsSync();
    if (shared) {
      final ok = await confirm(
        context,
        title: 'Open shared library?',
        message: 'This folder already holds a Christman Site Progress library. The app will switch to it, '
            'and your current library stays where it is.\n\n$dir',
        confirmLabel: 'Open it',
        destructive: false,
      );
      if (!ok || !mounted) return;
      await _run(store, dir);
      return;
    }
    final hasData = store.projects.isNotEmpty;
    final ok = await confirm(
      context,
      title: title,
      message: hasData
          ? 'If the chosen folder already contains a Christman Site Progress library, it will be opened. '
              'Otherwise all your projects, photos and videos (${prettySize(store.totalBytes)}) are moved there.\n\n$dir'
          : 'New photos and videos will be stored in:\n\n$dir',
      confirmLabel: 'Continue',
      destructive: false,
    );
    if (!ok || !mounted) return;
    await _run(store, dir);
  }

  Future<void> _run(LibraryStore store, String dir) async {
    setState(() => _moving = true);
    try {
      final msg = await store.changeLibraryFolder(dir, onProgress: (d, t) {
        if (mounted) setState(() {
          _done = d;
          _total = t;
        });
      });
      if (mounted) showSnack(context, msg);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not change folder: $e');
    } finally {
      if (mounted) setState(() => _moving = false);
    }
  }

  Widget _cloudCard(LibraryStore store) {
    final scheme = Theme.of(context).colorScheme;
    final provider = store.cloudProvider;
    final folders = detectCloudFolders();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(provider == null ? Icons.computer_rounded : Icons.cloud_done_rounded,
                    color: provider == null ? scheme.onSurfaceVariant : scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    provider == null
                        ? 'Your library is on this computer only.'
                        : 'Shared through $provider. Changes from other computers appear automatically.',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (provider != null)
                  TextButton.icon(
                    onPressed: () async {
                      final changed = await store.refreshFromDisk();
                      if (mounted) showSnack(context, changed ? 'Updated with the latest changes' : 'Up to date');
                    },
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('Check now'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_moving) ...[
              Text('Copying files… $_done of $_total'),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
            ] else ...[
              if (folders.isEmpty)
                Text(
                  'No Google Drive folder found on this PC. Install "Google Drive for desktop", sign in, '
                  'then come back here — or choose any synced folder below.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (label, path) in folders)
                    if (!p.isWithin(path, store.root.path))
                      FilledButton.tonalIcon(
                        onPressed: () => _useCloud(path, label),
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: Text('Use $label'),
                      ),
                  OutlinedButton.icon(
                    onPressed: () => _changeFolder(title: 'Use this folder?'),
                    icon: const Icon(Icons.folder_shared_outlined),
                    label: const Text('Open a shared library folder…'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Text('How to share with your team', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              '1. Click "Use Google Drive" — your projects move into My Drive › $appFolderName.\n'
              '2. In Google Drive, share that folder with your colleagues as Editors (or keep it in a Shared drive).\n'
              '3. Each colleague installs Google Drive for desktop and this app, adds the shared folder to their '
              'My Drive (right-click › Organize › Add shortcut), then clicks "Open a shared library folder…" and picks it.\n'
              'Everyone then sees the same projects, photos and videos. The app checks for changes every 20 seconds.',
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('CLOUD & SHARING',
              style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          _cloudCard(store),
          const SizedBox(height: 20),
          Text('LIBRARY',
              style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Where your originals are stored', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  SelectableText(store.root.path),
                  const SizedBox(height: 6),
                  Text(
                    '${store.projects.length} projects · ${prettySize(store.totalBytes)} of photos and videos. '
                    'Files are kept exactly as imported — never resized or recompressed. '
                    'To back up, copy this whole folder.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  if (_moving) ...[
                    Text('Moving files… $_done of $_total'),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
                  ] else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (isDesktop)
                          OutlinedButton.icon(
                            onPressed: () => openInFileManager(store.root.path),
                            icon: const Icon(Icons.folder_open_outlined),
                            label: const Text('Open folder'),
                          ),
                        if (isDesktop)
                          OutlinedButton.icon(
                            onPressed: _changeFolder,
                            icon: const Icon(Icons.drive_folder_upload_outlined),
                            label: const Text('Change folder…'),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('APPEARANCE',
              style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          const _AppearanceCard(),
          const SizedBox(height: 20),
          Text('KEYBOARD',
              style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Project:  ← / → previous / next week  ·  Space play week by week\n'
                'Photo viewer:  ← / → previous / next photo  ·  ↑ / ↓ same shot in previous / next week  ·  '
                'Z or double-click zoom to actual pixels  ·  H hide controls  ·  Esc back\n'
                'Compare Progress:  scroll to zoom both photos together  ·  0 reset zoom',
                style: TextStyle(height: 1.6),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text('Christman Site Progress $appVersion',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) {
    final look = context.watch<AppAppearance>();
    final scheme = Theme.of(context).colorScheme;
    final label = Theme.of(context).textTheme.labelLarge;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Theme', style: label),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final t in appThemes)
                  _ThemeSwatch(spec: t, selected: look.themeId == t.id, onTap: () => look.setTheme(t.id)),
                _ThemeSwatch(
                  spec: themeById('christman-light'),
                  second: themeById('christman-dark'),
                  name: 'Match Windows',
                  selected: look.themeId == systemThemeId,
                  onTap: () => look.setTheme(systemThemeId),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text('Font', style: label),
            const SizedBox(height: 8),
            SizedBox(
              width: 420,
              child: DropdownButtonFormField<String>(
                key: ValueKey(look.effectiveFont),
                initialValue: look.effectiveFont ?? appFonts.first,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                items: [
                  for (final f in appFonts)
                    DropdownMenuItem(
                      value: f,
                      child: Text(f, style: TextStyle(fontFamily: f, fontSize: 15)),
                    ),
                ],
                onChanged: (v) => look.setFont(v),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Text('Text size', style: label),
                const Spacer(),
                Text('${(look.textScale * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            Row(
              children: [
                const Text('A', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: look.textScale,
                    min: 0.8,
                    max: 1.5,
                    divisions: 14,
                    onChanged: (v) => look.setTextScale((v * 20).roundToDouble() / 20),
                  ),
                ),
                const Text('A', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                TextButton(onPressed: () => look.setTextScale(1.0), child: const Text('Reset')),
              ],
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hospital · 45° angle', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text('Preview: Level 3 deck poured, curtain wall started on the east side.',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.spec, required this.selected, required this.onTap, this.second, this.name});

  final AppThemeSpec spec;
  final AppThemeSpec? second;
  final String? name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget mini(AppThemeSpec t) => Expanded(
          child: Container(
            color: t.surface,
            child: Column(
              children: [
                Container(height: 16, color: t.bar),
                Expanded(
                  child: Row(
                    children: [
                      Container(width: 22, color: t.sidebar),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(height: 22, decoration: BoxDecoration(color: t.card, borderRadius: BorderRadius.circular(3))),
                              const SizedBox(height: 5),
                              Container(
                                  width: 34,
                                  height: 9,
                                  decoration: BoxDecoration(color: t.primary, borderRadius: BorderRadius.circular(5))),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 150,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? scheme.primary : Theme.of(context).dividerTheme.color!, width: selected ? 3 : 1),
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
              child: SizedBox(
                height: 78,
                child: Row(children: [mini(spec), if (second != null) mini(second!)]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (selected) Icon(Icons.check_circle, size: 16, color: scheme.primary),
                  if (selected) const SizedBox(width: 4),
                  Flexible(
                    child: Text(name ?? spec.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
