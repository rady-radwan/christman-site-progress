import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../library_store.dart';
import '../models.dart';
import '../util.dart';
import 'settings_screen.dart';
import 'welcome.dart';

/// Who uses the shared library and what everyone has been doing.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  List<Member> _members = [];
  List<Activity> _activity = [];
  bool _loading = true;
  String? _projectFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = context.read<LibraryStore>();
    await store.refreshFromDisk();
    final m = await store.readMembers();
    final a = await store.readActivity(limit: 500);
    if (!mounted) return;
    setState(() {
      _members = m;
      _activity = a;
      _loading = false;
    });
  }

  Future<void> _editName() async {
    final store = context.read<LibraryStore>();
    final name = await promptText(context,
        title: 'Your name', initial: LibraryStore.user?.name ?? '', label: 'Shown to your team');
    if (name == null || name.trim().isEmpty) return;
    await saveUserName(store, name);
    await _load();
  }

  Future<void> _invite(LibraryStore store) async {
    final provider = store.cloudProvider;
    final text = 'Join our site progress library:\n'
        '1. Install Google Drive for desktop (https://www.google.com/drive/download/) and sign in.\n'
        '2. In Google Drive, open "Shared with me", right-click the "Christman Site Progress" folder → '
        'Organize → Add shortcut → My Drive.\n'
        '3. Install the Christman Site Progress app, open Settings → Cloud & sharing → '
        '"Open a shared library folder…", and choose that folder (inside My Drive).';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite teammates'),
        content: SizedBox(
          width: 540,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (provider == null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                      'Your library is still on this computer only. First move it to Google Drive in '
                      'Settings → Cloud & sharing → "Use Google Drive".'),
                ),
              const Text('Step 1 — share the folder in Google Drive',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Open Google Drive, right-click the "Christman Site Progress" folder → Share, and add your '
                'colleagues\' emails. Choose Editor for people who add photos, Viewer for people who only look — '
                'the app automatically becomes view-only for Viewers.\n\nFolder on this PC: ${store.root.path}',
              ),
              const SizedBox(height: 14),
              const Text('Step 2 — send them these instructions', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(text, style: const TextStyle(fontSize: 12.5, height: 1.5)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Process.run('explorer', ['https://drive.google.com/drive/my-drive']),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open Google Drive'),
          ),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (ctx.mounted) showSnack(ctx, 'Instructions copied — paste them into an email or Teams');
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy instructions'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final scheme = Theme.of(context).colorScheme;
    final me = LibraryStore.user;
    final counts = store.itemsAddedBy();
    final provider = store.cloudProvider;
    final projectIds = {for (final a in _activity) if (a.projectId != null) a.projectId!: a.projectName ?? ''};
    final shown = _projectFilter == null ? _activity : _activity.where((a) => a.projectId == _projectFilter).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Team & activity'),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: () => _invite(store),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Invite teammates'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---------------- people
                SizedBox(
                  width: 380,
                  child: ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Icon(provider == null ? Icons.computer_rounded : Icons.cloud_done_rounded,
                                  color: provider == null ? scheme.onSurfaceVariant : scheme.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  provider == null
                                      ? 'Library on this computer only'
                                      : 'Shared library on $provider'
                                          '${store.readOnly ? ' · you have view-only access' : ''}',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (provider == null)
                                TextButton(
                                  onPressed: () => Navigator.push(
                                      context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                                  child: const Text('Share…'),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text('PEOPLE (${_members.length})',
                          style: TextStyle(
                              fontSize: 11.5, letterSpacing: 1, fontWeight: FontWeight.w800, color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      for (final m in _members)
                        Card(
                          child: ListTile(
                            leading: Avatar(name: m.name, id: m.id),
                            title: Text(m.id == me?.id ? '${me!.name} (you)' : m.name,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              '${_lastSeen(m.lastSeen)} · ${counts[m.id] ?? 0} files added'
                              '${m.readOnly ? ' · view only' : ''}'
                              '${m.computer.isEmpty ? '' : '\n${m.computer}'}',
                            ),
                            isThreeLine: m.computer.isNotEmpty,
                            trailing: m.id == me?.id
                                ? IconButton(tooltip: 'Change your name', onPressed: _editName, icon: const Icon(Icons.edit_outlined))
                                : null,
                          ),
                        ),
                      if (_members.length <= 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Only you so far. Share the library folder in Google Drive and your teammates will '
                            'appear here once they open it in the app.',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                // ---------------- activity
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Row(
                          children: [
                            Text('ACTIVITY',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    letterSpacing: 1,
                                    fontWeight: FontWeight.w800,
                                    color: scheme.onSurfaceVariant)),
                            const Spacer(),
                            if (projectIds.isNotEmpty)
                              DropdownButton<String?>(
                                value: _projectFilter,
                                underline: const SizedBox.shrink(),
                                items: [
                                  const DropdownMenuItem<String?>(value: null, child: Text('All projects')),
                                  for (final e in projectIds.entries)
                                    DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
                                ],
                                onChanged: (v) => setState(() => _projectFilter = v),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: shown.isEmpty
                            ? Center(
                                child: Text('No activity yet. Adding photos, notes and buildings shows up here.',
                                    style: TextStyle(color: scheme.onSurfaceVariant)))
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                                itemCount: shown.length,
                                itemBuilder: (context, i) {
                                  final a = shown[i];
                                  final newDay = i == 0 || dayKey(shown[i - 1].at) != dayKey(a.at);
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      if (newDay)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 14, bottom: 6),
                                          child: Text(_dayHeading(a.at),
                                              style: const TextStyle(fontWeight: FontWeight.w800)),
                                        ),
                                      ListTile(
                                        dense: true,
                                        leading: Avatar(name: a.userName, id: a.userId, size: 32),
                                        title: Text.rich(TextSpan(children: [
                                          TextSpan(
                                              text: a.userName,
                                              style: const TextStyle(fontWeight: FontWeight.w700)),
                                          TextSpan(text: ' ${a.text}'),
                                        ])),
                                        subtitle: Text([
                                          DateFormat('h:mm a').format(a.at),
                                          if (a.projectName != null) a.projectName!,
                                        ].join(' · ')),
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  static String _lastSeen(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 10) return 'Active now';
    if (d.inHours < 1) return 'Active ${d.inMinutes} min ago';
    if (d.inDays < 1) return 'Active ${d.inHours} h ago';
    return 'Last seen ${DateFormat('MMM d').format(t)}';
  }

  static String _dayHeading(DateTime t) {
    final now = DateTime.now();
    if (dayKey(t) == dayKey(now)) return 'Today';
    if (dayKey(t) == dayKey(now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return DateFormat('EEEE, MMM d, yyyy').format(t);
  }
}

/// Colored circle with someone's initials.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, required this.id, this.size = 40});
  final String name;
  final String id;
  final double size;

  static const _colors = [
    Color(0xFFAE734B), Color(0xFF2F6FB0), Color(0xFF2E8B57), Color(0xFF7B4FB8),
    Color(0xFFC0392B), Color(0xFFB8860B), Color(0xFF00838F), Color(0xFFAD1457),
  ];

  @override
  Widget build(BuildContext context) {
    final c = _colors[id.codeUnits.fold<int>(0, (s, x) => s + x) % _colors.length];
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: c,
      child: Text(initialsOf(name),
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.38)),
    );
  }
}
