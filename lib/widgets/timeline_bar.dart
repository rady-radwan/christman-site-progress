import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';

int _daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// A calendar timeline from the first capture to the last that always fits
/// the available width. Every capture sits at its real date. It works like a
/// slider: drag the handle (or click anywhere) and it snaps to the nearest
/// capture.
class DateTrack extends StatefulWidget {
  const DateTrack({
    super.key,
    required this.dates,
    required this.selectedIndex,
    required this.onSelect,
    this.accent,
    this.compact = false,
  });

  final List<DateTime> dates;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final Color? accent;
  final bool compact;

  @override
  State<DateTrack> createState() => _DateTrackState();
}

class _DateTrackState extends State<DateTrack> {
  double? _dragX; // handle position while dragging
  List<double> _xs = const [];

  int _nearest(double x) {
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < _xs.length; i++) {
      final d = (x - _xs[i]).abs();
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  void _pointer(double x, {bool dragging = true}) {
    if (_xs.isEmpty) return;
    final lo = _xs.first, hi = _xs.last;
    setState(() => _dragX = dragging ? x.clamp(lo, hi) : null);
    final i = _nearest(x);
    if (i != widget.selectedIndex) widget.onSelect(i);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.accent ?? scheme.primary;
    final dates = widget.dates;
    final compact = widget.compact;
    final height = compact ? 58.0 : 80.0;
    final trackY = compact ? 18.0 : 30.0;

    return LayoutBuilder(builder: (context, box) {
      if (dates.isEmpty) return SizedBox(height: height);
      final pad = compact ? 34.0 : 44.0;
      final w = box.maxWidth;
      final first = dates.first;
      final span = math.max(1, _daysBetween(first, dates.last));
      final usable = math.max(10.0, w - 2 * pad);
      _xs = dates.length == 1
          ? [w / 2]
          : [for (final d in dates) pad + _daysBetween(first, d) / span * usable];
      final sel = widget.selectedIndex.clamp(0, dates.length - 1);
      final selX = _xs[sel];
      final handleX = _dragX ?? selX;

      // Which dates get a text label (the rest are dots with a tooltip).
      final labelGap = compact ? 58.0 : 66.0;
      final labelled = <int>{sel};
      for (final i in [0, dates.length - 1]) {
        if ((_xs[i] - selX).abs() >= labelGap) labelled.add(i);
      }
      for (var i = 0; i < dates.length; i++) {
        if (labelled.contains(i)) continue;
        if (labelled.every((j) => (_xs[j] - _xs[i]).abs() >= labelGap)) labelled.add(i);
      }

      // Month boundaries
      final months = <(double, DateTime)>[];
      var m = DateTime(first.year, first.month + 1, 1);
      while (!m.isAfter(dates.last)) {
        months.add((pad + _daysBetween(first, m) / span * usable, m));
        m = DateTime(m.year, m.month + 1, 1);
      }
      final monthLabelEvery = math.max(1, (months.length / math.max(1, w / 70)).ceil());
      final muted = scheme.onSurfaceVariant;

      return MouseRegion(
        cursor: _dragX != null ? SystemMouseCursors.grabbing : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _pointer(d.localPosition.dx, dragging: false),
          onHorizontalDragStart: (d) => _pointer(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => _pointer(d.localPosition.dx),
          onHorizontalDragEnd: (_) => setState(() => _dragX = null),
          onHorizontalDragCancel: () => setState(() => _dragX = null),
          child: SizedBox(
            width: w,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Track and progress
                Positioned(
                  left: _xs.first,
                  width: math.max(0.0, _xs.last - _xs.first),
                  top: trackY - 2,
                  height: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Positioned(
                  left: _xs.first,
                  width: math.max(0.0, handleX - _xs.first),
                  top: trackY - 2,
                  height: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                // Month marks
                for (var k = 0; k < months.length; k++) ...[
                  Positioned(
                    left: months[k].$1,
                    top: trackY - 8,
                    width: 1,
                    height: 16,
                    child: Container(color: muted.withValues(alpha: 0.55)),
                  ),
                  if (!compact && k % monthLabelEvery == 0)
                    Positioned(
                      left: months[k].$1 + 4,
                      top: trackY - 24,
                      child: Text(
                        months[k].$2.month == 1
                            ? DateFormat('MMM yyyy').format(months[k].$2).toUpperCase()
                            : DateFormat('MMM').format(months[k].$2).toUpperCase(),
                        style: TextStyle(fontSize: 9.5, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: muted),
                      ),
                    ),
                ],
                // Capture dots
                for (var i = 0; i < dates.length; i++)
                  Positioned(
                    left: _xs[i] - 7,
                    top: trackY - 7,
                    width: 14,
                    height: 14,
                    child: Tooltip(
                      message: prettyDay(dates[i]),
                      child: Container(
                        decoration: BoxDecoration(
                          color: i <= sel ? accent : scheme.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: accent, width: 2),
                        ),
                      ),
                    ),
                  ),
                // Date labels
                for (final i in labelled)
                  Positioned(
                    left: _xs[i] - 45,
                    width: 90,
                    top: trackY + 12,
                    child: IgnorePointer(
                      child: Column(
                        children: [
                          Text(
                            DateFormat('MMM d').format(dates[i]),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: compact ? 11.5 : 13,
                              fontWeight: i == sel ? FontWeight.w800 : FontWeight.w500,
                              color: i == sel ? accent : scheme.onSurface,
                            ),
                          ),
                          if (!compact &&
                              (i == 0 || i == dates.length - 1 || dates[i].year != dates[i - 1].year))
                            Text('${dates[i].year}', style: TextStyle(fontSize: 10, color: muted)),
                        ],
                      ),
                    ),
                  ),
                // Slider handle
                AnimatedPositioned(
                  duration: _dragX != null ? Duration.zero : const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  left: handleX - 12,
                  top: trackY - 12,
                  width: 24,
                  height: 24,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.55), blurRadius: 10)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// The capture timeline along the bottom of a project, with previous/next
/// and play controls.
class TimelineBar extends StatelessWidget {
  const TimelineBar({
    super.key,
    required this.project,
    required this.dates,
    required this.selected,
    required this.onSelect,
    required this.playing,
    required this.onTogglePlay,
  });

  final Project project;
  final List<DateTime> dates;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;
  final bool playing;
  final VoidCallback onTogglePlay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = selected;
    final i = s == null ? -1 : dates.indexWhere((d) => dayKey(d) == dayKey(s));
    final span = dates.length < 2 ? 0 : _daysBetween(dates.first, dates.last);
    return Material(
      color: Theme.of(context).appBarTheme.backgroundColor,
      elevation: 2,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 92,
          child: Row(
            children: [
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Previous capture (←)',
                onPressed: i > 0 ? () => onSelect(dates[i - 1]) : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton.filledTonal(
                tooltip: playing ? 'Pause' : 'Play capture by capture',
                onPressed: dates.length > 1 ? onTogglePlay : null,
                icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              ),
              IconButton(
                tooltip: 'Next capture (→)',
                onPressed: i >= 0 && i < dates.length - 1 ? () => onSelect(dates[i + 1]) : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              const SizedBox(width: 4),
              const VerticalDivider(width: 1, indent: 16, endIndent: 16),
              Expanded(
                child: dates.isEmpty
                    ? Center(
                        child: Text('No captures yet — add photos or videos to start the timeline',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      )
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                        child: DateTrack(
                          dates: dates,
                          selectedIndex: i < 0 ? dates.length - 1 : i,
                          onSelect: (k) => onSelect(dates[k]),
                        ),
                      ),
              ),
              if (dates.length > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${dates.length} captures',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      Text('over $span days', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact date timeline used to pick one photo's date (e.g. Before/After in
/// Compare Progress).
class MiniTimeline extends StatelessWidget {
  const MiniTimeline({
    super.key,
    required this.project,
    required this.dates,
    required this.selectedIndex,
    required this.onSelect,
    this.accent,
  });

  final Project project;
  final List<DateTime> dates;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final Color? accent;

  @override
  Widget build(BuildContext context) => DateTrack(
        dates: dates,
        selectedIndex: selectedIndex,
        onSelect: onSelect,
        accent: accent,
        compact: true,
      );
}
