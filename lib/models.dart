import 'package:intl/intl.dart';

enum MediaType { photo, video }

const photoExtensions = {
  '.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif', '.tif', '.tiff', '.heic', '.dng'
};
const videoExtensions = {
  '.mp4', '.mov', '.m4v', '.avi', '.mkv', '.wmv', '.webm', '.mts', '.m2ts', '.3gp'
};

/// Photo formats Flutter can draw directly. Others (TIFF, HEIC, DNG) are still
/// stored as originals, but shown as a file tile instead of a picture.
const displayablePhotoExtensions = {
  '.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif'
};

MediaType? mediaTypeForExtension(String ext) {
  final e = ext.toLowerCase();
  if (photoExtensions.contains(e)) return MediaType.photo;
  if (videoExtensions.contains(e)) return MediaType.video;
  return null;
}

/// Dates are stored as plain calendar days (no time, no time zone).
String dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
DateTime parseDay(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

String prettyDay(DateTime d) => DateFormat('EEE, MMM d, yyyy').format(d);
String shortDay(DateTime d) => DateFormat('MMM d').format(d);

String prettySize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  double v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
}

class Building {
  Building({required this.id, required this.name});
  final String id;
  String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory Building.fromJson(Map<String, dynamic> j) =>
      Building(id: j['id'] as String, name: j['name'] as String);
}

class MediaItem {
  MediaItem({
    required this.id,
    required this.type,
    required this.relativePath,
    required this.originalName,
    required this.sizeBytes,
    required this.addedAt,
  });

  final String id;
  final MediaType type;

  /// Path inside the library folder, always with forward slashes.
  final String relativePath;
  final String originalName;
  final int sizeBytes;
  final DateTime addedAt;

  String get extension {
    final i = originalName.lastIndexOf('.');
    return i < 0 ? '' : originalName.substring(i).toLowerCase();
  }

  bool get isDisplayablePhoto =>
      type == MediaType.photo && displayablePhotoExtensions.contains(extension);

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'path': relativePath,
        'originalName': originalName,
        'size': sizeBytes,
        'addedAt': addedAt.toIso8601String(),
      };

  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
        id: j['id'] as String,
        type: MediaType.values.byName(j['type'] as String),
        relativePath: j['path'] as String,
        originalName: j['originalName'] as String,
        sizeBytes: (j['size'] as num?)?.toInt() ?? 0,
        addedAt: DateTime.tryParse(j['addedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Everything captured for one building on one day.
class Capture {
  Capture({
    required this.id,
    required this.buildingId,
    required this.date,
    this.note = '',
    List<MediaItem>? items,
  }) : items = items ?? [];

  final String id;
  String buildingId;
  DateTime date;
  String note;
  final List<MediaItem> items;

  List<MediaItem> get photos =>
      items.where((m) => m.type == MediaType.photo).toList();
  List<MediaItem> get videos =>
      items.where((m) => m.type == MediaType.video).toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'buildingId': buildingId,
        'date': dayKey(date),
        'note': note,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory Capture.fromJson(Map<String, dynamic> j) => Capture(
        id: j['id'] as String,
        buildingId: j['buildingId'] as String,
        date: parseDay(j['date'] as String),
        note: j['note'] as String? ?? '',
        items: ((j['items'] as List?) ?? [])
            .map((e) => MediaItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class Project {
  Project({
    required this.id,
    required this.name,
    this.location = '',
    this.description = '',
    required this.createdAt,
    List<Building>? buildings,
    List<Capture>? captures,
  })  : buildings = buildings ?? [],
        captures = captures ?? [];

  final String id;
  String name;
  String location;
  String description;
  final DateTime createdAt;
  final List<Building> buildings;
  final List<Capture> captures;

  Building? buildingById(String id) {
    for (final b in buildings) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// Distinct capture days, oldest first. [buildingId] null = all buildings.
  List<DateTime> datesFor(String? buildingId, {MediaType? type}) {
    final set = <String>{};
    for (final c in captures) {
      if (buildingId != null && c.buildingId != buildingId) continue;
      if (type != null && !c.items.any((m) => m.type == type)) continue;
      set.add(dayKey(c.date));
    }
    final list = set.map(parseDay).toList()..sort();
    return list;
  }

  List<Capture> capturesOn(DateTime day, String? buildingId) {
    final key = dayKey(day);
    final list = captures
        .where((c) =>
            dayKey(c.date) == key &&
            (buildingId == null || c.buildingId == buildingId))
        .toList();
    list.sort((a, b) => buildingIndex(a.buildingId).compareTo(buildingIndex(b.buildingId)));
    return list;
  }

  int buildingIndex(String id) {
    final i = buildings.indexWhere((b) => b.id == id);
    return i < 0 ? 1 << 30 : i;
  }

  List<MediaItem> mediaOn(DateTime day, String? buildingId, MediaType type) {
    final out = <MediaItem>[];
    for (final c in capturesOn(day, buildingId)) {
      out.addAll(c.items.where((m) => m.type == type));
    }
    return out;
  }

  /// Week number counted from the first capture of the project (week 1).
  int weekNumber(DateTime day) {
    if (captures.isEmpty) return 1;
    final first = captures.map((c) => c.date).reduce((a, b) => a.isBefore(b) ? a : b);
    final diff = DateTime.utc(day.year, day.month, day.day)
        .difference(DateTime.utc(first.year, first.month, first.day))
        .inDays;
    return diff < 0 ? 1 : diff ~/ 7 + 1;
  }

  MediaItem? get coverPhoto {
    final sorted = [...captures]..sort((a, b) => b.date.compareTo(a.date));
    for (final c in sorted) {
      for (final m in c.items) {
        if (m.isDisplayablePhoto) return m;
      }
    }
    return null;
  }

  DateTime? get lastCaptureDate {
    if (captures.isEmpty) return null;
    return captures.map((c) => c.date).reduce((a, b) => a.isAfter(b) ? a : b);
  }

  int get photoCount =>
      captures.fold(0, (s, c) => s + c.items.where((m) => m.type == MediaType.photo).length);
  int get videoCount =>
      captures.fold(0, (s, c) => s + c.items.where((m) => m.type == MediaType.video).length);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'location': location,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
        'buildings': buildings.map((e) => e.toJson()).toList(),
        'captures': captures.map((e) => e.toJson()).toList(),
      };

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as String,
        name: j['name'] as String,
        location: j['location'] as String? ?? '',
        description: j['description'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        buildings: ((j['buildings'] as List?) ?? [])
            .map((e) => Building.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        captures: ((j['captures'] as List?) ?? [])
            .map((e) => Capture.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}
