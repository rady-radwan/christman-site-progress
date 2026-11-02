import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../library_store.dart';
import '../models.dart';
import '../widgets/project_cover.dart';

/// Choose the project's look on the home page: newest drone photo, your own
/// picture (logo, rendering, site photo) or an icon with a color.
Future<void> showCoverDialog(BuildContext context, Project project) {
  return showDialog<void>(context: context, builder: (_) => _CoverDialog(project: project));
}

class _CoverDialog extends StatefulWidget {
  const _CoverDialog({required this.project});
  final Project project;

  @override
  State<_CoverDialog> createState() => _CoverDialogState();
}

class _CoverDialogState extends State<_CoverDialog> {
  late CoverMode _mode = widget.project.coverMode;
  late String _icon = widget.project.coverIcon;
  late int _color = widget.project.coverColor;
  String? _imagePath;
  bool _saving = false;

  Future<void> _pickImage() async {
    final f = await openFile(acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Images',
        extensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif'],
        uniformTypeIdentifiers: ['public.image'],
      ),
    ]);
    if (f != null) {
      setState(() {
        _imagePath = f.path;
        _mode = CoverMode.image;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final store = context.read<LibraryStore>();
    await store.setCover(widget.project, _mode, imageSource: _imagePath, icon: _icon, color: _color);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<LibraryStore>();
    final scheme = Theme.of(context).colorScheme;
    final existingImage = store.coverFile(widget.project);
    final canSave = _mode != CoverMode.image || _imagePath != null || existingImage != null;

    Widget preview;
    if (_mode == CoverMode.image && _imagePath != null) {
      preview = Image.file(File(_imagePath!), fit: BoxFit.cover, cacheWidth: 800);
    } else {
      final temp = Project.fromJson(widget.project.toJson())
        ..coverMode = _mode
        ..coverIcon = _icon
        ..coverColor = _color;
      preview = ProjectCover(project: temp, iconSize: 72);
    }

    return AlertDialog(
      title: Text('Cover for ${widget.project.name}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(aspectRatio: 16 / 9, child: preview),
              ),
              const SizedBox(height: 16),
              SegmentedButton<CoverMode>(
                segments: const [
                  ButtonSegment(value: CoverMode.auto, icon: Icon(Icons.flight_rounded), label: Text('Latest drone photo')),
                  ButtonSegment(value: CoverMode.image, icon: Icon(Icons.image_outlined), label: Text('My picture')),
                  ButtonSegment(value: CoverMode.icon, icon: Icon(Icons.apartment_rounded), label: Text('Icon')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 16),
              if (_mode == CoverMode.image)
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: Text(_imagePath == null && existingImage == null
                      ? 'Choose a picture (logo, rendering, site photo)…'
                      : 'Choose a different picture…'),
                ),
              if (_mode == CoverMode.auto)
                Text('Shows the newest photo you added to this project.',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              if (_mode == CoverMode.icon) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in projectIcons.entries)
                      InkWell(
                        onTap: () => setState(() => _icon = e.key),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: _icon == e.key ? Color(_color) : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(e.value,
                              color: _icon == e.key ? Colors.white : scheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  children: [
                    for (final c in coverColors)
                      InkWell(
                        onTap: () => setState(() => _color = c),
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color == c ? scheme.onSurface : Colors.black26,
                              width: _color == c ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: !canSave || _saving ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
