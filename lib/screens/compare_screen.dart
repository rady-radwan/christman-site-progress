import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../library_store.dart';
import '../models.dart';
import '../widgets/timeline_bar.dart';

enum CompareMode { slider, sideBySide, overlay }

const _beforeColor = Color(0xFF4FA3E0);
const _afterColor = Color(0xFFE8742A);

/// Compare Progress: two capture dates as a before/after slider, side by side,
/// or overlaid with adjustable transparency. Zoom is linked in every mode.
class CompareScreen extends StatefulWidget {
  const CompareScreen({
    super.key,
    required this.project,
    required this.buildingId,
    required this.viewId,
    required this.dates,
    required this.after,
  });

  final Project project;
  final String? buildingId;
  final String? viewId;
  final List<DateTime> dates;
  final DateTime after;

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  late final List<DateTime> _dates;
  int _beforeDay = 0;
  int _afterDay = 0;
  int _beforePhoto = 0;
  int _afterPhoto = 0;
  double _split = 0.5;
  CompareMode _mode = CompareMode.slider;
  double _beforeOpacity = 1.0;
  double _afterOpacity = 0.5;
  bool _afterOnTop = true;
  final _tc = TransformationController();

  LibraryStore get _store => context.read<LibraryStore>();

  @override
  void initState() {
    super.initState();
    _dates = widget.dates.where((d) => _photos(d).isNotEmpty).toList();
    if (_dates.isEmpty) return;
    _afterDay = _dates.indexWhere((d) => dayKey(d) == dayKey(widget.after));
    if (_afterDay < 0) _afterDay = _dates.length - 1;
    _beforeDay = _afterDay > 0 ? _afterDay - 1 : 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _beforePhoto = _match(_afterDay, _afterPhoto, _beforeDay));
    });
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  List<MediaItem> _photos(DateTime d) => widget.project
      .mediaOn(d, widget.buildingId, MediaType.photo, viewId: widget.viewId)
      .where((m) => m.isDisplayablePhoto)
      .toList();

  MediaItem? _item(int day, int photo) {
    if (_dates.isEmpty) return null;
    final list = _photos(_dates[day]);
    if (list.isEmpty) return null;
    return list[photo.clamp(0, list.length - 1)];
  }

  /// Picks the photo on [toDay] taken from the same building and camera view
  /// as the photo at ([fromDay], [fromPhoto]).
  int _match(int fromDay, int fromPhoto, int toDay) {
    final target = _photos(_dates[toDay]);
    final m = _item(fromDay, fromPhoto);
    if (m == null || target.isEmpty) return 0;
    final pr = widget.project;
    final c = _store.captureContaining(pr, m);
    if (c != null) {
      final pos = c.photos.where((x) => x.isDisplayablePhoto).toList().indexOf(m);
      final same = pr
          .capturesOn(_dates[toDay], c.buildingId, viewId: c.viewId)
          .expand((x) => x.photos)
          .where((x) => x.isDisplayablePhoto)
          .toList();
      if (same.isNotEmpty) {
        final i = target.indexOf(same[pos.clamp(0, same.length - 1)]);
        if (i >= 0) return i;
      }
    }
    return fromPhoto.clamp(0, target.length - 1);
  }

  String _viewLabel(MediaItem m) {
    final c = _store.captureContaining(widget.project, m);
    return c == null ? '' : widget.project.labelFor(c);
  }

  Widget _img(MediaItem m) => Image.file(
        _store.fileFor(m),
        key: ValueKey(m.id),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
      );

  Widget _zoom(Widget child) => InteractiveViewer(
        transformationController: _tc,
        maxScale: 30,
        child: SizedBox.expand(child: child),
      );

  @override
  Widget build(BuildContext context) {
    if (_dates.length < 2) {
      return Scaffold(
        appBar: AppBar(title: const Text('Compare Progress')),
        body: const Center(child: Text('You need photos on at least two dates to compare progress.')),
      );
    }
    final before = _item(_beforeDay, _beforePhoto)!;
    final after = _item(_afterDay, _afterPhoto)!;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.digit0): () => _tc.value = Matrix4.identity(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: const Text('Compare Progress'),
            actions: [
              IconButton(
                tooltip: 'Reset zoom (0)',
                onPressed: () => _tc.value = Matrix4.identity(),
                icon: const Icon(Icons.fit_screen_outlined),
              ),
              const SizedBox(width: 8),
              SegmentedButton<CompareMode>(
                segments: const [
                  ButtonSegment(value: CompareMode.slider, icon: Icon(Icons.compare_rounded), label: Text('Slider')),
                  ButtonSegment(
                      value: CompareMode.sideBySide,
                      icon: Icon(Icons.view_column_outlined),
                      label: Text('Side by side')),
                  ButtonSegment(
                      value: CompareMode.overlay, icon: Icon(Icons.layers_outlined), label: Text('Overlay')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: Column(
            children: [
              Expanded(child: ClipRect(child: _viewport(before, after))),
              _controls(before, after),
            ],
          ),
        ),
      ),
    );
  }

  Widget _viewport(MediaItem before, MediaItem after) {
    final beforeTag = _tag('BEFORE', _dates[_beforeDay], _viewLabel(before), _beforeColor);
    final afterTag = _tag('AFTER', _dates[_afterDay], _viewLabel(after), _afterColor);

    switch (_mode) {
      case CompareMode.sideBySide:
        return Row(
          children: [
            Expanded(child: Stack(children: [_zoom(_img(before)), Positioned(left: 12, top: 12, child: beforeTag)])),
            const VerticalDivider(width: 2, color: Colors.white24),
            Expanded(child: Stack(children: [_zoom(_img(after)), Positioned(left: 12, top: 12, child: afterTag)])),
          ],
        );

      case CompareMode.overlay:
        final bottom = _afterOnTop
            ? Opacity(opacity: _beforeOpacity, child: _img(before))
            : Opacity(opacity: _afterOpacity, child: _img(after));
        final top = _afterOnTop
            ? Opacity(opacity: _afterOpacity, child: _img(after))
            : Opacity(opacity: _beforeOpacity, child: _img(before));
        return Stack(
          children: [
            _zoom(Stack(fit: StackFit.expand, children: [bottom, top])),
            Positioned(left: 12, top: 12, child: beforeTag),
            Positioned(right: 12, top: 12, child: afterTag),
          ],
        );

      case CompareMode.slider:
        return LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          final x = _split * w;
          return Stack(
            children: [
              // Both layers share one zoom; the Before layer is clipped to the
              // left of the line, in screen space, so zooming keeps them aligned.
              Positioned.fill(child: _zoom(_img(after))),
              Positioned.fill(
                child: ClipRect(
                  clipper: _LeftClipper(_split),
                  child: Container(color: Colors.black, child: _zoom(_img(before))),
                ),
              ),
              Positioned(left: x - 1, top: 0, bottom: 0, child: IgnorePointer(child: Container(width: 2, color: Colors.white))),
              Positioned(
                left: x - 22,
                top: 0,
                bottom: 0,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) =>
                        setState(() => _split = ((x + d.delta.dx) / w).clamp(0.0, 1.0)),
                    child: SizedBox(
                      width: 44,
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _afterColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.code_rounded, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(left: 12, top: 12, child: beforeTag),
              Positioned(right: 12, top: 12, child: afterTag),
            ],
          );
        });
    }
  }

  Widget _tag(String tag, DateTime d, String view, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xB0000000),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Text(
          '$tag · ${prettyDay(d)}${view.isEmpty ? '' : ' · $view'}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      );

  Widget _controls(MediaItem before, MediaItem after) {
    return Material(
      color: Theme.of(context).appBarTheme.backgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _row(
                label: 'BEFORE',
                color: _beforeColor,
                day: _beforeDay,
                photo: _beforePhoto,
                item: before,
                opacity: _beforeOpacity,
                onDay: (d) => setState(() {
                  _beforePhoto = _match(_beforeDay, _beforePhoto, d);
                  _beforeDay = d;
                }),
                onPhoto: (p) => setState(() => _beforePhoto = p),
                onOpacity: (v) => setState(() => _beforeOpacity = v),
              ),
              const Divider(height: 8),
              _row(
                label: 'AFTER',
                color: _afterColor,
                day: _afterDay,
                photo: _afterPhoto,
                item: after,
                opacity: _afterOpacity,
                onDay: (d) => setState(() {
                  _afterPhoto = _match(_afterDay, _afterPhoto, d);
                  _afterDay = d;
                }),
                onPhoto: (p) => setState(() {
                  _afterPhoto = p;
                  _beforePhoto = _match(_afterDay, p, _beforeDay);
                }),
                onOpacity: (v) => setState(() => _afterOpacity = v),
              ),
              if (_mode == CompareMode.overlay)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _afterOnTop = !_afterOnTop),
                    icon: const Icon(Icons.swap_vert_rounded),
                    label: Text(_afterOnTop ? 'After is on top — swap' : 'Before is on top — swap'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row({
    required String label,
    required Color color,
    required int day,
    required int photo,
    required MediaItem item,
    required double opacity,
    required ValueChanged<int> onDay,
    required ValueChanged<int> onPhoto,
    required ValueChanged<double> onOpacity,
  }) {
    final count = _photos(_dates[day]).length;
    final shown = photo.clamp(0, count - 1);
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 74,
          padding: const EdgeInsets.symmetric(vertical: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color),
          ),
          child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
        ),
        IconButton(
          tooltip: 'Previous week',
          onPressed: day > 0 ? () => onDay(day - 1) : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: MiniTimeline(
            project: widget.project,
            dates: _dates,
            selectedIndex: day,
            accent: color,
            onSelect: onDay,
          ),
        ),
        IconButton(
          tooltip: 'Next week',
          onPressed: day < _dates.length - 1 ? () => onDay(day + 1) : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        const SizedBox(height: 44, child: VerticalDivider(width: 16, indent: 6, endIndent: 6)),
        SizedBox(
          width: 210,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Previous photo',
                onPressed: shown > 0 ? () => onPhoto(shown - 1) : null,
                icon: const Icon(Icons.navigate_before_rounded),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Photo ${shown + 1} of $count', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(_viewLabel(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Next photo',
                onPressed: shown < count - 1 ? () => onPhoto(shown + 1) : null,
                icon: const Icon(Icons.navigate_next_rounded),
              ),
            ],
          ),
        ),
        if (_mode == CompareMode.overlay) ...[
          const SizedBox(height: 44, child: VerticalDivider(width: 16, indent: 6, endIndent: 6)),
          SizedBox(
            width: 230,
            child: Row(
              children: [
                Icon(Icons.opacity_rounded, size: 18, color: color),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(activeTrackColor: color, thumbColor: color),
                    child: Slider(value: opacity, onChanged: onOpacity),
                  ),
                ),
                SizedBox(width: 40, child: Text('${(opacity * 100).round()}%')),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _LeftClipper extends CustomClipper<Rect> {
  _LeftClipper(this.fraction);
  final double fraction;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_LeftClipper old) => old.fraction != fraction;
}
