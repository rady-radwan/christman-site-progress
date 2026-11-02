import 'dart:convert';
import 'dart:io';

import 'package:christman_site_progress/library_store.dart';
import 'package:christman_site_progress/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late Directory src;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('csp_lib');
    src = await Directory.systemTemp.createTemp('csp_src');
    for (final n in ['DJI_0001.JPG', 'DJI_0002.JPG', 'DJI_0003.MP4']) {
      await File(p.join(src.path, n)).writeAsBytes(List.filled(1000 + n.length, 7));
    }
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
    await src.delete(recursive: true);
  });

  test('imports get coordinated names and follow renames', () async {
    final store = await LibraryStore.openAt(tmp);
    final pr = await store.createProject(name: 'Newcastle Medical', buildingNames: ['Overall Site'], viewNames: ['Front', '45° angle']);
    final b = pr.buildings.first;
    final front = b.views.first;
    final r = await store.importMedia(pr, b.id, front.id, DateTime(2026, 11, 2),
        [for (final n in ['DJI_0001.JPG', 'DJI_0002.JPG', 'DJI_0003.MP4']) p.join(src.path, n)]);
    expect(r.imported, 3);
    final names = pr.captures.single.items.map((m) => m.fileName).toList();
    expect(names, [
      '2026-11-02_Overall-Site_Front_01.jpg',
      '2026-11-02_Overall-Site_Front_02.jpg',
      '2026-11-02_Overall-Site_Front_03.mp4',
    ]);
    for (final m in pr.captures.single.items) {
      expect(await store.fileFor(m).exists(), isTrue, reason: m.relativePath);
      expect(m.relativePath, startsWith('projects/Newcastle-Medical_'));
    }
    expect(pr.captures.single.items.first.originalName, 'DJI_0001.JPG');

    await store.renameBuilding(pr, b, 'Hospital');
    final first = pr.captures.single.items.first;
    expect(first.fileName, '2026-11-02_Hospital_Front_01.jpg');
    expect(await store.fileFor(first).exists(), isTrue);

    await store.deleteMedia(pr, [first]);
    expect(pr.captures.single.items.first.fileName, '2026-11-02_Hospital_Front_01.jpg');
    expect(await store.fileFor(pr.captures.single.items.first).exists(), isTrue);

    await store.changeDate(pr, DateTime(2026, 11, 2), DateTime(2026, 11, 9), b.id);
    expect(pr.captures.single.items.first.fileName, '2026-11-09_Hospital_Front_01.jpg');
    expect(await store.fileFor(pr.captures.single.items.first).exists(), isTrue);
  });

  test('changes from another computer are merged, deletions stick', () async {
    final store = await LibraryStore.openAt(tmp);
    final pr = await store.createProject(name: 'Site A');
    final gone = await store.createProject(name: 'Old');
    await store.deleteProject(gone);

    // Another PC (stale: still has "Old", never saw our latest) adds a project.
    final libFile = File(p.join(tmp.path, libraryFileName));
    final j = jsonDecode(await libFile.readAsString()) as Map<String, dynamic>;
    final other = Project(id: 'other-pc-project-000', name: 'From Drive', createdAt: DateTime(2026));
    j['projects'] = [...(j['projects'] as List), other.toJson(), gone.toJson()];
    j['deleted'] = <String>[];
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await libFile.writeAsString(jsonEncode(j));

    final changed = await store.refreshFromDisk();
    expect(changed, isTrue);
    final names = store.projects.map((x) => x.name).toSet();
    expect(names, containsAll(['Site A', 'From Drive']));
    expect(names.contains('Old'), isFalse);

    // Our next save keeps both and writes the tombstone back.
    await store.updateProject(store.projectById(pr.id)!, location: 'Newcastle, OK');
    final saved = jsonDecode(await libFile.readAsString()) as Map<String, dynamic>;
    expect((saved['projects'] as List).length, 2);
    expect((saved['deleted'] as List), contains(gone.id));
  });
}
