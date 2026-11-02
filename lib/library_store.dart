import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

const _uuid = Uuid();
const appFolderName = 'Christman Site Progress';
const libraryFileName = 'library.json';

class ImportResult {
  ImportResult(this.imported, this.skipped);
  final int imported;
  final List<String> skipped;
}

/// Owns the library folder: one `library.json` plus every original file the
/// user imported. Originals are copied byte-for-byte and never re-encoded.
class LibraryStore extends ChangeNotifier {
  LibraryStore._(this.root, this.projects, this.deleted);

  Directory root;
  final List<Project> projects;

  /// Ids of everything deleted, so a stale copy from another computer can't
  /// bring it back when libraries are shared through Google Drive.
  final Set<String> deleted;

  Future<void> _saveChain = Future.value();
  String? _diskStamp;
  Timer? _poll;
  DateTime? lastSynced;
  int changesFromOthers = 0;

  // ---------------------------------------------------------------- open

  static Future<File> _configFile() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'config.json'));
  }

  static Future<Map<String, dynamic>> readConfig() async {
    try {
      final cfg = await _configFile();
      if (await cfg.exists()) {
        return Map<String, dynamic>.from(jsonDecode(await cfg.readAsString()) as Map);
      }
    } catch (_) {}
    return {};
  }

  static Future<void> setConfig(String key, Object? value) async {
    final map = await readConfig();
    map[key] = value;
    final cfg = await _configFile();
    await cfg.writeAsString(jsonEncode(map));
  }

  static Future<Directory> _defaultRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, appFolderName));
  }

  @visibleForTesting
  static Future<LibraryStore> openAt(Directory root) async {
    await root.create(recursive: true);
    final data = await _read(root);
    final store = LibraryStore._(root, data.projects, data.deleted);
    store._diskStamp = await _stamp(store._libraryFile);
    return store;
  }

  static Future<LibraryStore> open() async {
    Directory root = await _defaultRoot();
    final cfg = await readConfig();
    final custom = cfg['libraryPath'] as String?;
    if (custom != null && custom.isNotEmpty) root = Directory(custom);
    try {
      await root.create(recursive: true);
    } catch (_) {
      // e.g. the Google Drive letter isn't mounted yet: fall back to local.
      root = await _defaultRoot();
      await root.create(recursive: true);
    }
    final data = await _read(root);
    final store = LibraryStore._(root, data.projects, data.deleted);
    store._diskStamp = await _stamp(store._libraryFile);
    store.lastSynced = DateTime.now();
    var changed = store._migrate();
    for (final pr in store.projects) {
      if (await store._syncNames(pr)) changed = true;
    }
    if (changed) await store.save();
    store._poll = Timer.periodic(const Duration(seconds: 20), (_) => store.refreshFromDisk());
    return store;
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Makes sure every building has at least one view and every capture points
  /// at a real view. Returns true when anything changed.
  bool _migrate() {
    var changed = false;
    for (final pr in projects) {
      for (final b in pr.buildings) {
        final caps = pr.captures.where((c) => c.buildingId == b.id).toList();
        if (b.views.isEmpty) {
          if (caps.isEmpty) {
            b.views.addAll(defaultViewNames.map((n) => BuildingView(id: _uuid.v4(), name: n)));
          } else {
            b.views.add(BuildingView(id: _uuid.v4(), name: 'General'));
          }
          changed = true;
        }
        for (final c in caps) {
          if (b.viewById(c.viewId) == null) {
            c.viewId = b.views.first.id;
            changed = true;
          }
        }
      }
    }
    return changed;
  }

  static Future<({List<Project> projects, Set<String> deleted})> _read(Directory root) async {
    final f = File(p.join(root.path, libraryFileName));
    if (!await f.exists()) return (projects: <Project>[], deleted: <String>{});
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return (
        projects: ((j['projects'] as List?) ?? [])
            .map((e) => Project.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        deleted: ((j['deleted'] as List?) ?? []).map((e) => e.toString()).toSet(),
      );
    } catch (e) {
      // Keep a copy of the unreadable file so nothing is lost.
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await f.copy(p.join(root.path, 'library.unreadable.$stamp.json'));
      return (projects: <Project>[], deleted: <String>{});
    }
  }

  File get _libraryFile => File(p.join(root.path, libraryFileName));

  static Future<String?> _stamp(File f) async {
    try {
      final st = await f.stat();
      if (st.type == FileSystemEntityType.notFound) return null;
      return '${st.modified.millisecondsSinceEpoch}:${st.size}';
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------- sync

  /// Where the library lives, for display: "Google Drive", "OneDrive"…
  String? get cloudProvider => cloudProviderFor(root.path);

  static String? cloudProviderFor(String path) {
    final lower = path.toLowerCase();
    if (lower.contains('my drive') || lower.contains('google drive') || lower.contains('shared drives')) {
      return 'Google Drive';
    }
    if (lower.contains('onedrive')) return 'OneDrive';
    if (lower.contains('dropbox')) return 'Dropbox';
    if (lower.contains(r'\box\') || lower.endsWith(r'\box')) return 'Box';
    return null;
  }

  /// Picks up changes another computer saved into a shared (cloud) library.
  Future<bool> refreshFromDisk() {
    final done = Completer<bool>();
    _saveChain = _saveChain.then((_) async {
      var changed = false;
      try {
        final now = await _stamp(_libraryFile);
        if (now != null && now != _diskStamp) {
          final before = jsonEncode(projects.map((e) => e.toJson()).toList());
          await _mergeFromDisk(remoteWins: true);
          final after = jsonEncode(projects.map((e) => e.toJson()).toList());
          changed = before != after;
          if (changed) changesFromOthers++;
        }
        lastSynced = DateTime.now();
      } catch (e) {
        debugPrint('Refresh failed: $e');
      }
      if (changed) notifyListeners();
      done.complete(changed);
    });
    return done.future;
  }

  Future<void> _mergeFromDisk({required bool remoteWins}) async {
    final remote = await _read(root);
    deleted.addAll(remote.deleted);
    final merged = remoteWins
        ? _mergeLists(remote.projects, projects)
        : _mergeLists(projects, remote.projects);
    projects
      ..clear()
      ..addAll(merged);
    _migrate();
    _diskStamp = await _stamp(_libraryFile);
  }

  /// Union of two project lists. [primary] wins where both changed the same
  /// thing; anything in [deleted] is dropped.
  List<Project> _mergeLists(List<Project> primary, List<Project> secondary) {
    final out = <Project>[];
    final secById = {for (final x in secondary) x.id: x};
    final seen = <String>{};
    for (final a in primary) {
      if (deleted.contains(a.id)) continue;
      seen.add(a.id);
      final b = secById[a.id];
      out.add(_mergeProject(a, b));
    }
    for (final b in secondary) {
      if (!seen.contains(b.id) && !deleted.contains(b.id)) out.add(_mergeProject(b, null));
    }
    return out;
  }

  Project _mergeProject(Project a, Project? b) {
    final r = Project.fromJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
    if (b != null) {
      final bj = Project.fromJson(jsonDecode(jsonEncode(b.toJson())) as Map<String, dynamic>);
      for (final bb in bj.buildings) {
        final ab = r.buildingById(bb.id);
        if (ab == null) {
          r.buildings.add(bb);
        } else {
          for (final v in bb.views) {
            if (ab.viewById(v.id) == null) ab.views.add(v);
          }
        }
      }
      final capById = {for (final c in r.captures) c.id: c};
      for (final bc in bj.captures) {
        final ac = capById[bc.id];
        if (ac == null) {
          r.captures.add(bc);
          continue;
        }
        final itemById = {for (final m in ac.items) m.id: m};
        for (final bm in bc.items) {
          final am = itemById[bm.id];
          if (am == null) {
            ac.items.add(bm);
          } else if (am.relativePath != bm.relativePath &&
              !_existsRel(am.relativePath) &&
              _existsRel(bm.relativePath)) {
            am.relativePath = bm.relativePath;
          }
        }
      }
    }
    // Drop deleted things.
    r.buildings.removeWhere((x) => deleted.contains(x.id));
    for (final x in r.buildings) {
      x.views.removeWhere((v) => deleted.contains(v.id));
    }
    r.captures.removeWhere((c) => deleted.contains(c.id) || r.buildingById(c.buildingId) == null);
    final seenItems = <String>{};
    for (final c in r.captures) {
      c.items.removeWhere((m) => deleted.contains(m.id) || !seenItems.add(m.id));
    }
    // Two people may have added photos to the same building/view/date.
    final byKey = <String, Capture>{};
    for (final c in [...r.captures]) {
      final key = '${c.buildingId}|${c.viewId}|${dayKey(c.date)}';
      final first = byKey[key];
      if (first == null) {
        byKey[key] = c;
      } else {
        first.items.addAll(c.items);
        if (first.note.isEmpty) first.note = c.note;
        r.captures.remove(c);
      }
    }
    r.captures.removeWhere((c) => c.items.isEmpty);
    return r;
  }

  bool _existsRel(String rel) {
    try {
      return File(p.joinAll([root.path, ...rel.split('/')])).existsSync();
    } catch (_) {
      return false;
    }
  }

  void _tomb(Iterable<String> ids) => deleted.addAll(ids);

  // ---------------------------------------------------------------- save

  Future<void> save() {
    final rootPath = root.path;
    _saveChain = _saveChain.then((_) async {
      final target = File(p.join(rootPath, libraryFileName));
      // Someone else saved since we last looked: fold their changes in first.
      final now = await _stamp(target);
      if (now != null && now != _diskStamp && p.equals(rootPath, root.path)) {
        await _mergeFromDisk(remoteWins: false);
        notifyListeners();
      }
      final data = const JsonEncoder.withIndent('  ').convert({
        'app': appFolderName,
        'version': 2,
        'savedAt': DateTime.now().toIso8601String(),
        'savedBy': Platform.localHostname,
        'projects': projects.map((e) => e.toJson()).toList(),
        'deleted': deleted.toList(),
      });
      final tmp = File('${target.path}.${Platform.localHostname}.tmp');
      await tmp.writeAsString(data, flush: true);
      if (await target.exists()) {
        await target.copy(p.join(rootPath, 'library.backup.json'));
      }
      await tmp.rename(target.path);
      _diskStamp = await _stamp(target);
      lastSynced = DateTime.now();
    }).catchError((Object e) {
      debugPrint('Save failed: $e');
    });
    return _saveChain;
  }

  Future<void> _changed({Project? renameIn}) async {
    if (renameIn != null) await _syncNames(renameIn);
    notifyListeners();
    await save();
  }

  // ---------------------------------------------------------------- paths & names

  File fileFor(MediaItem m) =>
      File(p.joinAll([root.path, ...m.relativePath.split('/')]));

  File? coverFile(Project pr) =>
      pr.coverImage == null ? null : File(p.joinAll([root.path, ...pr.coverImage!.split('/')]));

  /// A name segment safe for Windows and readable: "Overall Site" → "Overall-Site".
  static String _seg(String s) {
    final t = s
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[.\s-]+$'), '');
    return t.isEmpty ? 'Unnamed' : t;
  }

  String projectFolder(Project pr) => 'projects/${_seg(pr.name)}_${pr.id.substring(0, 8)}';

  Directory projectDir(Project pr) => Directory(p.joinAll([root.path, ...projectFolder(pr).split('/')]));

  /// projects/Newcastle_1a2b3c4d/Hospital/Front/2026-11-02_Hospital_Front_01.jpg
  String expectedPath(Project pr, Capture c, MediaItem m, int number) {
    final b = pr.buildingById(c.buildingId);
    final v = b?.viewById(c.viewId);
    final bn = _seg(b?.name ?? 'Building');
    final vn = _seg(v?.name ?? 'View');
    final ext = p.extension(m.originalName).toLowerCase();
    final n = number.toString().padLeft(2, '0');
    return '${projectFolder(pr)}/$bn/$vn/${dayKey(c.date)}_${bn}_${vn}_$n$ext';
  }

  /// Renames stored files so every name says building, view and date. Files
  /// that aren't on this computer yet (still syncing) are left alone.
  Future<bool> _syncNames(Project pr) async {
    final moves = <(MediaItem, String)>[];
    for (final c in pr.captures) {
      for (var i = 0; i < c.items.length; i++) {
        final m = c.items[i];
        final want = expectedPath(pr, c, m, i + 1);
        if (m.relativePath != want) moves.add((m, want));
      }
    }
    var changed = false;
    if (moves.isNotEmpty) {
      // Two passes so files can swap names without colliding.
      final staged = <(MediaItem, String, File)>[];
      for (final (m, want) in moves) {
        final src = fileFor(m);
        try {
          if (!await src.exists()) continue;
          final dst = File(p.joinAll([root.path, ...want.split('/')]));
          await dst.parent.create(recursive: true);
          final tmp = File('${dst.path}.moving-${m.id.substring(0, 8)}');
          await src.rename(tmp.path);
          staged.add((m, want, tmp));
        } catch (e) {
          debugPrint('Rename failed for ${m.relativePath}: $e');
        }
      }
      for (final (m, want, tmp) in staged) {
        var rel = want;
        var dst = File(p.joinAll([root.path, ...rel.split('/')]));
        var k = 2;
        while (await dst.exists()) {
          final ext = p.extension(want);
          rel = '${want.substring(0, want.length - ext.length)} ($k)$ext';
          dst = File(p.joinAll([root.path, ...rel.split('/')]));
          k++;
        }
        try {
          await tmp.rename(dst.path);
          m.relativePath = rel;
          changed = true;
        } catch (e) {
          debugPrint('Rename failed: $e');
        }
      }
    }
    // Keep the cover image inside the project folder too.
    final cover = pr.coverImage;
    if (cover != null && !cover.startsWith('${projectFolder(pr)}/')) {
      final src = coverFile(pr)!;
      if (await src.exists()) {
        final rel = '${projectFolder(pr)}/cover${p.extension(cover).toLowerCase()}';
        final dst = File(p.joinAll([root.path, ...rel.split('/')]));
        await dst.parent.create(recursive: true);
        try {
          if (await dst.exists()) await dst.delete();
          await src.rename(dst.path);
          pr.coverImage = rel;
          changed = true;
        } catch (_) {}
      }
    }
    if (changed) await _removeEmptyDirs(Directory(p.join(root.path, 'projects')));
    return changed;
  }

  Future<void> _removeEmptyDirs(Directory dir) async {
    try {
      if (!await dir.exists()) return;
      final dirs = <Directory>[];
      await for (final e in dir.list(recursive: true)) {
        if (e is Directory) dirs.add(e);
      }
      dirs.sort((a, b) => b.path.length.compareTo(a.path.length));
      for (final d in dirs) {
        if (await d.list().isEmpty) await d.delete();
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------- projects

  Project? projectById(String id) {
    for (final pr in projects) {
      if (pr.id == id) return pr;
    }
    return null;
  }

  Future<Project> createProject({
    required String name,
    String location = '',
    String description = '',
    List<String> buildingNames = const [],
    List<String> viewNames = defaultViewNames,
  }) async {
    final names = buildingNames.where((n) => n.trim().isNotEmpty).toList();
    if (names.isEmpty) names.add('Overall Site');
    final pr = Project(
      id: _uuid.v4(),
      name: name.trim(),
      location: location.trim(),
      description: description.trim(),
      createdAt: DateTime.now(),
      buildings: names
          .map((n) => Building(id: _uuid.v4(), name: n.trim(), views: _makeViews(viewNames)))
          .toList(),
    );
    projects.add(pr);
    await _changed();
    return pr;
  }

  Future<void> updateProject(Project pr,
      {String? name, String? location, String? description}) async {
    if (name != null) pr.name = name.trim();
    if (location != null) pr.location = location.trim();
    if (description != null) pr.description = description.trim();
    await _changed(renameIn: pr);
  }

  /// Sets how the project card looks: newest drone photo, a chosen image
  /// (copied into the library) or an icon with a color.
  Future<void> setCover(Project pr, CoverMode mode, {String? imageSource, String? icon, int? color}) async {
    if (mode == CoverMode.image && imageSource != null) {
      final rel = '${projectFolder(pr)}/cover${p.extension(imageSource).toLowerCase()}';
      final dst = File(p.joinAll([root.path, ...rel.split('/')]));
      await dst.parent.create(recursive: true);
      final old = coverFile(pr);
      if (old != null && old.path != dst.path && await old.exists()) await old.delete();
      await File(imageSource).copy(dst.path);
      pr.coverImage = rel;
      PaintingBinding.instance.imageCache.evict(FileImage(dst));
    }
    if (icon != null) pr.coverIcon = icon;
    if (color != null) pr.coverColor = color;
    pr.coverMode = mode;
    await _changed();
  }

  Future<void> deleteProject(Project pr) async {
    projects.remove(pr);
    _tomb([pr.id]);
    await _changed();
    for (final dir in [projectDir(pr), Directory(p.join(root.path, 'projects', pr.id))]) {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------- buildings

  static List<BuildingView> _makeViews(List<String> names) {
    final clean = names.map((n) => n.trim()).where((n) => n.isNotEmpty).toList();
    if (clean.isEmpty) clean.add('General');
    return clean.map((n) => BuildingView(id: _uuid.v4(), name: n)).toList();
  }

  Future<Building> addBuilding(Project pr, String name,
      {List<String> viewNames = defaultViewNames}) async {
    final b = Building(id: _uuid.v4(), name: name.trim(), views: _makeViews(viewNames));
    pr.buildings.add(b);
    await _changed();
    return b;
  }

  Future<void> renameBuilding(Project pr, Building b, String name) async {
    b.name = name.trim();
    await _changed(renameIn: pr);
  }

  Future<void> deleteBuilding(Project pr, Building b) async {
    final caps = pr.captures.where((c) => c.buildingId == b.id).toList();
    final files = [for (final c in caps) ...c.items.map(fileFor)];
    _tomb([b.id, ...b.views.map((v) => v.id), for (final c in caps) ...[c.id, ...c.items.map((m) => m.id)]]);
    pr.captures.removeWhere((c) => c.buildingId == b.id);
    pr.buildings.remove(b);
    await _changed();
    await _deleteFiles(files);
  }

  // ---------------------------------------------------------------- views

  Future<BuildingView> addView(Project pr, Building b, String name) async {
    final v = BuildingView(id: _uuid.v4(), name: name.trim());
    b.views.add(v);
    await _changed();
    return v;
  }

  Future<void> renameView(Project pr, BuildingView v, String name) async {
    v.name = name.trim();
    await _changed(renameIn: pr);
  }

  Future<void> deleteView(Project pr, Building b, BuildingView v) async {
    final caps = pr.captures.where((c) => c.buildingId == b.id && c.viewId == v.id).toList();
    final files = [for (final c in caps) ...c.items.map(fileFor)];
    _tomb([v.id, for (final c in caps) ...[c.id, ...c.items.map((m) => m.id)]]);
    pr.captures.removeWhere(caps.contains);
    b.views.remove(v);
    await _changed();
    await _deleteFiles(files);
  }

  Future<void> moveView(Project pr, Building b, int oldIndex, int newIndex) async {
    final v = b.views.removeAt(oldIndex);
    b.views.insert(newIndex.clamp(0, b.views.length), v);
    await _changed();
  }

  Future<void> moveBuilding(Project pr, int oldIndex, int newIndex) async {
    final b = pr.buildings.removeAt(oldIndex);
    pr.buildings.insert(newIndex.clamp(0, pr.buildings.length), b);
    await _changed();
  }

  // ---------------------------------------------------------------- captures

  Capture? captureFor(Project pr, String buildingId, String viewId, DateTime day) {
    final key = dayKey(day);
    for (final c in pr.captures) {
      if (c.buildingId == buildingId && c.viewId == viewId && dayKey(c.date) == key) return c;
    }
    return null;
  }

  Capture _ensureCapture(Project pr, String buildingId, String viewId, DateTime day) {
    final existing = captureFor(pr, buildingId, viewId, day);
    if (existing != null) return existing;
    final c = Capture(
      id: _uuid.v4(),
      buildingId: buildingId,
      viewId: viewId,
      date: DateTime(day.year, day.month, day.day),
    );
    pr.captures.add(c);
    return c;
  }

  static String safeFileName(String name) => _safeName(name);

  static String _safeName(String name) =>
      name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');

  /// Copies each file into the library unchanged and records it.
  Future<ImportResult> importMedia(
    Project pr,
    String buildingId,
    String viewId,
    DateTime day,
    List<String> paths, {
    String? note,
    void Function(int done, int total, String current)? onProgress,
  }) async {
    final capture = _ensureCapture(pr, buildingId, viewId, day);
    if (note != null && note.trim().isNotEmpty) capture.note = note.trim();
    // Files land in an incoming folder, then get their coordinated names.
    final mediaDir = Directory(p.join(projectDir(pr).path, '_incoming'));
    await mediaDir.create(recursive: true);

    var imported = 0;
    final skipped = <String>[];
    for (var i = 0; i < paths.length; i++) {
      final src = File(paths[i]);
      final name = p.basename(src.path);
      onProgress?.call(i, paths.length, name);
      final type = mediaTypeForExtension(p.extension(name));
      if (type == null) {
        skipped.add('$name (not a photo or video)');
        continue;
      }
      try {
        final id = _uuid.v4();
        final stored = '$id${p.extension(name).toLowerCase()}';
        final dest = File(p.join(mediaDir.path, stored));
        await src.copy(dest.path);
        final srcLen = await src.length();
        final destLen = await dest.length();
        if (srcLen != destLen) {
          await dest.delete();
          skipped.add('$name (copy was incomplete)');
          continue;
        }
        capture.items.add(MediaItem(
          id: id,
          type: type,
          relativePath: '${projectFolder(pr)}/_incoming/$stored',
          originalName: name,
          sizeBytes: destLen,
          addedAt: DateTime.now(),
        ));
        imported++;
      } catch (e) {
        skipped.add('$name ($e)');
      }
    }
    onProgress?.call(paths.length, paths.length, '');
    if (capture.items.isEmpty) pr.captures.remove(capture);
    await _changed(renameIn: pr);
    return ImportResult(imported, skipped);
  }

  Capture? captureContaining(Project pr, MediaItem m) {
    for (final c in pr.captures) {
      if (c.items.contains(m)) return c;
    }
    return null;
  }

  Future<void> deleteMedia(Project pr, List<MediaItem> items) async {
    final files = items.map(fileFor).toList();
    _tomb(items.map((m) => m.id));
    for (final m in items) {
      final c = captureContaining(pr, m);
      c?.items.remove(m);
    }
    _tomb(pr.captures.where((c) => c.items.isEmpty).map((c) => c.id));
    pr.captures.removeWhere((c) => c.items.isEmpty);
    await _deleteFiles(files);
    await _changed(renameIn: pr);
  }

  Future<void> deleteDay(Project pr, DateTime day, String? buildingId, {String? viewId}) async {
    final caps = pr.capturesOn(day, buildingId, viewId: viewId);
    final files = [for (final c in caps) ...c.items.map(fileFor)];
    _tomb([for (final c in caps) ...[c.id, ...c.items.map((m) => m.id)]]);
    pr.captures.removeWhere(caps.contains);
    await _changed();
    await _deleteFiles(files);
  }

  Future<void> setNote(Project pr, Capture c, String note) async {
    c.note = note.trim();
    await _changed();
  }

  /// Moves every capture shown on [from] to [to] (merging with what's there).
  Future<void> changeDate(
      Project pr, DateTime from, DateTime to, String? buildingId, {String? viewId}) async {
    final caps = pr.capturesOn(from, buildingId, viewId: viewId);
    for (final c in caps) {
      final target = captureFor(pr, c.buildingId, c.viewId, to);
      if (target != null && target != c) {
        target.items.addAll(c.items);
        if (target.note.isEmpty) target.note = c.note;
        pr.captures.remove(c);
        _tomb([c.id]);
      } else {
        c.date = DateTime(to.year, to.month, to.day);
      }
    }
    await _changed(renameIn: pr);
  }

  /// Moves items to another building, view and/or date.
  Future<void> moveMedia(Project pr, List<MediaItem> items,
      {required String buildingId, required String viewId, required DateTime day}) async {
    final target = _ensureCapture(pr, buildingId, viewId, day);
    for (final m in items) {
      final c = captureContaining(pr, m);
      if (c == target) continue;
      c?.items.remove(m);
      target.items.add(m);
    }
    _tomb(pr.captures.where((c) => c.items.isEmpty).map((c) => c.id));
    pr.captures.removeWhere((c) => c.items.isEmpty);
    await _changed(renameIn: pr);
  }

  Future<void> _deleteFiles(List<File> files) async {
    for (final f in files) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------- export

  /// Copies originals out, named by building, view and date.
  Future<int> exportItems(List<MediaItem> items, String destDir) async {
    var n = 0;
    for (final m in items) {
      final base = _safeName(p.basename(m.relativePath.split('/').last));
      var target = File(p.join(destDir, base));
      var k = 1;
      while (await target.exists()) {
        final stem = p.basenameWithoutExtension(base);
        target = File(p.join(destDir, '$stem ($k)${p.extension(base)}'));
        k++;
      }
      await fileFor(m).copy(target.path);
      n++;
    }
    return n;
  }

  // ---------------------------------------------------------------- library location

  int get totalBytes => projects.fold(
      0, (s, pr) => s + pr.captures.fold(0, (s2, c) => s2 + c.items.fold(0, (s3, m) => s3 + m.sizeBytes)));

  /// Switches to [newPath]. If it already holds a library, opens it.
  /// Otherwise moves the current library there.
  Future<String> changeLibraryFolder(String newPath,
      {void Function(int done, int total)? onProgress}) async {
    final newRoot = Directory(newPath);
    if (p.equals(newRoot.path, root.path)) return 'That is already the library folder.';
    await newRoot.create(recursive: true);
    final existing = File(p.join(newRoot.path, libraryFileName));
    String message;
    if (await existing.exists()) {
      await _saveChain;
      final loaded = await _read(newRoot);
      projects
        ..clear()
        ..addAll(loaded.projects);
      deleted
        ..clear()
        ..addAll(loaded.deleted);
      _migrate();
      root = newRoot;
      _diskStamp = await _stamp(_libraryFile);
      message = 'Opened the shared library in that folder (${projects.length} projects).';
    } else {
      await _saveChain;
      final oldRoot = root;
      final files = <File>[];
      final projDir = Directory(p.join(oldRoot.path, 'projects'));
      if (await projDir.exists()) {
        await for (final e in projDir.list(recursive: true)) {
          if (e is File) files.add(e);
        }
      }
      for (var i = 0; i < files.length; i++) {
        onProgress?.call(i, files.length);
        final rel = p.relative(files[i].path, from: oldRoot.path);
        final dest = File(p.join(newRoot.path, rel));
        await dest.parent.create(recursive: true);
        await files[i].copy(dest.path);
      }
      onProgress?.call(files.length, files.length);
      root = newRoot;
      _diskStamp = null;
      await save();
      await _saveChain;
      // Copy succeeded; remove the old copies.
      if (await projDir.exists()) await projDir.delete(recursive: true);
      for (final name in [libraryFileName, 'library.backup.json']) {
        final f = File(p.join(oldRoot.path, name));
        if (await f.exists()) await f.delete();
      }
      message = 'Moved ${files.length} files to the new folder.';
    }
    root = newRoot;
    await setConfig('libraryPath', newRoot.path);
    notifyListeners();
    return message;
  }
}
