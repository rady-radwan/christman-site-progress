import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../dialogs/add_media_dialog.dart';
import '../dialogs/project_dialog.dart';
import '../library_store.dart';
import '../models.dart';
import '../util.dart';
import '../widgets/media_tile.dart';
import '../widgets/timeline_bar.dart';
import 'compare_screen.dart';
import 'photo_viewer.dart';
import 'video_player_screen.dart';

class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key, required this.projectId});
  final String projectId;

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  String? _buildingId; // null = all buildings
  String? _viewId; // null = all views of the building
  DateTime? _day;
  MediaType _type = MediaType.photo;
  final Set<String> _selected = {};
  bool _dropHover = false;
  Timer? _player;
  final _focus = FocusNode();

  LibraryStore get _store => context.read<LibraryStore>();

  @override
  void dispose() {
    _player?.cancel();
    _focus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ navigation

  List<DateTime> _dates(Project pr) => pr.datesFor(_buildingId, viewId: _viewId);

  void _selectBuilding(String? id, {String? viewId}) => setState(() {
        _buildingId = id;
        _viewId = id == null ? null : viewId;
        _selected.clear();
      });

  DateTime? _effectiveDay(List<DateTime> dates) {
    if (dates.isEmpty) return null;
    final d = _day;
    if (d != null && dates.any((x) => dayKey(x) == dayKey(d))) return d;
    return dates.last;
  }

  void _select(DateTime d) => setState(() {
        _day = d;
        _selected.clear();
      });

  void _step(Project pr, int delta) {
    final dates = _dates(pr);
    final cur = _effectiveDay(dates);
    if (cur == null) return;
    final i = dates.indexWhere((x) => dayKey(x) == dayKey(cur));
    final j = (i + delta).clamp(0, dates.length - 1);
    if (j != i) _select(dates[j]);
  }

  void _togglePlay(Project pr) {
    if (_player != null) {
      setState(() {
        _player?.cancel();
        _player = null;
      });
      return;
    }
    final dates = _dates(pr);
    if (dates.length < 2) return;
    final cur = _effectiveDay(dates);
    if (cur != null && dayKey(cur) == dayKey(dates.last)) _select(dates.first);
    setState(() {
      _player = Timer.periodic(const Duration(milliseconds: 2500), (t) {
        final ds = _dates(pr);
        final c = _effectiveDay(ds);
        final i = c == null ? -1 : ds.indexWhere((x) => dayKey(x) == dayKey(c));
        if (i < 0 || i >= ds.length - 1) {
          t.cancel();
          if (mounted) setState(() => _player = null);
        } else {
          _select(ds[i + 1]);
        }
      });
    });
  }

  // ------------------------------------------------------------ actions

  Future<void> _addMedia(Project pr, {List<String> paths = const []}) async {
    final r = await showAddMediaDialog(
      context,
      project: pr,
      buildingId: _buildingId,
      viewId: _viewId,
      initialPaths: paths,
    );
    if (r == null || !mounted) return;
    setState(() {
      _day = r.day;
      if (_buildingId != null && _buildingId != r.buildingId) _buildingId = r.buildingId;
      if (_viewId != null && _viewId != r.viewId) _viewId = r.viewId;
    });
    if (r.imported > 0) showSnack(context, 'Added ${r.imported} file${r.imported == 1 ? '' : 's'} to ${prettyDay(r.day)}');
  }

  Future<void> _addBuilding(Project pr) async {
    final r = await showBuildingDialog(context);
    if (r == null || r.name.trim().isEmpty) return;
    final b = await _store.addBuilding(pr, r.name, viewNames: r.views);
    _selectBuilding(b.id);
  }

  Future<void> _addView(Project pr, Building b) async {
    final name = await promptText(context,
        title: 'New camera view for ${b.name}',
        label: 'View name (e.g. North elevation, Roof)',
        confirmLabel: 'Add');
    if (name == null || name.trim().isEmpty) return;
    final v = await _store.addView(pr, b, name);
    _selectBuilding(b.id, viewId: v.id);
  }

  Future<void> _renameView(Project pr, BuildingView v) async {
    final name = await promptText(context, title: 'Rename view', initial: v.name);
    if (name == null || name.trim().isEmpty) return;
    await _store.renameView(pr, v, name);
  }

  Future<void> _deleteView(Project pr, Building b, BuildingView v) async {
    if (b.views.length == 1) {
      showSnack(context, 'A building needs at least one camera view.');
      return;
    }
    final count = pr.captures
        .where((c) => c.buildingId == b.id && c.viewId == v.id)
        .fold<int>(0, (s, c) => s + c.items.length);
    final ok = await confirm(context,
        title: 'Delete view "${v.name}"?',
        message: 'This deletes the view and its $count stored photos/videos from the library.');
    if (!ok) return;
    await _store.deleteView(pr, b, v);
    if (_viewId == v.id) setState(() => _viewId = null);
  }

  Future<void> _renameBuilding(Project pr, Building b) async {
    final name = await promptText(context, title: 'Rename building', initial: b.name);
    if (name == null || name.trim().isEmpty) return;
    await _store.renameBuilding(pr, b, name);
  }

  Future<void> _deleteBuilding(Project pr, Building b) async {
    if (pr.buildings.length == 1) {
      showSnack(context, 'A project needs at least one building or area.');
      return;
    }
    final count = pr.captures.where((c) => c.buildingId == b.id).fold<int>(0, (s, c) => s + c.items.length);
    final ok = await confirm(context,
        title: 'Delete "${b.name}"?',
        message: 'This deletes the building and its $count stored photos/videos from the library.');
    if (!ok) return;
    await _store.deleteBuilding(pr, b);
    if (_buildingId == b.id) _selectBuilding(null);
  }

  List<MediaItem> _selectedItems(Project pr) => [
        for (final c in pr.captures)
          for (final m in c.items)
            if (_selected.contains(m.id)) m
      ];

  Future<void> _export(List<MediaItem> items, {String prefix = ''}) async {
    if (items.isEmpty) return;
    final dir = await getDirectoryPath(confirmButtonText: 'Export here');
    if (dir == null || !mounted) return;
    final n = await _store.exportItems(items, dir, prefix: prefix);
    if (!mounted) return;
    showSnack(context, 'Exported $n original file${n == 1 ? '' : 's'}');
    if (isDesktop) openInFileManager(dir);
  }

  Future<void> _deleteSelected(Project pr) async {
    final items = _selectedItems(pr);
    final ok = await confirm(context,
        title: 'Delete ${items.length} item${items.length == 1 ? '' : 's'}?',
        message: 'They will be removed from the library permanently.');
    if (!ok) return;
    await _store.deleteMedia(pr, items);
    setState(_selected.clear);
  }

  Future<void> _moveSelected(Project pr, DateTime day) async {
    final items = _selectedItems(pr);
    if (items.isEmpty) return;
    final from = _store.captureContaining(pr, items.first);
    final bId = from?.buildingId ?? pr.buildings.first.id;
    final vId = from?.viewId ?? pr.buildings.first.views.first.id;
    final r = await showMoveDialog(context, pr, bId, vId, day);
    if (r == null) return;
    await _store.moveMedia(pr, items, buildingId: r.$1, viewId: r.$2, day: r.$3);
    setState(() {
      _selected.clear();
      _day = r.$3;
    });
  }

  Future<void> _changeDate(Project pr, DateTime day) async {
    final d = await pickDay(context, day);
    if (d == null || dayKey(d) == dayKey(day)) return;
    await _store.changeDate(pr, day, d, _buildingId, viewId: _viewId);
    setState(() => _day = d);
  }

  Future<void> _deleteDay(Project pr, DateTime day) async {
    final caps = pr.capturesOn(day, _buildingId, viewId: _viewId);
    final n = caps.fold<int>(0, (s, c) => s + c.items.length);
    final where = _scopeLabel(pr);
    final ok = await confirm(context,
        title: 'Delete ${prettyDay(day)}?',
        message: 'This deletes all $n photos/videos captured on this date ($where) from the library.');
    if (!ok) return;
    await _store.deleteDay(pr, day, _buildingId, viewId: _viewId);
    setState(() => _day = null);
  }

  String _scopeLabel(Project pr) {
    if (_buildingId == null) return 'all buildings';
    final b = pr.buildingById(_buildingId!);
    final v = b?.viewById(_viewId);
    return [b?.name ?? '', if (v != null) v.name].join(' · ');
  }

  Future<void> _editNote(Project pr, Capture c) async {
    final text = await promptText(context,
        title: 'Note — ${pr.labelFor(c)}, ${prettyDay(c.date)}',
        initial: c.note,
        label: 'What happened on site',
        maxLines: 4);
    if (text == null) return;
    await _store.setNote(pr, c, text);
  }

  void _openPhoto(Project pr, List<DateTime> dates, DateTime day, MediaItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoViewer(
          project: pr,
          buildingId: _buildingId,
          viewId: _viewId,
          dates: dates,
          startDay: day,
          startItemId: item.id,
        ),
      ),
    ).then((value) {
      if (value is DateTime && mounted) setState(() => _day = value);
    });
  }

  void _playVideos(Project pr, List<MediaItem> items, int start, List<String> labels) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          files: items.map((m) => _store.fileFor(m).path).toList(),
          labels: labels,
          startIndex: start,
        ),
      ),
    );
  }

  void _playAllWeeks(Project pr) {
    final items = <MediaItem>[];
    final labels = <String>[];
    for (final d in pr.datesFor(_buildingId, viewId: _viewId, type: MediaType.video)) {
      for (final c in pr.capturesOn(d, _buildingId, viewId: _viewId)) {
        for (final m in c.videos) {
          items.add(m);
          labels.add('Week ${pr.weekNumber(d)} · ${prettyDay(d)} · ${pr.labelFor(c)}');
        }
      }
    }
    if (items.isEmpty) return;
    _playVideos(pr, items, 0, labels);
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final pr = store.projectById(widget.projectId);
    if (pr == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Project not found')));
    }
    if (_buildingId != null && pr.buildingById(_buildingId!) == null) {
      _buildingId = null;
      _viewId = null;
    }
    if (_viewId != null && pr.buildingById(_buildingId ?? '')?.viewById(_viewId) == null) _viewId = null;

    final dates = _dates(pr);
    final day = _effectiveDay(dates);
    final selecting = _selected.isNotEmpty;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _step(pr, -1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _step(pr, 1),
        const SingleActivator(LogicalKeyboardKey.space): () => _togglePlay(pr),
        const SingleActivator(LogicalKeyboardKey.escape): () => setState(_selected.clear),
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pr.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (pr.location.isNotEmpty)
                  Text(pr.location, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
              ],
            ),
            actions: [
              if (day != null && dates.length > 1)
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CompareScreen(
                        project: pr,
                        buildingId: _buildingId,
                        viewId: _viewId,
                        dates: dates,
                        after: day,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.compare_rounded),
                  label: const Text('Compare Progress'),
                ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _addMedia(pr),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Add photos & videos'),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (v) {
                  if (v == 'folder') openInFileManager(store.projectDir(pr).path);
                  if (v == 'exportDay' && day != null) {
                    _export(
                      [
                        ...pr.mediaOn(day, _buildingId, MediaType.photo, viewId: _viewId),
                        ...pr.mediaOn(day, _buildingId, MediaType.video, viewId: _viewId),
                      ],
                      prefix: '${dayKey(day)}_',
                    );
                  }
                  if (v == 'date' && day != null) _changeDate(pr, day);
                  if (v == 'deleteDay' && day != null) _deleteDay(pr, day);
                },
                itemBuilder: (_) => [
                  if (day != null) ...[
                    const PopupMenuItem(value: 'exportDay', child: Text('Export this date (originals)…')),
                    const PopupMenuItem(value: 'date', child: Text('Change this capture date…')),
                    const PopupMenuItem(value: 'deleteDay', child: Text('Delete this capture date…')),
                    const PopupMenuDivider(),
                  ],
                  if (Platform.isWindows)
                    const PopupMenuItem(value: 'folder', child: Text('Open project folder')),
                ],
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: DropTarget(
            onDragEntered: (_) => setState(() => _dropHover = true),
            onDragExited: (_) => setState(() => _dropHover = false),
            onDragDone: (d) {
              setState(() => _dropHover = false);
              _addMedia(pr, paths: d.files.map((f) => f.path).toList());
            },
            child: Stack(
              children: [
                LayoutBuilder(builder: (context, c) {
                  final wide = c.maxWidth >= 760;
                  final content = Column(
                    children: [
                      if (!wide) _buildingChips(pr),
                      _header(pr, day, selecting),
                      const Divider(),
                      Expanded(child: _content(pr, dates, day, selecting)),
                    ],
                  );
                  return Row(
                    children: [
                      if (wide) _sidebar(pr),
                      if (wide) const VerticalDivider(width: 1),
                      Expanded(child: content),
                    ],
                  );
                }),
                if (_dropHover)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                        alignment: Alignment.center,
                        child: const Card(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Drop to add these files', style: TextStyle(fontSize: 18)),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          bottomNavigationBar: TimelineBar(
            project: pr,
            dates: dates,
            selected: day,
            onSelect: _select,
            playing: _player != null,
            onTogglePlay: () => _togglePlay(pr),
          ),
        ),
      ),
    );
  }

  int _countFor(Project pr, {String? buildingId, String? viewId}) => pr.captures
      .where((c) =>
          (buildingId == null || c.buildingId == buildingId) &&
          (viewId == null || c.viewId == viewId))
      .fold(0, (s, c) => s + c.items.length);

  Widget _sidebar(Project pr) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Text('BUILDINGS & VIEWS',
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant)),
                const Spacer(),
                IconButton(
                  tooltip: 'Add building / area',
                  iconSize: 20,
                  onPressed: () => _addBuilding(pr),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          _BuildingTile(
            label: 'All buildings',
            icon: Icons.layers_outlined,
            count: _countFor(pr),
            selected: _buildingId == null,
            onTap: () => _selectBuilding(null),
          ),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: pr.buildings.length,
              onReorder: (a, b) => _store.moveBuilding(pr, a, b > a ? b - 1 : b),
              itemBuilder: (context, i) {
                final b = pr.buildings[i];
                final open = _buildingId == b.id;
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(b.id),
                  index: i,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _BuildingTile(
                        label: b.name,
                        icon: Icons.apartment_outlined,
                        count: _countFor(pr, buildingId: b.id),
                        selected: open && _viewId == null,
                        expanded: open,
                        onTap: () => _selectBuilding(b.id),
                        menu: PopupMenuButton<String>(
                          iconSize: 18,
                          onSelected: (v) {
                            if (v == 'view') _addView(pr, b);
                            if (v == 'rename') _renameBuilding(pr, b);
                            if (v == 'delete') _deleteBuilding(pr, b);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'view', child: Text('Add camera view')),
                            PopupMenuItem(value: 'rename', child: Text('Rename building')),
                            PopupMenuItem(value: 'delete', child: Text('Delete building')),
                          ],
                        ),
                      ),
                      if (open) ...[
                        for (final v in b.views)
                          _BuildingTile(
                            label: v.name,
                            icon: Icons.photo_camera_outlined,
                            indent: true,
                            count: _countFor(pr, buildingId: b.id, viewId: v.id),
                            selected: _viewId == v.id,
                            onTap: () => _selectBuilding(b.id, viewId: v.id),
                            menu: PopupMenuButton<String>(
                              iconSize: 18,
                              onSelected: (x) {
                                if (x == 'rename') _renameView(pr, v);
                                if (x == 'delete') _deleteView(pr, b, v);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'rename', child: Text('Rename view')),
                                PopupMenuItem(value: 'delete', child: Text('Delete view')),
                              ],
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(36, 0, 8, 6),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => _addView(pr, b),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Add view'),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildingChips(Project pr) {
    final b = _buildingId == null ? null : pr.buildingById(_buildingId!);
    Widget row(List<Widget> children) => SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final c in children) Padding(padding: const EdgeInsets.only(right: 8), child: c),
            ],
          ),
        );
    return Column(
      children: [
        row([
          ChoiceChip(
            label: const Text('All'),
            selected: _buildingId == null,
            onSelected: (_) => _selectBuilding(null),
          ),
          for (final x in pr.buildings)
            ChoiceChip(
              label: Text(x.name),
              selected: _buildingId == x.id,
              onSelected: (_) => _selectBuilding(x.id),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('Building'),
            onPressed: () => _addBuilding(pr),
          ),
        ]),
        if (b != null)
          row([
            ChoiceChip(
              label: const Text('All views'),
              selected: _viewId == null,
              onSelected: (_) => _selectBuilding(b.id),
            ),
            for (final v in b.views)
              ChoiceChip(
                avatar: const Icon(Icons.photo_camera_outlined, size: 16),
                label: Text(v.name),
                selected: _viewId == v.id,
                onSelected: (_) => _selectBuilding(b.id, viewId: v.id),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('View'),
              onPressed: () => _addView(pr, b),
            ),
          ]),
      ],
    );
  }

  Widget _header(Project pr, DateTime? day, bool selecting) {
    final scheme = Theme.of(context).colorScheme;
    final photos = day == null ? 0 : pr.mediaOn(day, _buildingId, MediaType.photo, viewId: _viewId).length;
    final videos = day == null ? 0 : pr.mediaOn(day, _buildingId, MediaType.video, viewId: _viewId).length;
    final caps = day == null ? <Capture>[] : pr.capturesOn(day, _buildingId, viewId: _viewId);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: day == null
                    ? Text('No captures yet', style: Theme.of(context).textTheme.titleLarge)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('WEEK ${pr.weekNumber(day)}  ·  ${_scopeLabel(pr).toUpperCase()}',
                              style: TextStyle(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                  fontSize: 12)),
                          Text(prettyDay(day), style: Theme.of(context).textTheme.titleLarge),
                        ],
                      ),
              ),
              if (selecting) ...[
                Text('${_selected.length} selected'),
                const SizedBox(width: 8),
                IconButton(
                    tooltip: 'Export originals',
                    onPressed: () => _export(_selectedItems(pr)),
                    icon: const Icon(Icons.file_download_outlined)),
                if (day != null)
                  IconButton(
                      tooltip: 'Move to another date or building',
                      onPressed: () => _moveSelected(pr, day),
                      icon: const Icon(Icons.drive_file_move_outlined)),
                IconButton(
                    tooltip: 'Delete',
                    onPressed: () => _deleteSelected(pr),
                    icon: const Icon(Icons.delete_outline)),
                IconButton(
                    tooltip: 'Clear selection',
                    onPressed: () => setState(_selected.clear),
                    icon: const Icon(Icons.close)),
                const SizedBox(width: 8),
              ],
              SegmentedButton<MediaType>(
                segments: [
                  ButtonSegment(
                      value: MediaType.photo,
                      icon: const Icon(Icons.photo_outlined),
                      label: Text('Photos ($photos)')),
                  ButtonSegment(
                      value: MediaType.video,
                      icon: const Icon(Icons.videocam_outlined),
                      label: Text('Videos ($videos)')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() {
                  _type = s.first;
                  _selected.clear();
                }),
              ),
            ],
          ),
          if (caps.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final c in caps)
                  ActionChip(
                    avatar: Icon(
                        c.note.isEmpty ? Icons.edit_note_rounded : Icons.sticky_note_2_outlined,
                        size: 18),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Text(
                        _viewId == null
                            ? '${pr.labelFor(c)}: ${c.note.isEmpty ? 'add note' : c.note}'
                            : (c.note.isEmpty ? 'Add a note for this date' : c.note),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    onPressed: () => _editNote(pr, c),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _content(Project pr, List<DateTime> dates, DateTime? day, bool selecting) {
    final scheme = Theme.of(context).colorScheme;
    if (day == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_photo_alternate_outlined, size: 56, color: scheme.primary),
            const SizedBox(height: 12),
            const Text('Add this week\'s drone photos and videos to start the timeline.'),
            const SizedBox(height: 4),
            Text('Tip: you can drag files straight onto this window, and back-date older captures.',
                style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _addMedia(pr),
              icon: const Icon(Icons.add),
              label: const Text('Add photos & videos'),
            ),
          ],
        ),
      );
    }

    final caps = pr.capturesOn(day, _buildingId, viewId: _viewId);
    final groups = <(String, List<MediaItem>)>[];
    for (final c in caps) {
      final items = c.items.where((m) => m.type == _type).toList();
      if (items.isNotEmpty) groups.add((pr.labelFor(c), items));
    }

    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_type == MediaType.photo ? 'No photos on this date.' : 'No videos on this date.',
                style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _addMedia(pr),
              icon: const Icon(Icons.add),
              label: const Text('Add files'),
            ),
          ],
        ),
      );
    }

    final allOfType = [for (final g in groups) ...g.$2];
    final showGroupTitles = _viewId == null;

    return CustomScrollView(
      slivers: [
        if (_type == MediaType.video)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _playVideos(
                        pr, allOfType, 0, List.filled(allOfType.length, prettyDay(day))),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play this week'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _playAllWeeks(pr),
                    icon: const Icon(Icons.playlist_play_rounded),
                    label: const Text('Play all weeks in order'),
                  ),
                ],
              ),
            ),
          ),
        for (final g in groups) ...[
          if (showGroupTitles)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Text(g.$1,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 340,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 4 / 3,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final m = g.$2[i];
                  return MediaTile(
                    key: ValueKey(m.id),
                    item: m,
                    selecting: selecting,
                    selected: _selected.contains(m.id),
                    onToggleSelect: () => setState(() {
                      if (!_selected.remove(m.id)) _selected.add(m.id);
                    }),
                    onOpen: () {
                      if (m.type == MediaType.video) {
                        final idx = allOfType.indexOf(m);
                        _playVideos(pr, allOfType, idx < 0 ? 0 : idx,
                            List.filled(allOfType.length, prettyDay(day)));
                      } else {
                        _openPhoto(pr, dates, day, m);
                      }
                    },
                  );
                },
                childCount: g.$2.length,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _BuildingTile extends StatelessWidget {
  const _BuildingTile({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.onTap,
    this.menu,
    this.indent = false,
    this.expanded = false,
  });

  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Widget? menu;
  final bool indent;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highlight = selected || expanded;
    return Padding(
      padding: EdgeInsets.fromLTRB(indent ? 30 : 8, indent ? 0 : 2, 8, indent ? 0 : 2),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.14)
            : expanded
                ? scheme.primary.withValues(alpha: 0.06)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, indent ? 4 : 8, menu == null ? 12 : 0, indent ? 4 : 8),
            child: Row(
              children: [
                Icon(icon,
                    size: indent ? 17 : 20,
                    color: highlight ? scheme.primary : scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: indent ? 13 : 14,
                          fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                          color: highlight ? scheme.primary : null)),
                ),
                Text('$count', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                if (menu != null) menu!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
