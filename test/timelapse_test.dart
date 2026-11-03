import 'package:christman_site_progress/models.dart';
import 'package:christman_site_progress/timelapse/timelapse_plan.dart';
import 'package:christman_site_progress/timelapse/timelapse_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Project project() {
    MediaItem photo(String id) => MediaItem(
          id: id,
          type: MediaType.photo,
          relativePath: 'projects/p/media/$id.jpg',
          originalName: '$id.jpg',
          sizeBytes: 1,
          addedAt: DateTime(2026),
        );
    return Project(
      id: 'p',
      name: 'Newcastle',
      createdAt: DateTime(2026),
      buildings: [Building(id: 'b', name: 'Hospital', views: [BuildingView(id: 'f', name: 'Front')])],
      captures: [
        Capture(id: '1', buildingId: 'b', viewId: 'f', date: DateTime(2026, 10, 1), items: [photo('a'), photo('a2')], note: 'Grading'),
        Capture(id: '2', buildingId: 'b', viewId: 'f', date: DateTime(2026, 10, 8), items: [photo('b')]),
        Capture(id: '3', buildingId: 'b', viewId: 'f', date: DateTime(2026, 10, 15), items: [photo('c')]),
      ],
    );
  }

  test('slots: first photo per date, labels and day counter', () {
    final slots = buildSlots(project(),
        buildingId: 'b', viewId: 'f', from: null, to: null, perDate: PhotosPerDate.first);
    expect(slots.map((s) => s.item.id), ['a', 'b', 'c']);
    expect(slots.last.dayNumber, 15);
    expect(slots.first.building, 'Hospital');
    expect(slots.first.view, 'Front');
    expect(slots.first.note, 'Grading');
    final all = buildSlots(project(),
        buildingId: 'b', viewId: null, from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 8), perDate: PhotosPerDate.all);
    expect(all.map((s) => s.item.id), ['a', 'a2', 'b']);
  });

  test('frame schedule: title, cross-fades and hold', () {
    final s = TimelapseSettings()
      ..fps = 10
      ..secondsPerPhoto = 1
      ..transitionSeconds = 0.3
      ..titleCard = true
      ..titleSeconds = 2
      ..endHoldSeconds = 1;
    final plan = TimelapsePlan(
      settings: s,
      slots: buildSlots(project(), buildingId: 'b', viewId: 'f', from: null, to: null, perDate: PhotosPerDate.first),
      projectName: 'Newcastle',
      scopeLabel: 'Hospital · Front',
    );
    expect(plan.totalFrames, 20 + 30 + 10);
    expect(plan.at(0).isTitle, isTrue);
    expect(plan.at(20).slot, 0);
    expect(plan.at(20).nextSlot, isNull);
    expect(plan.at(29).nextSlot, 1); // fading into photo 2
    expect(plan.at(49).nextSlot, isNull); // last photo never fades out
    expect(plan.at(55).global, 1);
    expect(plan.at(59).slot, 2);
    s.transition = PhotoTransition.cut;
    expect(plan.at(29).nextSlot, isNull);
  });

  test('custom camera keeps moving across weeks without jumping', () {
    final s = TimelapseSettings()
      ..fps = 10
      ..secondsPerPhoto = 1
      ..transition = PhotoTransition.cut
      ..titleCard = false
      ..endHoldSeconds = 0
      ..motion = MotionMode.custom
      ..motionScope = MotionScope.wholeVideo
      ..easeMotion = false
      ..startFrame = const CameraFrame(1, 0.5, 0.5)
      ..endFrame = const CameraFrame(3, 0.2, 0.8);
    final plan = TimelapsePlan(
      settings: s,
      slots: buildSlots(project(), buildingId: 'b', viewId: 'f', from: null, to: null, perDate: PhotosPerDate.first),
      projectName: 'N',
      scopeLabel: 'H',
    );
    final lastOfWeek1 = plan.cameraFor(plan.at(9));
    final firstOfWeek2 = plan.cameraFor(plan.at(10));
    expect((firstOfWeek2.zoom - lastOfWeek1.zoom).abs(), lessThan(0.1));
    expect(plan.cameraFor(plan.at(0)).zoom, 1);
    expect(plan.cameraFor(plan.at(plan.totalFrames - 1)).zoom, closeTo(3, 1e-9));
    s.motionScope = MotionScope.eachPhoto;
    expect(plan.cameraFor(plan.at(10)).zoom, 1); // restarts on each photo
  });

  test('settings survive a save/load round trip', () {
    final s = TimelapseSettings()
      ..timeSymbol = TimeSymbol.hourglass
      ..aspect = VideoAspect.vertical
      ..resolution = VideoResolution.uhd4k
      ..showNote = true
      ..motion = MotionMode.custom
      ..endFrame = const CameraFrame(2.5, 0.3, 0.7);
    final back = TimelapseSettings.fromJson(s.toJson());
    expect(back.motion, MotionMode.custom);
    expect(back.endFrame.zoom, 2.5);
    expect(back.endFrame.cx, 0.3);
    expect(back.timeSymbol, TimeSymbol.hourglass);
    expect(back.outputSize.width, 2160);
    expect(back.outputSize.height, 3840);
    expect(back.showNote, isTrue);
  });
}
