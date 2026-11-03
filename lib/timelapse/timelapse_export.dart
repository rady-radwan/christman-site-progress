import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../library_store.dart';
import 'frame_painter.dart';
import 'timelapse_plan.dart';

/// Decodes slot photos at just the size a frame needs (never upscaled), and
/// keeps the most recently used ones in memory.
class SlotImageCache {
  SlotImageCache(this.store, this.plan, this.frameSize, {this.capacity = 4});

  final LibraryStore store;
  TimelapsePlan plan;
  ui.Size frameSize;
  final int capacity;
  // Keyed by media item id, so the cache survives changes to the slot list.
  final Map<String, ui.Image> _images = {};
  final List<String> _order = [];
  final Map<String, Future<void>> _pending = {};

  String? _id(int slot) => slot >= 0 && slot < plan.slots.length ? plan.slots[slot].item.id : null;

  ui.Image? get(int slot) => _images[_id(slot)];

  bool has(int slot) => _images.containsKey(_id(slot));

  Future<void> ensure(Iterable<int> slots) async {
    final wanted = <String, int>{};
    for (final i in slots) {
      final id = _id(i);
      if (id != null) wanted[id] = i;
    }
    await Future.wait(wanted.entries.map((e) => _load(e.key, e.value)));
    for (final id in wanted.keys) {
      _order
        ..remove(id)
        ..add(id);
    }
    while (_order.length > capacity) {
      final drop = _order.firstWhere((id) => !wanted.containsKey(id), orElse: () => '');
      if (drop.isEmpty) break;
      _order.remove(drop);
      _images.remove(drop)?.dispose();
    }
  }

  Future<void> _load(String id, int slot) {
    if (_images.containsKey(id)) return Future.value();
    final item = plan.slots[slot].item;
    return _pending[id] ??= () async {
      try {
        final file = store.fileFor(item);
        final buffer = await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes());
        // Enough pixels to cover the frame with room for the slow zoom.
        final codec = await ui.instantiateImageCodecWithSize(buffer, getTargetSize: (w, h) {
          final need = math.max(frameSize.width * 1.15 / w, frameSize.height * 1.15 / h);
          if (need >= 1) return ui.TargetImageSize(width: w, height: h);
          return ui.TargetImageSize(width: (w * need).ceil(), height: (h * need).ceil());
        });
        final frame = await codec.getNextFrame();
        codec.dispose();
        _images[id] = frame.image;
      } catch (_) {
        // Unreadable photo: the frame is drawn without it.
      } finally {
        _pending.remove(id);
      }
    }();
  }

  void clear() {
    for (final img in _images.values) {
      img.dispose();
    }
    _images.clear();
    _order.clear();
  }
}

Future<ui.Image?> loadLogo([String asset = 'assets/logo.png']) async {
  try {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  } catch (_) {
    return null;
  }
}

/// Finds ffmpeg: bundled next to the app first, then on PATH.
Future<String?> findFfmpeg() async {
  final exeDir = p.dirname(Platform.resolvedExecutable);
  final name = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
  for (final c in [p.join(exeDir, 'ffmpeg', name), p.join(exeDir, name)]) {
    if (await File(c).exists()) return c;
  }
  try {
    final r = await Process.run(Platform.isWindows ? 'where' : 'which', ['ffmpeg']);
    if (r.exitCode == 0) {
      final first = (r.stdout as String).split(RegExp(r'[\r\n]+')).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
      if (first.isNotEmpty) return first.trim();
    }
  } catch (_) {}
  return null;
}

class ExportCancelled implements Exception {}

/// Renders every frame with [paintFrame] and streams it to ffmpeg (H.264 MP4).
class TimelapseExporter {
  TimelapseExporter({required this.plan, required this.store, required this.outputPath, this.logo});

  final TimelapsePlan plan;
  final LibraryStore store;
  final String outputPath;
  final ui.Image? logo;

  Process? _proc;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _proc?.kill();
  }

  Future<void> run(void Function(int done, int total) onProgress) async {
    final ffmpeg = await findFfmpeg();
    if (ffmpeg == null) {
      throw Exception('The video encoder (ffmpeg) was not found. Reinstall the app to restore it.');
    }
    final s = plan.settings;
    final size = s.outputSize;
    final w = size.width.toInt(), h = size.height.toInt();
    final total = plan.totalFrames;
    final seconds = total / plan.fps;
    final music = s.musicPath;
    final hasMusic = music != null && music.isNotEmpty && await File(music).exists();

    final args = <String>[
      '-hide_banner', '-loglevel', 'error', '-y',
      '-f', 'rawvideo', '-pix_fmt', 'rgba', '-s', '${w}x$h', '-r', '${plan.fps}', '-i', '-',
      if (hasMusic) ...['-stream_loop', '-1', '-i', music],
      '-map', '0:v',
      if (hasMusic) ...[
        '-map', '1:a', '-c:a', 'aac', '-b:a', '192k',
        '-af', 'afade=t=in:d=1,afade=t=out:st=${math.max(0, seconds - 2.5).toStringAsFixed(2)}:d=2.5',
      ],
      '-t', seconds.toStringAsFixed(3),
      '-c:v', 'libx264', '-preset', s.preset, '-crf', '${s.crf}',
      '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
      outputPath,
    ];

    final proc = await Process.start(ffmpeg, args);
    _proc = proc;
    final errors = StringBuffer();
    final errSub = proc.stderr.transform(utf8.decoder).listen((t) {
      errors.write(t);
    });
    final outSub = proc.stdout.listen((_) {});
    var exited = false;
    final exitFuture = proc.exitCode.then((c) {
      exited = true;
      return c;
    });

    final cache = SlotImageCache(store, plan, size, capacity: 4);
    Uint8List? lastBytes;
    String? lastKey;
    try {
      for (var f = 0; f < total; f++) {
        if (_cancelled) throw ExportCancelled();
        if (exited) break;
        final info = plan.at(f);
        final key = '${info.isTitle}|${info.titleProgress}|${info.slot}|${info.nextSlot}|'
            '${info.mix}|${info.local}|${info.global}';
        Uint8List bytes;
        if (key == lastKey && lastBytes != null) {
          bytes = lastBytes;
        } else {
          final need = <int>{info.isTitle ? 0 : info.slot, if (info.nextSlot != null) info.nextSlot!};
          await cache.ensure({...need, if (!info.isTitle) info.slot + 1});
          final rec = ui.PictureRecorder();
          final canvas = ui.Canvas(rec, ui.Offset.zero & size);
          paintFrame(canvas, size, plan, info, cache.get, logo);
          final pic = rec.endRecording();
          final img = await pic.toImage(w, h);
          final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
          img.dispose();
          pic.dispose();
          bytes = data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
          lastBytes = bytes;
          lastKey = key;
        }
        proc.stdin.add(bytes);
        await proc.stdin.flush();
        if (f % 3 == 0 || f == total - 1) onProgress(f + 1, total);
      }
      await proc.stdin.close();
    } catch (e) {
      if (_cancelled || e is ExportCancelled) {
        proc.kill();
        await exitFuture;
        await _deletePartial();
        throw ExportCancelled();
      }
      if (!exited) {
        // Writing failed; let ffmpeg explain why.
        try {
          await proc.stdin.close();
        } catch (_) {}
      }
    } finally {
      cache.clear();
    }

    final code = await exitFuture;
    await errSub.cancel();
    await outSub.cancel();
    if (_cancelled) {
      await _deletePartial();
      throw ExportCancelled();
    }
    if (code != 0) {
      await _deletePartial();
      final msg = errors.toString().trim();
      throw Exception('Video encoding failed (code $code).${msg.isEmpty ? '' : '\n\n${msg.length > 1200 ? msg.substring(msg.length - 1200) : msg}'}');
    }
    onProgress(total, total);
  }

  Future<void> _deletePartial() async {
    try {
      final f = File(outputPath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
