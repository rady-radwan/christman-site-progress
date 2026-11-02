import '../models.dart';
import 'timelapse_settings.dart';

/// One photo shown in the timelapse, with what the overlay should say.
class TimelapseSlot {
  TimelapseSlot({
    required this.item,
    required this.date,
    required this.week,
    required this.dayNumber,
    required this.building,
    required this.view,
    required this.note,
  });

  final MediaItem item;
  final DateTime date;
  final int week;
  final int dayNumber; // days since the first date in the video, starting at 1
  final String building;
  final String view;
  final String note;
}

/// What to draw on one frame.
class FrameInfo {
  const FrameInfo({
    this.isTitle = false,
    this.titleProgress = 0,
    this.slot = 0,
    this.nextSlot,
    this.mix = 0,
    this.local = 0,
    this.global = 0,
  });

  final bool isTitle;
  final double titleProgress; // 0..1 through the title card
  final int slot; // photo index
  final int? nextSlot; // set while cross-fading into the next photo
  final double mix; // 0..1 amount of nextSlot
  final double local; // 0..1 through the current photo's time on screen
  final double global; // 0..1 through the whole photo sequence

  /// The slot whose labels are shown (switches halfway through a fade).
  int get labelSlot => (nextSlot != null && mix >= 0.5) ? nextSlot! : slot;
}

/// Turns settings + photos into a frame-by-frame schedule.
class TimelapsePlan {
  TimelapsePlan({
    required this.settings,
    required this.slots,
    required this.projectName,
    required this.scopeLabel,
  });

  final TimelapseSettings settings;
  final List<TimelapseSlot> slots;
  final String projectName;
  final String scopeLabel; // "Hospital · Front"

  int get fps => settings.fps;
  int get framesPerSlot => (settings.secondsPerPhoto * fps).round().clamp(1, 100000);
  int get transitionFrames => settings.transition == PhotoTransition.cut || slots.length < 2
      ? 0
      : (settings.transitionSeconds * fps).round().clamp(0, framesPerSlot - 1);
  int get titleFrames => settings.titleCard && slots.isNotEmpty ? (settings.titleSeconds * fps).round() : 0;
  int get holdFrames => slots.isEmpty ? 0 : (settings.endHoldSeconds * fps).round();
  int get sequenceFrames => slots.length * framesPerSlot;
  int get totalFrames => titleFrames + sequenceFrames + holdFrames;
  Duration get duration => Duration(milliseconds: (totalFrames * 1000 / fps).round());

  FrameInfo at(int frame) {
    if (slots.isEmpty) return const FrameInfo();
    if (frame < titleFrames) {
      return FrameInfo(isTitle: true, titleProgress: titleFrames == 0 ? 1 : frame / titleFrames);
    }
    final g = frame - titleFrames;
    if (g >= sequenceFrames) {
      return FrameInfo(slot: slots.length - 1, local: 1, global: 1);
    }
    final i = g ~/ framesPerSlot;
    final inSlot = g % framesPerSlot;
    final local = framesPerSlot <= 1 ? 1.0 : inSlot / (framesPerSlot - 1);
    final global = sequenceFrames <= 1 ? 1.0 : g / (sequenceFrames - 1);
    final tStart = framesPerSlot - transitionFrames;
    if (transitionFrames > 0 && i < slots.length - 1 && inSlot >= tStart) {
      final mix = (inSlot - tStart + 1) / (transitionFrames + 1);
      return FrameInfo(slot: i, nextSlot: i + 1, mix: mix, local: local, global: global);
    }
    return FrameInfo(slot: i, local: local, global: global);
  }

  /// First frame where [slotIndex] is fully on screen (for preview scrubbing).
  int frameOfSlot(int slotIndex) => titleFrames + slotIndex * framesPerSlot;

  String get dateRange {
    if (slots.isEmpty) return '';
    final a = slots.first.date, b = slots.last.date;
    return dayKey(a) == dayKey(b) ? prettyDay(a) : '${shortDay(a)}, ${a.year} – ${shortDay(b)}, ${b.year}';
  }
}

/// Builds the slot list for a building/view and date range.
List<TimelapseSlot> buildSlots(
  Project pr, {
  required String? buildingId,
  required String? viewId,
  required DateTime? from,
  required DateTime? to,
  required PhotosPerDate perDate,
}) {
  final slots = <TimelapseSlot>[];
  final dates = pr.datesFor(buildingId, viewId: viewId, type: MediaType.photo).where((d) {
    if (from != null && d.isBefore(from)) return false;
    if (to != null && d.isAfter(to)) return false;
    return true;
  }).toList();
  if (dates.isEmpty) return slots;
  final first = dates.first;
  for (final d in dates) {
    final caps = pr.capturesOn(d, buildingId, viewId: viewId);
    var added = false;
    for (final c in caps) {
      final b = pr.buildingById(c.buildingId);
      final v = b?.viewById(c.viewId);
      for (final m in c.photos.where((m) => m.isDisplayablePhoto)) {
        slots.add(TimelapseSlot(
          item: m,
          date: d,
          week: pr.weekNumber(d),
          dayNumber: DateTime.utc(d.year, d.month, d.day)
                  .difference(DateTime.utc(first.year, first.month, first.day))
                  .inDays +
              1,
          building: b?.name ?? '',
          view: v?.name ?? '',
          note: c.note,
        ));
        added = true;
        if (perDate == PhotosPerDate.first) break;
      }
      if (added && perDate == PhotosPerDate.first) break;
    }
  }
  return slots;
}
