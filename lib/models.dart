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

/// Default camera positions offered for a new building.
const defaultViewNames = ['Front', 'Back', 'Side', '45° angle'];

/// A repeatable camera position for a building (Front, Back, 45°…). Keeping
/// the same angle and elevation every week makes progress easy to compare.
class BuildingView {
  BuildingView({required this.id, required this.name});
  final String id;
  String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory BuildingView.fromJson(Map<String, dynamic> j) =>
      BuildingView(id: j['id'] as String, name: j['name'] as String);
}

class Building {
  Building({required this.id, required this.name, List<BuildingView>? views})
      : views = views ?? [];
  final String id;
  String name;
  final List<BuildingView> views;

  BuildingView? viewById(String? id) {
    for (final v in views) {
      if (v.id == id) return v;
    }
    return null;
  }

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'views': views.map((v) => v.toJson()).toList()};
  factory Building.fromJson(Map<String, dynamic> j) => Building(
        id: j['id'] as String,
        name: j['name'] as String,
        views: ((j['views'] as List?) ?? [])
            .map((e) => BuildingView.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class MediaItem {
  MediaItem({
    required this.id,
    required this.type,
    required this.relativePath,
    required this.originalName,
    required this.sizeBytes,
    required this.addedAt,
    this.addedBy,
    this.addedById,
    this.seq,
  });

  final String id;
  final MediaType type;

  /// Who added it (name and user id), for shared libraries.
  final String? addedBy;
  final String? addedById;

  /// Number within its capture, fixed when added so names never shuffle
  /// when other photos are deleted.
  int? seq;

  /// Path inside the library folder, always with forward slashes.
  String relativePath;
  final String originalName;
  final int sizeBytes;
  final DateTime addedAt;

  /// The coordinated name in the library, e.g. 2026-11-02_Hospital_Front_01.jpg
  String get fileName => relativePath.split('/').last;

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
        if (addedBy != null) 'addedBy': addedBy,
        if (addedById != null) 'addedById': addedById,
        if (seq != null) 'seq': seq,
      };

  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
        id: j['id'] as String,
        type: MediaType.values.byName(j['type'] as String),
        relativePath: j['path'] as String,
        originalName: j['originalName'] as String,
        sizeBytes: (j['size'] as num?)?.toInt() ?? 0,
        addedAt: DateTime.tryParse(j['addedAt'] as String? ?? '') ?? DateTime.now(),
        addedBy: j['addedBy'] as String?,
        addedById: j['addedById'] as String?,
        seq: (j['seq'] as num?)?.toInt(),
      );
}

/// Everything captured for one building on one day.
class Capture {
  Capture({
    required this.id,
    required this.buildingId,
    required this.viewId,
    required this.date,
    this.note = '',
    List<MediaItem>? items,
  }) : items = items ?? [];

  final String id;
  String buildingId;
  String viewId;
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
        'viewId': viewId,
        'date': dayKey(date),
        'note': note,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory Capture.fromJson(Map<String, dynamic> j) => Capture(
        id: j['id'] as String,
        buildingId: j['buildingId'] as String,
        viewId: j['viewId'] as String? ?? '',
        date: parseDay(j['date'] as String),
        note: j['note'] as String? ?? '',
        items: ((j['items'] as List?) ?? [])
            .map((e) => MediaItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

enum CoverMode { auto, image, icon }

class Project {
  Project({
    required this.id,
    required this.name,
    this.location = '',
    this.description = '',
    required this.createdAt,
    List<Building>? buildings,
    List<Capture>? captures,
    this.coverMode = CoverMode.auto,
    this.coverImage,
    this.coverIcon = 'apartment',
    this.coverColor = 0xFFE8742A,
  })  : buildings = buildings ?? [],
        captures = captures ?? [];

  /// How the project card looks on the home page.
  CoverMode coverMode;
  String? coverImage; // relative path inside the library
  String coverIcon; // key in projectIcons (see widgets/project_cover.dart)
  int coverColor;

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

  bool _matches(Capture c, String? buildingId, String? viewId) =>
      (buildingId == null || c.buildingId == buildingId) &&
      (viewId == null || c.viewId == viewId);

  /// Distinct capture days, oldest first. [buildingId]/[viewId] null = all.
  List<DateTime> datesFor(String? buildingId, {String? viewId, MediaType? type}) {
    final set = <String>{};
    for (final c in captures) {
      if (!_matches(c, buildingId, viewId)) continue;
      if (type != null && !c.items.any((m) => m.type == type)) continue;
      set.add(dayKey(c.date));
    }
    final list = set.map(parseDay).toList()..sort();
    return list;
  }

  List<Capture> capturesOn(DateTime day, String? buildingId, {String? viewId}) {
    final key = dayKey(day);
    final list = captures
        .where((c) => dayKey(c.date) == key && _matches(c, buildingId, viewId))
        .toList();
    list.sort((a, b) {
      final byBuilding = buildingIndex(a.buildingId).compareTo(buildingIndex(b.buildingId));
      if (byBuilding != 0) return byBuilding;
      return viewIndex(a).compareTo(viewIndex(b));
    });
    return list;
  }

  int viewIndex(Capture c) {
    final b = buildingById(c.buildingId);
    final i = b?.views.indexWhere((v) => v.id == c.viewId) ?? -1;
    return i < 0 ? 1 << 30 : i;
  }

  /// "Hospital · Front"
  String labelFor(Capture c) {
    final b = buildingById(c.buildingId);
    final v = b?.viewById(c.viewId);
    return [if (b != null) b.name, if (v != null) v.name].join(' · ');
  }

  int buildingIndex(String id) {
    final i = buildings.indexWhere((b) => b.id == id);
    return i < 0 ? 1 << 30 : i;
  }

  List<MediaItem> mediaOn(DateTime day, String? buildingId, MediaType type, {String? viewId}) {
    final out = <MediaItem>[];
    for (final c in capturesOn(day, buildingId, viewId: viewId)) {
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

  DateTime? get firstCaptureDate {
    if (captures.isEmpty) return null;
    return captures.map((c) => c.date).reduce((a, b) => a.isBefore(b) ? a : b);
  }

  /// Number of distinct capture dates across the project.
  int get captureDateCount => captures.map((c) => dayKey(c.date)).toSet().length;

  int get totalBytes =>
      captures.fold(0, (s, c) => s + c.items.fold(0, (s2, m) => s2 + m.sizeBytes));

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
        'coverMode': coverMode.name,
        if (coverImage != null) 'coverImage': coverImage,
        'coverIcon': coverIcon,
        'coverColor': coverColor,
        'buildings': buildings.map((e) => e.toJson()).toList(),
        'captures': captures.map((e) => e.toJson()).toList(),
      };

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as String,
        name: j['name'] as String,
        location: j['location'] as String? ?? '',
        description: j['description'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        coverMode: CoverMode.values.firstWhere((m) => m.name == j['coverMode'], orElse: () => CoverMode.auto),
        coverImage: j['coverImage'] as String?,
        coverIcon: j['coverIcon'] as String? ?? 'apartment',
        coverColor: (j['coverColor'] as num?)?.toInt() ?? 0xFFE8742A,
        buildings: ((j['buildings'] as List?) ?? [])
            .map((e) => Building.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        captures: ((j['captures'] as List?) ?? [])
            .map((e) => Capture.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}


/// The person using this copy of the app.
class AppUser {
  const AppUser({required this.id, required this.name});
  final String id;
  final String name;

  String get initials => initialsOf(name);
}

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '';
  if (parts.length == 1) return parts.first.substring(0, parts.first.length.clamp(0, 2)).toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

/// One line in the team activity feed.
class Activity {
  Activity({
    required this.id,
    required this.at,
    required this.userId,
    required this.userName,
    required this.text,
    this.projectId,
    this.projectName,
  });

  final String id;
  final DateTime at;
  final String userId;
  final String userName;
  final String text;
  final String? projectId;
  final String? projectName;

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.toUtc().toIso8601String(),
        'userId': userId,
        'userName': userName,
        'text': text,
        if (projectId != null) 'projectId': projectId,
        if (projectName != null) 'projectName': projectName,
      };

  static Activity? tryParse(Map<String, dynamic> j) {
    try {
      return Activity(
        id: j['id'] as String,
        at: DateTime.parse(j['at'] as String).toLocal(),
        userId: j['userId'] as String,
        userName: j['userName'] as String? ?? 'Someone',
        text: j['text'] as String,
        projectId: j['projectId'] as String?,
        projectName: j['projectName'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// A person who uses the shared library (one file per person in team/).
class Member {
  Member({
    required this.id,
    required this.name,
    required this.lastSeen,
    this.computer = '',
    this.readOnly = false,
  });

  final String id;
  final String name;
  final DateTime lastSeen;
  final String computer;
  final bool readOnly;

  String get initials => initialsOf(name);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lastSeen': lastSeen.toUtc().toIso8601String(),
        'computer': computer,
        'readOnly': readOnly,
      };

  static Member? tryParse(Map<String, dynamic> j) {
    try {
      return Member(
        id: j['id'] as String,
        name: j['name'] as String,
        lastSeen: DateTime.parse(j['lastSeen'] as String).toLocal(),
        computer: j['computer'] as String? ?? '',
        readOnly: j['readOnly'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}
