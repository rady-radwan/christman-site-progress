import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';

int _daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// A true calendar timeline from the first capture to the last. Every capture
/// sits at its real date, so uneven gaps between flights show as uneven
/// spacing. Month marks run along the line.
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
  final _scroll = ScrollController();
  List<double> _xs = const [];
  double _viewW = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(false));
  }

  @override
  void didUpdateWidget(covariant DateTrack old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex || old.dates.length != widget.dates.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(true));
    }
  }

  void _reveal(bool animate) {
    final i = widget.selectedIndex;
    if (!_scroll.hasClients || i < 0 || i >= _xs.length) return;
    final target = (_xs[i] - _viewW / 2).clamp(0.0, _scroll.position.maxScrollExtent);
    if (animate) {
      _scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      _scroll.jumpTo(target);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.accent ?? scheme.primary;
    final dates = widget.dates;
    final compact = widget.compact;
    final height = compact ? 58.0 : 80.0;
    final trackY = compact ? 20.0 : 30.0;

    return LayoutBuilder(builder: (context, box) {
      _viewW = box.maxWidth;
      if (dates.isEmpty) return SizedBox(height: height);
      final pad = compact ? 44.0 : 60.0;
      final first = dates.first;
      final span = math.max(1, _daysBetween(first, dates.last));
      var minGap = 1 << 30;
      for (var i = 1; i < dates.length; i++) {
        minGap = math.min(minGap, math.max(1, _daysBetween(dates[i - 1], dates[i])));
      }
      if (minGap == 1 << 30) minGap = 1;
      final minPx = compact ? 72.0 : 92.0;
      final ppd = math.max((box.maxWidth - 2 * pad) / span, minPx / minGap);
      final contentW = math.max(box.maxWidth, span * ppd + 2 * pad);
      _xs = dates.length == 1
          ? [box.maxWidth / 2]
          : [for (final d in dates) pad + _daysBetween(first, d) * ppd];
      final sel = widget.selectedIndex.clamp(0, dates.length - 1);
      final x0 = _xs.first, xN = _xs.last, xs = _xs[sel];

      // Month boundaries inside the range.
      final months = <(double, DateTime)>[];
      var m = DateTime(first.year, first.month + 1, 1);
      while (!m.isAfter(dates.last)) {
        months.add((pad + _daysBetween(first, m) * ppd, m));
        m = DateTime(m.year, m.month + 1, 1);
      }
      final muted = scheme.onSurfaceVariant;

      return Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent && _scroll.hasClients) {
            final d = e.scrollDelta.dx != 0 ? e.scrollDelta.dx : e.scrollDelta.dy;
            _scroll.jumpTo((_scroll.offset + d).clamp(0.0, _scroll.position.maxScrollExtent));
          }
        },
        child: Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentW,
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Track and progress up to the selected capture.
                  Positioned(
                    left: x0,
                    width: math.max(0.0, xN - x0),
                    top: trackY - 1,
                    height: 2,
                    child: Container(color: scheme.outlineVariant),
                  ),
                  Positioned(
                    left: x0,
                    width: math.max(0.0, xs - x0),
                    top: trackY - 1.5,
                    height: 3,
                    child: Container(color: accent),
                  ),
                  // Month marks
                  for (final (mx, md) in months) ...[
                    Positioned(
                      left: mx,
                      top: trackY - 7,
                      width: 1,
                      height: 14,
                      child: Container(color: muted.withValues(alpha: 0.6)),
                    ),
                    if (!compact)
                      Positioned(
                        left: mx + 4,
                        top: trackY - 22,
                        child: Text(
                          md.month == 1 ? DateFormat('MMM yyyy').format(md).toUpperCase() : DateFormat('MMM').format(md).toUpperCase(),
                          style: TextStyle(fontSize: 9.5, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: muted),
                        ),
                      ),
                  ],
                  // Captures
                  for (var i = 0; i < dates.length; i++)
                    Positioned(
                      left: _xs[i] - 42,
                      width: 84,
                      top: trackY - 11,
                      child: _Marker(
                        date: dates[i],
                        selected: i == sel,
                        accent: accent,
                        compact: compact,
                        showYear: !compact && (i == 0 || i == dates.length - 1 || dates[i].year != dates[i - 1].year),
                        onTap: () => widget.onSelect(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _Marker extends StatelessWidget {
  const _Marker({
    required this.date,
    required this.selected,
    required this.accent,
    required this.compact,
    required this.showYear,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final Color accent;
  final bool compact;
  final bool showYear;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = selected ? 18.0 : 11.0;
    return Tooltip(
      message: prettyDay(date),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 22,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: selected ? accent : scheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: selected ? Colors.white : accent, width: selected ? 3 : 2),
                    boxShadow: selected ? [BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 8)] : null,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              DateFormat('MMM d').format(date),
              style: TextStyle(
                fontSize: compact ? 11.5 : 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? accent : scheme.onSurface,
              ),
            ),
            if (showYear)
              Text('${date.year}', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
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
                        padding: const EdgeInsets.only(top: 6),
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
