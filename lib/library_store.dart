import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
  LibraryStore._(this.root, this.projects);

  Directory root;
  final List<Project> projects;
  Future<void> _saveChain = Future.value();

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

  static Future<LibraryStore> open() async {
    Directory root = await _defaultRoot();
    final cfg = await readConfig();
    final custom = cfg['libraryPath'] as String?;
    if (custom != null && custom.isNotEmpty) root = Directory(custom);
    await root.create(recursive: true);
    final projects = await _readProjects(root);
    return LibraryStore._(root, projects);
  }

  static Future<List<Project>> _readProjects(Directory root) async {
    final f = File(p.join(root.path, libraryFileName));
    if (!await f.exists()) return [];
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return ((j['projects'] as List?) ?? [])
          .map((e) => Project.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      // Keep a copy of the unreadable file so nothing is lost.
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await f.copy(p.join(root.path, 'library.unreadable.$stamp.json'));
      return [];
    }
  }

  // ---------------------------------------------------------------- save

  Future<void> save() {
    final data = const JsonEncoder.withIndent('  ').convert({
      'app': appFolderName,
      'version': 1,
      'savedAt': DateTime.now().toIso8601String(),
      'projects': projects.map((e) => e.toJson()).toList(),
    });
    final rootPath = root.path;
    _saveChain = _saveChain.then((_) async {
      final target = File(p.join(rootPath, libraryFileName));
      final tmp = File('${target.path}.tmp');
      await tmp.writeAsString(data, flush: true);
      if (await target.exists()) {
        await target.copy(p.join(rootPath, 'library.backup.json'));
      }
      await tmp.rename(target.path);
    }).catchError((Object e) {
      debugPrint('Save failed: $e');
    });
    return _saveChain;
  }

  Future<void> _changed() async {
    notifyListeners();
    await save();
  }

  // ---------------------------------------------------------------- paths

  File fileFor(MediaItem m) =>
      File(p.joinAll([root.path, ...m.relativePath.split('/')]));

  Directory projectDir(Project pr) =>
      Directory(p.join(root.path, 'projects', pr.id));

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
  }) async {
    final names = buildingNames.where((n) => n.trim().isNotEmpty).toList();
    if (names.isEmpty) names.add('Overall Site');
    final pr = Project(
      id: _uuid.v4(),
      name: name.trim(),
      location: location.trim(),
      description: description.trim(),
      createdAt: DateTime.now(),
      buildings: names.map((n) => Building(id: _uuid.v4(), name: n.trim())).toList(),
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
    await _changed();
  }

  Future<void> deleteProject(Project pr) async {
    projects.remove(pr);
    await _changed();
    final dir = projectDir(pr);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  // ---------------------------------------------------------------- buildings

  Future<Building> addBuilding(Project pr, String name) async {
    final b = Building(id: _uuid.v4(), name: name.trim());
    pr.buildings.add(b);
    await _changed();
    return b;
  }

  Future<void> renameBuilding(Project pr, Building b, String name) async {
    b.name = name.trim();
    await _changed();
  }

  Future<void> deleteBuilding(Project pr, Building b) async {
    final caps = pr.captures.where((c) => c.buildingId == b.id).toList();
    final files = [for (final c in caps) ...c.items.map(fileFor)];
    pr.captures.removeWhere((c) => c.buildingId == b.id);
    pr.buildings.remove(b);
    await _changed();
    await _deleteFiles(files);
  }

  Future<void> moveBuilding(Project pr, int oldIndex, int newIndex) async {
    final b = pr.buildings.removeAt(oldIndex);
    pr.buildings.insert(newIndex.clamp(0, pr.buildings.length), b);
    await _changed();
  }

  // ---------------------------------------------------------------- captures

  Capture? captureFor(Project pr, String buildingId, DateTime day) {
    final key = dayKey(day);
    for (final c in pr.captures) {
      if (c.buildingId == buildingId && dayKey(c.date) == key) return c;
    }
    return null;
  }

  Capture _ensureCapture(Project pr, String buildingId, DateTime day) {
    final existing = captureFor(pr, buildingId, day);
    if (existing != null) return existing;
    final c = Capture(
      id: _uuid.v4(),
      buildingId: buildingId,
      date: DateTime(day.year, day.month, day.day),
    );
    pr.captures.add(c);
    return c;
  }

  static String _safeName(String name) =>
      name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');

  /// Copies each file into the library unchanged and records it.
  Future<ImportResult> importMedia(
    Project pr,
    String buildingId,
    DateTime day,
    List<String> paths, {
    String? note,
    void Function(int done, int total, String current)? onProgress,
  }) async {
    final capture = _ensureCapture(pr, buildingId, day);
    if (note != null && note.trim().isNotEmpty) capture.note = note.trim();
    final mediaDir = Directory(p.join(projectDir(pr).path, 'media'));
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
        final stored = '${id.substring(0, 8)}_${_safeName(name)}';
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
          relativePath: 'projects/${pr.id}/media/$stored',
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
    await _changed();
    return ImportResult(imported, skipped);
  }

  Capture? captureContaining(Project pr, MediaItem m) {
    for (final c in pr.captures) {
      if (c.items.contains(m)) return c;
    }
    return null;
  }

  Future<void> deleteMedia(Project pr, List<MediaItem> items) async {
    for (final m in items) {
      final c = captureContaining(pr, m);
      c?.items.remove(m);
    }
    pr.captures.removeWhere((c) => c.items.isEmpty);
    await _changed();
    await _deleteFiles(items.map(fileFor).toList());
  }

  Future<void> deleteDay(Project pr, DateTime day, String? buildingId) async {
    final caps = pr.capturesOn(day, buildingId);
    final files = [for (final c in caps) ...c.items.map(fileFor)];
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
      Project pr, DateTime from, DateTime to, String? buildingId) async {
    final caps = pr.capturesOn(from, buildingId);
    for (final c in caps) {
      final target = captureFor(pr, c.buildingId, to);
      if (target != null && target != c) {
        target.items.addAll(c.items);
        if (target.note.isEmpty) target.note = c.note;
        pr.captures.remove(c);
      } else {
        c.date = DateTime(to.year, to.month, to.day);
      }
    }
    await _changed();
  }

  /// Moves items to another building and/or date.
  Future<void> moveMedia(Project pr, List<MediaItem> items,
      {required String buildingId, required DateTime day}) async {
    final target = _ensureCapture(pr, buildingId, day);
    for (final m in items) {
      final c = captureContaining(pr, m);
      if (c == target) continue;
      c?.items.remove(m);
      target.items.add(m);
    }
    pr.captures.removeWhere((c) => c.items.isEmpty);
    await _changed();
  }

  Future<void> _deleteFiles(List<File> files) async {
    for (final f in files) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------- export

  /// Copies originals out with their original file names.
  Future<int> exportItems(List<MediaItem> items, String destDir,
      {String prefix = ''}) async {
    var n = 0;
    for (final m in items) {
      final base = _safeName('$prefix${m.originalName}');
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
      final loaded = await _readProjects(newRoot);
      projects
        ..clear()
        ..addAll(loaded);
      message = 'Opened the existing library in that folder.';
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
