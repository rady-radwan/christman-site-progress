import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../dialogs/project_dialog.dart';
import '../library_store.dart';
import '../models.dart';
import '../util.dart';
import '../widgets/media_tile.dart';
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

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Image.asset('assets/logo.png', width: 30, height: 30),
            const SizedBox(width: 12),
            const Text('Christman Site Progress',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: projects.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _newProject(context),
              icon: const Icon(Icons.add),
              label: const Text('New project'),
            ),
      body: projects.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flight_takeoff_rounded, size: 64, color: scheme.primary),
                  const SizedBox(height: 16),
                  Text('Track every site, week by week',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text('Create a project, add its buildings, then drop in each week\'s drone captures.',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => _newProject(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Create your first project'),
                  ),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (context, c) {
                final cols = (c.maxWidth / 360).floor().clamp(1, 6);
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.15,
                  ),
                  itemCount: projects.length,
                  itemBuilder: (context, i) => _ProjectCard(project: projects[i]),
                );
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
        name: project.name,
        location: project.location,
        description: project.description,
        editing: true);
    if (r == null) return;
    await store.updateProject(project,
        name: r.name, location: r.location, description: r.description);
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
    final cover = project.coverPhoto;
    final last = project.lastCaptureDate;
    return Card(
      child: InkWell(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => ProjectScreen(projectId: project.id))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: cover != null
                  ? MediaThumb(item: cover, decodeWidth: 720)
                  : Container(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(Icons.apartment_rounded, size: 56, color: scheme.onSurfaceVariant),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 4, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(project.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        if (project.location.isNotEmpty)
                          Text(project.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Text(
                          '${project.buildings.length} building${project.buildings.length == 1 ? '' : 's'} · '
                          '${project.photoCount} photos · ${project.videoCount} videos',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                        Text(
                          last == null ? 'No captures yet' : 'Last capture ${prettyDay(last)}',
                          style: TextStyle(fontSize: 12, color: scheme.primary),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') _edit(context);
                      if (v == 'delete') _delete(context);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit project')),
                      PopupMenuItem(value: 'delete', child: Text('Delete project')),
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
