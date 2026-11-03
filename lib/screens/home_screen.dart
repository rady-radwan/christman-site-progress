import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../dialogs/cover_dialog.dart';
import '../dialogs/project_dialog.dart';
import '../library_store.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/project_cover.dart';
import 'project_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _newProject(BuildContext context) async {
    final store = context.read<LibraryStore>();
    final r = await showProjectDialog(context);
    if (r == null) return;
    final pr = await store.createProject(
      name: r.name,
      location: r.location,
      description: r.description,
      buildingNames: r.buildings,
      viewNames: r.views,
    );
    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectScreen(projectId: pr.id)));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final projects = [...store.projects]
      ..sort((a, b) => (b.lastCaptureDate ?? b.createdAt).compareTo(a.lastCaptureDate ?? a.createdAt));
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final photos = projects.fold<int>(0, (s, p) => s + p.photoCount);
    final videos = projects.fold<int>(0, (s, p) => s + p.videoCount);
    final buildings = projects.fold<int>(0, (s, p) => s + p.buildings.length);

    return Scaffold(
      floatingActionButton: projects.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _newProject(context),
              icon: const Icon(Icons.add),
              label: const Text('New project'),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---------------- header
          Container(
            padding: const EdgeInsets.fromLTRB(28, 20, 20, 20),
            decoration: BoxDecoration(
              color: context.palette.header,
              border: Border(bottom: BorderSide(color: Theme.of(context).dividerTheme.color ?? Colors.black12)),
            ),
            child: Row(
              children: [
                // Christman wordmark + the app's own mark
                Image.asset(
                  dark ? 'assets/christman_logo_light.png' : 'assets/christman_logo_dark.png',
                  height: 50,
                  filterQuality: FilterQuality.high,
                ),
                Container(
                  width: 2,
                  height: 54,
                  margin: const EdgeInsets.symmetric(horizontal: 22),
                  color: scheme.primary,
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset('assets/logo.png', width: 56, height: 56, filterQuality: FilterQuality.high),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SITE PROGRESS',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.5,
                            color: dark ? Colors.white : brandSlateText,
                          )),
                      Text(
                        projects.isEmpty
                            ? 'Drone progress for every site, capture by capture'
                            : '${projects.length} project${projects.length == 1 ? '' : 's'} · $buildings buildings · '
                                '$photos photos · $videos videos',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const _SyncChip(),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () =>
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                ),
              ],
            ),
          ),
          // ---------------- projects
          Expanded(
            child: projects.isEmpty
                ? _Empty(onCreate: () => _newProject(context))
                : LayoutBuilder(
                    builder: (context, c) {
                      final cols = (c.maxWidth / 420).floor().clamp(1, 5);
                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 110),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          mainAxisSpacing: 20,
                          crossAxisSpacing: 20,
                          mainAxisExtent: 400,
                        ),
                        itemCount: projects.length,
                        itemBuilder: (context, i) => _ProjectCard(project: projects[i]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

const brandSlateText = Color(0xFF1E2A33);

class _Empty extends StatelessWidget {
  const _Empty({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flight_takeoff_rounded, size: 64, color: scheme.primary),
          const SizedBox(height: 16),
          Text('Track every site, week by week', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('Create a project, add its buildings, then drop in each week\'s drone captures.',
              style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            children: [
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Create your first project'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                icon: const Icon(Icons.cloud_outlined),
                label: const Text('Open a shared library (Google Drive)'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shows where the library lives and when it last synced; click for settings.
class _SyncChip extends StatelessWidget {
  const _SyncChip();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final provider = store.cloudProvider;
    final scheme = Theme.of(context).colorScheme;
    final when = store.lastSynced == null ? '' : ' · ${DateFormat('h:mm a').format(store.lastSynced!)}';
    return Tooltip(
      message: provider == null
          ? 'Your library is on this computer only. Click to share it through Google Drive.'
          : 'Shared library in $provider. Changes from others appear automatically.\n${store.root.path}',
      child: ActionChip(
        avatar: Icon(provider == null ? Icons.computer_rounded : Icons.cloud_done_rounded,
            size: 18, color: provider == null ? scheme.onSurfaceVariant : scheme.primary),
        label: Text(provider == null ? 'On this computer' : '$provider$when'),
        onPressed: () async {
          if (provider != null) {
            final changed = await store.refreshFromDisk();
            if (context.mounted) {
              showSnack(context, changed ? 'Updated with the latest changes from $provider' : 'Up to date');
            }
          } else {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
          }
        },
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});
  final Project project;

  Future<void> _edit(BuildContext context) async {
    final store = context.read<LibraryStore>();
    final r = await showProjectDialog(context,
        name: project.name, location: project.location, description: project.description, editing: true);
    if (r == null) return;
    await store.updateProject(project, name: r.name, location: r.location, description: r.description);
  }

  Future<void> _delete(BuildContext context) async {
    final store = context.read<LibraryStore>();
    final ok = await confirm(
      context,
      title: 'Delete "${project.name}"?',
      message:
          'This permanently deletes the project and all ${project.photoCount} photos and ${project.videoCount} videos stored for it in the library. Your original files elsewhere are not touched.',
    );
    if (ok) await store.deleteProject(project);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = project.lastCaptureDate;
    final first = project.firstCaptureDate;
    final range = first == null
        ? 'No captures yet'
        : dayKey(first) == dayKey(last!)
            ? prettyDay(first)
            : '${DateFormat('MMM d, yyyy').format(first)} – ${DateFormat('MMM d, yyyy').format(last)}';

    return Card(
      child: InkWell(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => ProjectScreen(projectId: project.id))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProjectCover(project: project),
                  if (last != null)
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                            color: const Color(0xAA000000), borderRadius: BorderRadius.circular(20)),
                        child: Text('Last capture · ${DateFormat('MMM d, yyyy').format(last)}',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Material(
                      color: const Color(0x88000000),
                      shape: const CircleBorder(),
                      child: PopupMenuButton<String>(
                        iconColor: Colors.white,
                        tooltip: 'Project options',
                        onSelected: (v) {
                          if (v == 'edit') _edit(context);
                          if (v == 'cover') showCoverDialog(context, project);
                          if (v == 'delete') _delete(context);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'cover', child: Text('Change picture or icon…')),
                          PopupMenuItem(value: 'edit', child: Text('Edit name, location, description…')),
                          PopupMenuDivider(),
                          PopupMenuItem(value: 'delete', child: Text('Delete project')),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: project.location.isEmpty ? () => _edit(context) : null,
                    child: Row(
                      children: [
                        Icon(Icons.place_outlined, size: 16, color: scheme.primary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            project.location.isEmpty ? 'Add location' : project.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: project.location.isEmpty ? scheme.primary : scheme.onSurfaceVariant,
                              fontStyle: project.location.isEmpty ? FontStyle.italic : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _Stat(icon: Icons.apartment_rounded, value: project.buildings.length, label: 'Buildings'),
                      _Stat(icon: Icons.event_available_rounded, value: project.captureDateCount, label: 'Captures'),
                      _Stat(icon: Icons.photo_outlined, value: project.photoCount, label: 'Photos'),
                      _Stat(icon: Icons.videocam_outlined, value: project.videoCount, label: 'Videos'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.date_range_rounded, size: 15, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(range,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                      ),
                      Text(prettySize(project.totalBytes),
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
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

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label});
  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 15, color: scheme.primary),
                const SizedBox(width: 4),
                Text('$value', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ],
            ),
            Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
