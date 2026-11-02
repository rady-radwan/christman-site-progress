import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../library_store.dart';
import '../main.dart' show themeMode;
import '../models.dart';
import '../util.dart';

const appVersion = '1.1.0';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _moving = false;
  int _done = 0;
  int _total = 0;

  Future<void> _changeFolder() async {
    final store = context.read<LibraryStore>();
    final dir = await getDirectoryPath(confirmButtonText: 'Use this folder');
    if (dir == null || !mounted) return;
    final hasData = store.projects.isNotEmpty;
    final ok = await confirm(
      context,
      title: 'Change library folder?',
      message: hasData
          ? 'If the chosen folder already contains a Christman Site Progress library, it will be opened. '
              'Otherwise all your projects, photos and videos (${prettySize(store.totalBytes)}) are moved there.\n\n$dir'
          : 'New photos and videos will be stored in:\n\n$dir',
      confirmLabel: 'Continue',
      destructive: false,
    );
    if (!ok || !mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ValueListenableBuilder<ThemeMode>(
                valueListenable: themeMode,
                builder: (context, mode, _) => SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
                    ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.computer_outlined), label: Text('System')),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) => themeMode.value = s.first,
                ),
              ),
            ),
          ),
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
