import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../library_store.dart';
import '../models.dart';
import '../util.dart';

const mediaTypeGroup = XTypeGroup(
  label: 'Photos and videos',
  extensions: [
    'jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif', 'tif', 'tiff', 'heic', 'dng',
    'mp4', 'mov', 'm4v', 'avi', 'mkv', 'wmv', 'webm', 'mts', 'm2ts', '3gp',
  ],
  mimeTypes: ['image/*', 'video/*'],
  uniformTypeIdentifiers: ['public.image', 'public.movie'],
);

class AddMediaResult {
  AddMediaResult(this.day, this.buildingId, this.imported);
  final DateTime day;
  final String buildingId;
  final int imported;
}

Future<AddMediaResult?> showAddMediaDialog(
  BuildContext context, {
  required Project project,
  String? buildingId,
  DateTime? day,
  List<String> initialPaths = const [],
}) {
  return showDialog<AddMediaResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AddMediaDialog(
      project: project,
      buildingId: buildingId,
      day: day,
      initialPaths: initialPaths,
    ),
  );
}

class _AddMediaDialog extends StatefulWidget {
  const _AddMediaDialog({
    required this.project,
    required this.buildingId,
    required this.day,
    required this.initialPaths,
  });

  final Project project;
  final String? buildingId;
  final DateTime? day;
  final List<String> initialPaths;

  @override
  State<_AddMediaDialog> createState() => _AddMediaDialogState();
}

class _AddMediaDialogState extends State<_AddMediaDialog> {
  late String _buildingId;
  late DateTime _day;
  final _note = TextEditingController();
  final List<String> _paths = [];
  bool _dragging = false;
  bool _busy = false;
  int _done = 0;
  String _current = '';

  @override
  void initState() {
    super.initState();
    _buildingId = widget.buildingId ?? widget.project.buildings.first.id;
    final now = DateTime.now();
    _day = widget.day ?? DateTime(now.year, now.month, now.day);
    _addPaths(widget.initialPaths);
  }

  void _addPaths(Iterable<String> paths) {
    for (final path in paths) {
      if (mediaTypeForExtension(p.extension(path)) == null) continue;
      if (!_paths.contains(path)) _paths.add(path);
    }
  }

  Future<void> _browse() async {
    final files = await openFiles(acceptedTypeGroups: [mediaTypeGroup]);
    setState(() => _addPaths(files.map((f) => f.path)));
  }

  Future<void> _import() async {
    if (_paths.isEmpty) return;
    final store = context.read<LibraryStore>();
    setState(() => _busy = true);
    final result = await store.importMedia(
      widget.project,
      _buildingId,
      _day,
      List.of(_paths),
      note: _note.text,
      onProgress: (done, total, current) {
        if (mounted) setState(() {
          _done = done;
          _current = current;
        });
      },
    );
    if (!mounted) return;
    if (result.skipped.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Imported ${result.imported} of ${_paths.length}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Text('These files were skipped:\n\n${result.skipped.join('\n')}'),
            ),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      if (!mounted) return;
    }
    Navigator.pop(context, AddMediaResult(_day, _buildingId, result.imported));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final photos = _paths.where((x) => mediaTypeForExtension(p.extension(x)) == MediaType.photo).length;
    final videos = _paths.length - photos;

    return AlertDialog(
      title: const Text('Add photos & videos'),
      content: SizedBox(
        width: 560,
        child: _busy
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Copying originals into the library… ($_done of ${_paths.length})'),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: _paths.isEmpty ? null : _done / _paths.length),
                  const SizedBox(height: 8),
                  Text(_current,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _buildingId,
                          decoration: const InputDecoration(
                              labelText: 'Building / area', border: OutlineInputBorder()),
                          items: [
                            for (final b in widget.project.buildings)
                              DropdownMenuItem(value: b.id, child: Text(b.name)),
                          ],
                          onChanged: (v) => setState(() => _buildingId = v ?? _buildingId),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final d = await pickDay(context, _day);
                            if (d != null) setState(() => _day = d);
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Capture date',
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.calendar_month_outlined),
                            ),
                            child: Text(prettyDay(_day)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _note,
                    decoration: const InputDecoration(
                      labelText: 'Note for this date (optional)',
                      hintText: 'e.g. Level 3 deck poured, curtain wall started on east side',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropTarget(
                    onDragEntered: (_) => setState(() => _dragging = true),
                    onDragExited: (_) => setState(() => _dragging = false),
                    onDragDone: (d) => setState(() {
                      _dragging = false;
                      _addPaths(d.files.map((f) => f.path));
                    }),
                    child: InkWell(
                      onTap: _browse,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 120,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: _dragging ? scheme.primary.withValues(alpha: 0.12) : null,
                          border: Border.all(
                            color: _dragging ? scheme.primary : scheme.outlineVariant,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.cloud_upload_outlined, size: 36, color: scheme.primary),
                            const SizedBox(height: 6),
                            Text(isDesktop
                                ? 'Drop drone photos/videos here, or click to browse'
                                : 'Tap to choose photos/videos'),
                            Text('Files are copied in their original quality',
                                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_paths.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text('$photos photo${photos == 1 ? '' : 's'}, $videos video${videos == 1 ? '' : 's'}',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        TextButton(
                            onPressed: () => setState(_paths.clear), child: const Text('Clear')),
                      ],
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _paths.length,
                        itemBuilder: (context, i) {
                          final path = _paths[i];
                          final isVideo =
                              mediaTypeForExtension(p.extension(path)) == MediaType.video;
                          return ListTile(
                            dense: true,
                            leading: Icon(isVideo ? Icons.videocam_outlined : Icons.photo_outlined),
                            title: Text(p.basename(path),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setState(() => _paths.removeAt(i)),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
      ),
      actions: _busy
          ? null
          : [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton.icon(
                onPressed: _paths.isEmpty ? null : _import,
                icon: const Icon(Icons.download_done_rounded),
                label: Text('Add ${_paths.length} file${_paths.length == 1 ? '' : 's'}'),
              ),
            ],
    );
  }
}

/// Move selected items to another building and/or date.
Future<(String, DateTime)?> showMoveDialog(
    BuildContext context, Project project, String buildingId, DateTime day) {
  var b = buildingId;
  var d = day;
  return showDialog<(String, DateTime)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Move to…'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: b,
                decoration:
                    const InputDecoration(labelText: 'Building / area', border: OutlineInputBorder()),
                items: [
                  for (final x in project.buildings)
                    DropdownMenuItem(value: x.id, child: Text(x.name)),
                ],
                onChanged: (v) => setS(() => b = v ?? b),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await pickDay(ctx, d);
                  if (picked != null) setS(() => d = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Capture date',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_month_outlined),
                  ),
                  child: Text(prettyDay(d)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, (b, d)), child: const Text('Move')),
        ],
      ),
    ),
  );
}
