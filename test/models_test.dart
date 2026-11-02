import 'package:christman_site_progress/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('timeline dates, week numbers and JSON round-trip', () {
    final p = Project(
      id: 'p1',
      name: 'Newcastle',
      createdAt: DateTime(2026, 1, 1),
      buildings: [Building(id: 'b1', name: 'Tower'), Building(id: 'b2', name: 'Garage')],
    );
    MediaItem item(String id, MediaType t) => MediaItem(
          id: id,
          type: t,
          relativePath: 'projects/p1/media/$id.jpg',
          originalName: '$id.jpg',
          sizeBytes: 10,
          addedAt: DateTime(2026, 1, 1),
        );
    p.captures.addAll([
      Capture(id: 'c1', buildingId: 'b1', date: DateTime(2026, 10, 5), items: [item('a', MediaType.photo)]),
      Capture(id: 'c2', buildingId: 'b2', date: DateTime(2026, 10, 12), items: [item('b', MediaType.video)]),
      Capture(id: 'c3', buildingId: 'b1', date: DateTime(2026, 10, 19), items: [item('c', MediaType.photo)]),
    ]);

    expect(p.datesFor(null).length, 3);
    expect(p.datesFor('b1').length, 2);
    expect(p.datesFor(null, type: MediaType.video), [DateTime(2026, 10, 12)]);
    expect(p.weekNumber(DateTime(2026, 10, 5)), 1);
    expect(p.weekNumber(DateTime(2026, 10, 19)), 3);
    expect(p.mediaOn(DateTime(2026, 10, 19), null, MediaType.photo).single.id, 'c');

    final back = Project.fromJson(p.toJson());
    expect(back.captures.length, 3);
    expect(back.captures.first.items.first.relativePath, 'projects/p1/media/a.jpg');
    expect(dayKey(back.captures.last.date), '2026-10-19');
  });
}
