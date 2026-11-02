import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';

/// The week-by-week bar along the bottom of a project. Each stop is a capture
/// date; clicking one shows the site as it was that day.
class TimelineBar extends StatefulWidget {
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
  State<TimelineBar> createState() => _TimelineBarState();
}

class _TimelineBarState extends State<TimelineBar> {
  final _scroll = ScrollController();
  final Map<String, GlobalKey> _keys = {};

  int get _index {
    final s = widget.selected;
    if (s == null) return -1;
    return widget.dates.indexWhere((d) => dayKey(d) == dayKey(s));
  }

  @override
  void didUpdateWidget(covariant TimelineBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected ||
        oldWidget.dates.length != widget.dates.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(animate: false));
  }

  void _reveal({bool animate = true}) {
    final s = widget.selected;
    if (s == null) return;
    final ctx = _keys[dayKey(s)]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: animate ? const Duration(milliseconds: 250) : Duration.zero,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final i = _index;
    final dates = widget.dates;
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
                tooltip: 'Previous week (←)',
                onPressed: i > 0 ? () => widget.onSelect(dates[i - 1]) : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton.filledTonal(
                tooltip: widget.playing ? 'Pause' : 'Play week by week',
                onPressed: dates.length > 1 ? widget.onTogglePlay : null,
                icon: Icon(widget.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              ),
              IconButton(
                tooltip: 'Next week (→)',
                onPressed: i >= 0 && i < dates.length - 1 ? () => widget.onSelect(dates[i + 1]) : null,
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
                    : Scrollbar(
                        controller: _scroll,
                        child: ListView.builder(
                          controller: _scroll,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          itemCount: dates.length,
                          itemBuilder: (context, k) {
                            final d = dates[k];
                            final key = _keys.putIfAbsent(dayKey(d), () => GlobalKey());
                            return _Stop(
                              key: key,
                              date: d,
                              week: widget.project.weekNumber(d),
                              selected: k == i,
                              first: k == 0,
                              last: k == dates.length - 1,
                              onTap: () => widget.onSelect(d),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stop extends StatelessWidget {
  const _Stop({
    super.key,
    required this.date,
    required this.week,
    required this.selected,
    required this.first,
    required this.last,
    required this.onTap,
  });

  final DateTime date;
  final int week;
  final bool selected;
  final bool first;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lineColor = scheme.outlineVariant;
    final textColor = selected ? scheme.primary : scheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 92,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('WEEK $week',
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            SizedBox(
              height: 16,
              child: Row(
                children: [
                  Expanded(child: Container(height: 2, color: first ? Colors.transparent : lineColor)),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: selected ? 16 : 10,
                    height: selected ? 16 : 10,
                    decoration: BoxDecoration(
                      color: selected ? scheme.primary : scheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: selected ? scheme.primary : scheme.outline, width: 2),
                    ),
                  ),
                  Expanded(child: Container(height: 2, color: last ? Colors.transparent : lineColor)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(DateFormat('MMM d').format(date),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: textColor)),
            Text(DateFormat('yyyy').format(date),
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
