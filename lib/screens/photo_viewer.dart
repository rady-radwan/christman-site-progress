import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../library_store.dart';
import '../models.dart';
import '../util.dart';

/// Full-quality photo viewer. Photos are decoded at their original resolution
/// and can be zoomed to actual pixels. ←/→ moves within the date, ↑/↓ jumps to
/// the same shot in the previous/next week.
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({
    super.key,
    required this.project,
    required this.buildingId,
    required this.viewId,
    required this.dates,
    required this.startDay,
    required this.startItemId,
  });

  final Project project;
  final String? buildingId;
  final String? viewId;
  final List<DateTime> dates;
  final DateTime startDay;
  final String startItemId;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late List<DateTime> _dates;
  late int _dayIndex;
  int _photoIndex = 0;
  final _tc = TransformationController();
  Size? _imageSize;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Offset _doubleTapPos = Offset.zero;
  bool _chrome = true;
  Size _box = Size.zero;

  LibraryStore get _store => context.read<LibraryStore>();

  @override
  void initState() {
    super.initState();
    // Only dates that actually have photos.
    _dates = widget.dates
        .where((d) => widget.project.mediaOn(d, widget.buildingId, MediaType.photo, viewId: widget.viewId).isNotEmpty)
        .toList();
    _dayIndex = _dates.indexWhere((d) => dayKey(d) == dayKey(widget.startDay));
    if (_dayIndex < 0) _dayIndex = 0;
    final photos = _photosOf(_dayIndex);
    final start = photos.indexWhere((m) => m.id == widget.startItemId);
    _photoIndex = start < 0 ? 0 : start;
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPhotoChanged());
  }

  @override
  void dispose() {
    _detachStream();
    _tc.dispose();
    super.dispose();
  }

  List<MediaItem> _photosOf(int dayIndex) {
    if (_dates.isEmpty) return [];
    return widget.project.mediaOn(_dates[dayIndex], widget.buildingId, MediaType.photo, viewId: widget.viewId);
  }

  MediaItem? get _current {
    final list = _photosOf(_dayIndex);
    if (list.isEmpty) return null;
    return list[_photoIndex.clamp(0, list.length - 1)];
  }

  void _detachStream() {
    if (_stream != null && _listener != null) _stream!.removeListener(_listener!);
    _stream = null;
    _listener = null;
  }

  void _onPhotoChanged() {
    _tc.value = Matrix4.identity();
    _detachStream();
    setState(() => _imageSize = null);
    final m = _current;
    if (m == null || !m.isDisplayablePhoto) return;
    final provider = FileImage(_store.fileFor(m));
    _stream = provider.resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener((info, _) {
      if (mounted) {
        setState(() => _imageSize = Size(info.image.width.toDouble(), info.image.height.toDouble()));
      }
    });
    _stream!.addListener(_listener!);
    _precacheNeighbours();
  }

  void _precacheNeighbours() {
    final list = _photosOf(_dayIndex);
    for (final i in [_photoIndex + 1, _photoIndex - 1]) {
      if (i >= 0 && i < list.length && list[i].isDisplayablePhoto) {
        precacheImage(FileImage(_store.fileFor(list[i])), context);
      }
    }
  }

  void _goPhoto(int delta) {
    final list = _photosOf(_dayIndex);
    final j = _photoIndex + delta;
    if (j < 0 || j >= list.length) {
      // Roll over into the neighbouring week.
      final nd = _dayIndex + delta;
      if (nd < 0 || nd >= _dates.length) return;
      setState(() {
        _dayIndex = nd;
        _photoIndex = delta > 0 ? 0 : _photosOf(nd).length - 1;
      });
    } else {
      setState(() => _photoIndex = j);
    }
    _onPhotoChanged();
  }

  /// Index of the matching shot on another day: same building and camera
  /// view, same position within that view; falls back to the same position.
  int _matchingIndex(int targetDay) {
    final target = _photosOf(targetDay);
    final m = _current;
    if (m == null || target.isEmpty) return 0;
    final pr = widget.project;
    final c = _store.captureContaining(pr, m);
    if (c != null) {
      final posInView = c.photos.indexOf(m);
      final other = pr
          .capturesOn(_dates[targetDay], c.buildingId, viewId: c.viewId)
          .expand((x) => x.photos)
          .toList();
      if (other.isNotEmpty) {
        final pick = other[posInView.clamp(0, other.length - 1)];
        final i = target.indexOf(pick);
        if (i >= 0) return i;
      }
    }
    return _photoIndex.clamp(0, target.length - 1);
  }

  /// Same shot, different week — ideal for repeat drone waypoints.
  void _goWeek(int delta) {
    final nd = _dayIndex + delta;
    if (nd < 0 || nd >= _dates.length) return;
    final idx = _matchingIndex(nd);
    setState(() {
      _dayIndex = nd;
      _photoIndex = idx;
    });
    _onPhotoChanged();
  }

  void _jumpToDay(int i) {
    final idx = _matchingIndex(i);
    setState(() {
      _dayIndex = i;
      _photoIndex = idx;
    });
    _onPhotoChanged();
  }

  double get _fitScale {
    final s = _imageSize;
    if (s == null || _box.isEmpty) return 1;
    return (_box.width / s.width) < (_box.height / s.height)
        ? _box.width / s.width
        : _box.height / s.height;
  }

  /// Zoom that shows one image pixel per screen pixel.
  double get _actualPixelsZoom {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return (1 / dpr) / _fitScale;
  }

  void _toggleZoom([Offset? focal]) {
    final current = _tc.value.getMaxScaleOnAxis();
    if (current > 1.01) {
      _tc.value = Matrix4.identity();
      return;
    }
    var target = _actualPixelsZoom;
    if (target < 2) target = 2.5;
    final f = focal ?? Offset(_box.width / 2, _box.height / 2);
    _tc.value = Matrix4.diagonal3Values(target, target, 1)
      ..setTranslationRaw(-f.dx * (target - 1), -f.dy * (target - 1), 0);
  }

  Future<void> _export() async {
    final m = _current;
    if (m == null) return;
    final dir = await getDirectoryPath(confirmButtonText: 'Export here');
    if (dir == null || !mounted) return;
    await _store.exportItems([m], dir);
    if (mounted) showSnack(context, 'Exported original to $dir');
  }

  void _close() => Navigator.pop(context, _dates.isEmpty ? null : _dates[_dayIndex]);

  @override
  Widget build(BuildContext context) {
    final m = _current;
    final photos = _photosOf(_dayIndex);
    final day = _dates.isEmpty ? null : _dates[_dayIndex];
    final cap = m == null ? null : _store.captureContaining(widget.project, m);
    final bName = cap == null ? '' : widget.project.labelFor(cap);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _goPhoto(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _goPhoto(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _goWeek(-1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _goWeek(1),
        const SingleActivator(LogicalKeyboardKey.pageUp): () => _goWeek(-1),
        const SingleActivator(LogicalKeyboardKey.pageDown): () => _goWeek(1),
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        const SingleActivator(LogicalKeyboardKey.keyZ): () => _toggleZoom(),
        const SingleActivator(LogicalKeyboardKey.keyH): () => setState(() => _chrome = !_chrome),
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _close();
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: m == null
                ? Center(
                    child: TextButton(onPressed: _close, child: const Text('No photos — go back')))
                : Stack(
                    children: [
                      Positioned.fill(
                        child: LayoutBuilder(builder: (context, c) {
                          _box = Size(c.maxWidth, c.maxHeight);
                          if (!m.isDisplayablePhoto) return _Unpreviewable(item: m);
                          return GestureDetector(
                            onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
                            onDoubleTap: () => _toggleZoom(_doubleTapPos),
                            onTap: () => setState(() => _chrome = !_chrome),
                            child: InteractiveViewer(
                              transformationController: _tc,
                              minScale: 1,
                              maxScale: (_actualPixelsZoom * 4).clamp(8, 60),
                              child: SizedBox(
                                width: c.maxWidth,
                                height: c.maxHeight,
                                child: Image.file(
                                  _store.fileFor(m),
                                  key: ValueKey(m.id),
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                  gaplessPlayback: true,
                                  isAntiAlias: true,
                                  errorBuilder: (context, e, s) => _Unpreviewable(item: m),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                      if (_chrome) _topBar(m, photos.length, day, bName),
                      if (_chrome) ..._sideArrows(photos.length),
                      if (_chrome && _dates.length > 1) _weekStrip(),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(MediaItem m, int count, DateTime? day, String bName) {
    final size = _imageSize;
    final details = [
      if (size != null) '${size.width.toInt()} × ${size.height.toInt()} px',
      prettySize(m.sizeBytes),
    ].join(' · ');
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xDD000000), Colors.transparent],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              IconButton(
                color: Colors.white,
                tooltip: 'Back (Esc)',
                onPressed: _close,
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      day == null
                          ? ''
                          : '${prettyDay(day)} · capture ${_dayIndex + 1} of ${_dates.length}${bName.isEmpty ? '' : ' · $bName'}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    Text(
                      '${_photoIndex + 1} of $count · ${m.fileName} · $details · original: ${m.originalName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                color: Colors.white,
                tooltip: 'Zoom to actual pixels (Z / double-click)',
                onPressed: () => _toggleZoom(),
                icon: const Icon(Icons.zoom_in_map_rounded),
              ),
              IconButton(
                color: Colors.white,
                tooltip: 'Export original',
                onPressed: _export,
                icon: const Icon(Icons.file_download_outlined),
              ),
              if (Platform.isWindows)
                IconButton(
                  color: Colors.white,
                  tooltip: 'Show in folder',
                  onPressed: () => revealFile(_store.fileFor(m).path),
                  icon: const Icon(Icons.folder_open_outlined),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _sideArrows(int count) {
    final canPrev = _photoIndex > 0 || _dayIndex > 0;
    final canNext = _photoIndex < count - 1 || _dayIndex < _dates.length - 1;
    Widget btn(IconData icon, VoidCallback? onTap, String tip) => IconButton.filled(
          tooltip: tip,
          style: IconButton.styleFrom(
            backgroundColor: const Color(0x66000000),
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.transparent,
          ),
          iconSize: 30,
          onPressed: onTap,
          icon: Icon(icon),
        );
    return [
      Positioned(
        left: 12,
        top: 0,
        bottom: 0,
        child: Center(child: btn(Icons.chevron_left_rounded, canPrev ? () => _goPhoto(-1) : null, 'Previous (←)')),
      ),
      Positioned(
        right: 12,
        top: 0,
        bottom: 0,
        child: Center(child: btn(Icons.chevron_right_rounded, canNext ? () => _goPhoto(1) : null, 'Next (→)')),
      ),
    ];
  }

  Widget _weekStrip() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xDD000000), Colors.transparent],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              IconButton(
                color: Colors.white,
                tooltip: 'Same shot, previous week (↑)',
                onPressed: _dayIndex > 0 ? () => _goWeek(-1) : null,
                icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
              ),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _dates.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, i) {
                      final sel = i == _dayIndex;
                      return ChoiceChip(
                        label: Text(DateFormat('MMM d, yy').format(_dates[i])),
                        selected: sel,
                        showCheckmark: false,
                        onSelected: (_) => _jumpToDay(i),
                      );
                    },
                  ),
                ),
              ),
              IconButton(
                color: Colors.white,
                tooltip: 'Same shot, next week (↓)',
                onPressed: _dayIndex < _dates.length - 1 ? () => _goWeek(1) : null,
                icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Unpreviewable extends StatelessWidget {
  const _Unpreviewable({required this.item});
  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final store = context.read<LibraryStore>();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_not_supported_outlined, color: Colors.white54, size: 56),
          const SizedBox(height: 12),
          Text('${item.extension.toUpperCase().replaceFirst('.', '')} files are stored in full quality but can\'t be previewed here.',
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          if (isDesktop)
            FilledButton.icon(
              onPressed: () => openWithDefaultApp(store.fileFor(item).path),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open in default app'),
            ),
        ],
      ),
    );
  }
}
