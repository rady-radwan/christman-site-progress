import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import 'media_tile.dart';

/// The newest displayable photo for a building (and view) on or before [day].
(MediaItem, DateTime)? latestPhotoAsOf(Project pr, String buildingId, String? viewId, DateTime day) {
  final key = dayKey(day);
  final caps = pr.captures
      .where((c) =>
          c.buildingId == buildingId &&
          (viewId == null || c.viewId == viewId) &&
          dayKey(c.date).compareTo(key) <= 0 &&
          c.items.any((m) => m.isDisplayablePhoto))
      .toList();
  if (caps.isEmpty) return null;
  final b = pr.buildingById(buildingId);
  caps.sort((a, c) {
    final byDate = c.date.compareTo(a.date);
    if (byDate != 0) return byDate;
    // Same day: follow the order of the views in the sidebar.
    final ia = b?.views.indexWhere((v) => v.id == a.viewId) ?? 0;
    final ic = b?.views.indexWhere((v) => v.id == c.viewId) ?? 0;
    return ia.compareTo(ic);
  });
  final c = caps.first;
  return (c.items.firstWhere((m) => m.isDisplayablePhoto), c.date);
}

/// Lays out [count] cards left-to-right, as large as the space allows. Uses
/// one row when the cards stay a comfortable size, otherwise the grid that
/// gives the biggest cards.
class _CardRow extends StatelessWidget {
  const _CardRow({required this.count, required this.builder, this.footer = 92});

  final int count;
  final Widget Function(int i) builder;
  final double footer;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      const gap = 16.0, pad = 20.0;
      final w = box.maxWidth - pad * 2;
      final h = box.maxHeight - pad * 2;
      double cardW(int cols) {
        final rows = (count / cols).ceil();
        final byW = (w - gap * (cols - 1)) / cols;
        final byH = ((h - gap * (rows - 1)) / rows - footer) / 0.75;
        return math.min(byW, byH);
      }

      var cols = count;
      if (cardW(count) < 250) {
        var best = 1;
        for (var c = 1; c <= count; c++) {
          if (cardW(c) > cardW(best)) best = c;
        }
        cols = best;
      }
      final cw = math.max(180.0, cardW(cols));
      return SingleChildScrollView(
        padding: const EdgeInsets.all(pad),
        child: Center(
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < count; i++)
                SizedBox(width: cw, height: cw * 0.75 + footer, child: builder(i)),
            ],
          ),
        ),
      );
    });
  }
}

class _OverviewCard extends StatefulWidget {
  const _OverviewCard({
    required this.photo,
    required this.title,
    required this.badge,
    required this.lines,
    required this.onTap,
    this.photoNote,
    this.icon = Icons.photo_camera_outlined,
    this.highlight = false,
  });

  final MediaItem? photo;
  final String title;
  final String badge;
  final String? photoNote; // e.g. "from Aug 24"
  final List<Widget> lines;
  final VoidCallback onTap;
  final IconData icon;
  final bool highlight;

  @override
  State<_OverviewCard> createState() => _OverviewCardState();
}

class _OverviewCardState extends State<_OverviewCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = Theme.of(context).cardTheme.color;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hover || widget.highlight ? scheme.primary : (Theme.of(context).dividerTheme.color ?? Colors.transparent),
              width: _hover || widget.highlight ? 2 : 1,
            ),
            boxShadow: _hover ? const [BoxShadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 6))] : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.photo != null)
                        MediaThumb(item: widget.photo!, decodeWidth: 900)
                      else
                        Container(
                          color: scheme.surfaceContainerHighest,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(widget.icon, size: 40, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                              const SizedBox(height: 6),
                              Text('No photos yet', style: TextStyle(color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      Positioned(
                        left: 10,
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(widget.badge,
                              style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
                        ),
                      ),
                      if (widget.photoNote != null)
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xB3000000),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(widget.photoNote!,
                                style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(widget.icon, size: 17, color: scheme.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          ),
                          Icon(Icons.arrow_forward_rounded, size: 18, color: _hover ? scheme.primary : scheme.onSurfaceVariant),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...widget.lines,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips(this.items);
  final List<(IconData, String)> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 2,
      children: [
        for (final (icon, text) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 3),
              Text(text, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
      ],
    );
  }
}

String _asOf(DateTime shown, DateTime day) =>
    dayKey(shown) == dayKey(day) ? 'this date' : 'from ${DateFormat('MMM d').format(shown)}';

/// Every camera view of one building, left to right in sidebar order.
class BuildingViewsOverview extends StatelessWidget {
  const BuildingViewsOverview({
    super.key,
    required this.project,
    required this.building,
    required this.day,
    required this.onOpenView,
  });

  final Project project;
  final Building building;
  final DateTime day;
  final ValueChanged<String> onOpenView;

  @override
  Widget build(BuildContext context) {
    final views = building.views;
    return _CardRow(
      count: views.length,
      footer: 78,
      builder: (i) {
        final v = views[i];
        final latest = latestPhotoAsOf(project, building.id, v.id, day);
        final caps = project.captures.where((c) => c.buildingId == building.id && c.viewId == v.id).toList();
        final shots = caps.fold<int>(0, (s, c) => s + c.items.length);
        final onDay = caps.any((c) => dayKey(c.date) == dayKey(day));
        return _OverviewCard(
          photo: latest?.$1,
          title: v.name,
          badge: v.name,
          photoNote: latest == null ? null : _asOf(latest.$2, day),
          highlight: onDay,
          onTap: () => onOpenView(v.id),
          lines: [
            _Chips([
              (Icons.photo_library_outlined, '$shots shot${shots == 1 ? '' : 's'}'),
              (Icons.event_available_outlined, '${caps.length} capture${caps.length == 1 ? '' : 's'}'),
              if (latest != null) (Icons.history_rounded, 'shown: ${DateFormat('MMM d').format(latest.$2)}'),
            ]),
          ],
        );
      },
    );
  }
}

/// Every building of the project, left to right in sidebar order, with stats.
class AllBuildingsOverview extends StatelessWidget {
  const AllBuildingsOverview({
    super.key,
    required this.project,
    required this.day,
    required this.onOpenBuilding,
  });

  final Project project;
  final DateTime day;
  final ValueChanged<String> onOpenBuilding;

  @override
  Widget build(BuildContext context) {
    final bs = project.buildings;
    return _CardRow(
      count: bs.length,
      footer: 100,
      builder: (i) {
        final b = bs[i];
        final latest = latestPhotoAsOf(project, b.id, null, day);
        final caps = project.captures.where((c) => c.buildingId == b.id).toList();
        final photos = caps.fold<int>(0, (s, c) => s + c.items.where((m) => m.type == MediaType.photo).length);
        final videos = caps.fold<int>(0, (s, c) => s + c.items.where((m) => m.type == MediaType.video).length);
        final dates = caps.map((c) => dayKey(c.date)).toSet();
        final last = caps.isEmpty ? null : caps.map((c) => c.date).reduce((a, c) => a.isAfter(c) ? a : c);
        final onDay = dates.contains(dayKey(day));
        return _OverviewCard(
          photo: latest?.$1,
          title: b.name,
          badge: b.name,
          icon: Icons.apartment_rounded,
          photoNote: latest == null ? null : _asOf(latest.$2, day),
          highlight: onDay,
          onTap: () => onOpenBuilding(b.id),
          lines: [
            _Chips([
              (Icons.photo_camera_outlined, '${b.views.length} view${b.views.length == 1 ? '' : 's'}'),
              (Icons.photo_outlined, '$photos photo${photos == 1 ? '' : 's'}'),
              if (videos > 0) (Icons.videocam_outlined, '$videos video${videos == 1 ? '' : 's'}'),
              (Icons.event_available_outlined, '${dates.length} capture date${dates.length == 1 ? '' : 's'}'),
            ]),
            const SizedBox(height: 3),
            _Chips([
              (Icons.update_rounded, last == null ? 'No captures yet' : 'Last: ${DateFormat('MMM d, yyyy').format(last)}'),
            ]),
          ],
        );
      },
    );
  }
}
