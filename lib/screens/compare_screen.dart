import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../library_store.dart';
import '../models.dart';

/// Before/after comparison of two capture dates, with a draggable split line
/// or side by side.
class CompareScreen extends StatefulWidget {
  const CompareScreen({
    super.key,
    required this.project,
    required this.buildingId,
    required this.dates,
    required this.after,
  });

  final Project project;
  final String? buildingId;
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
  bool _sideBySide = false;

  @override
  void initState() {
    super.initState();
    _dates = widget.dates
        .where((d) => _photos(d).isNotEmpty)
        .toList();
    if (_dates.isEmpty) return;
    _afterDay = _dates.indexWhere((d) => dayKey(d) == dayKey(widget.after));
    if (_afterDay < 0) _afterDay = _dates.length - 1;
    _beforeDay = _afterDay > 0 ? _afterDay - 1 : 0;
  }

  List<MediaItem> _photos(DateTime d) => widget.project
      .mediaOn(d, widget.buildingId, MediaType.photo)
      .where((m) => m.isDisplayablePhoto)
      .toList();

  MediaItem? _item(int day, int photo) {
    if (_dates.isEmpty) return null;
    final list = _photos(_dates[day]);
    if (list.isEmpty) return null;
    return list[photo.clamp(0, list.length - 1)];
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<LibraryStore>();
    if (_dates.length < 2) {
      return Scaffold(
        appBar: AppBar(title: const Text('Compare weeks')),
        body: const Center(child: Text('You need photos on at least two dates to compare.')),
      );
    }
    final before = _item(_beforeDay, _beforePhoto)!;
    final after = _item(_afterDay, _afterPhoto)!;

    Widget img(MediaItem m) => Image.file(
          store.fileFor(m),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: const Text('Compare weeks'),
            actions: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.compare_rounded), label: Text('Slider')),
                  ButtonSegment(
                      value: true, icon: Icon(Icons.view_column_outlined), label: Text('Side by side')),
                ],
                selected: {_sideBySide},
                onSelectionChanged: (s) => setState(() => _sideBySide = s.first),
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: _sideBySide
                    ? Row(
                        children: [
                          Expanded(child: _zoomable(img(before), 'BEFORE', _dates[_beforeDay])),
                          const VerticalDivider(width: 2, color: Colors.white24),
                          Expanded(child: _zoomable(img(after), 'AFTER', _dates[_afterDay])),
                        ],
                      )
                    : LayoutBuilder(builder: (context, c) {
                        final w = c.maxWidth;
                        void move(Offset pos) => setState(() => _split = (pos.dx / w).clamp(0.0, 1.0));
                        return GestureDetector(
                          onHorizontalDragUpdate: (d) => move(d.localPosition),
                          onTapDown: (d) => move(d.localPosition),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.resizeColumn,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                img(after),
                                ClipRect(
                                  clipper: _LeftClipper(_split),
                                  child: Container(color: Colors.black, child: img(before)),
                                ),
                                Positioned(
                                  left: _split * w - 1,
                                  top: 0,
                                  bottom: 0,
                                  child: Container(width: 2, color: Colors.white),
                                ),
                                Positioned(
                                  left: _split * w - 20,
                                  top: c.maxHeight / 2 - 20,
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                    child: const Icon(Icons.code_rounded, color: Colors.white),
                                  ),
                                ),
                                Positioned(left: 12, top: 12, child: _tag('BEFORE', _dates[_beforeDay])),
                                Positioned(right: 12, top: 12, child: _tag('AFTER', _dates[_afterDay])),
                              ],
                            ),
                          ),
                        );
                      }),
              ),
              Material(
                color: Theme.of(context).appBarTheme.backgroundColor,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: _picker(
                            'Before',
                            _beforeDay,
                            _beforePhoto,
                            (d) => setState(() => _beforeDay = d),
                            (p) => setState(() => _beforePhoto = p),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _picker(
                            'After',
                            _afterDay,
                            _afterPhoto,
                            (d) => setState(() => _afterDay = d),
                            (p) => setState(() => _afterPhoto = p),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _zoomable(Widget child, String tag, DateTime d) => Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(maxScale: 20, child: child),
          Positioned(left: 12, top: 12, child: _tag(tag, d)),
        ],
      );

  Widget _tag(String tag, DateTime d) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xAA000000),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('$tag · Week ${widget.project.weekNumber(d)} · ${prettyDay(d)}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      );

  Widget _picker(String label, int day, int photo, ValueChanged<int> onDay, ValueChanged<int> onPhoto) {
    final count = _photos(_dates[day]).length;
    final shown = photo.clamp(0, count - 1);
    return Row(
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButton<int>(
            isExpanded: true,
            value: day,
            items: [
              for (var i = 0; i < _dates.length; i++)
                DropdownMenuItem(
                  value: i,
                  child: Text('Week ${widget.project.weekNumber(_dates[i])} · ${prettyDay(_dates[i])}'),
                ),
            ],
            onChanged: (v) {
              if (v != null) onDay(v);
            },
          ),
        ),
        IconButton(
          tooltip: 'Previous photo',
          onPressed: shown > 0 ? () => onPhoto(shown - 1) : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text('Photo ${shown + 1}/$count'),
        IconButton(
          tooltip: 'Next photo',
          onPressed: shown < count - 1 ? () => onPhoto(shown + 1) : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
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
