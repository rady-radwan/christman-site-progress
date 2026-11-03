import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'timelapse_plan.dart';
import 'timelapse_settings.dart';

typedef SlotImage = ui.Image? Function(int slot);

/// Draws one timelapse frame in output pixels. The live preview and the MP4
/// export use this same function, so what you see is what you get.
void paintFrame(
  Canvas canvas,
  Size size,
  TimelapsePlan plan,
  FrameInfo info,
  SlotImage imageFor,
  ui.Image? logo, {
  bool cameraOff = false,
  bool overlays = true,
}) {
  final s = plan.settings;
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF000000));
  if (plan.slots.isEmpty) return;

  if (info.isTitle) {
    _paintTitle(canvas, size, plan, info, imageFor, logo);
    return;
  }

  final cam = cameraOff ? CameraFrame.whole : plan.cameraFor(info);
  final img = imageFor(info.slot);
  if (img != null) _drawPhoto(canvas, size, s, img, cam, 1);
  final next = info.nextSlot;
  if (next != null && info.mix > 0) {
    final nimg = imageFor(next);
    final ncam = cameraOff ? CameraFrame.whole : plan.cameraFor(info, forNext: true);
    if (nimg != null) _drawPhoto(canvas, size, s, nimg, ncam, info.mix);
  }
  if (overlays) _paintOverlays(canvas, size, plan, info, logo);
}

// ------------------------------------------------------------------ photo

/// Where the whole photo sits in the frame at zoom 1: the full frame when
/// filling, the letter-boxed rectangle when fitting. Camera centres are
/// fractions of this rectangle, so a zoomed area stays on the same spot of
/// the site from one week's photo to the next.
Rect photoBaseRect(Size size, TimelapseSettings s, ui.Image img) {
  if (s.fit == PhotoFit.fill) return Offset.zero & size;
  final iw = img.width.toDouble(), ih = img.height.toDouble();
  final scale = math.min(size.width / iw, size.height / ih);
  return Rect.fromCenter(center: size.center(Offset.zero), width: iw * scale, height: ih * scale);
}

/// The part of the zoom-1 frame the camera shows. The view is kept inside
/// the photo whenever the photo is big enough to fill it.
Rect cameraRectInFrame(Size size, TimelapseSettings s, ui.Image img, CameraFrame cam) {
  final base = photoBaseRect(size, s, img);
  final z = cam.zoom < 1 ? 1.0 : cam.zoom;
  final w = size.width / z, h = size.height / z;
  double fit(double c, double lo, double hi, double half) =>
      hi - lo >= half * 2 ? c.clamp(lo + half, hi - half) : (lo + hi) / 2;
  final cx = fit(base.left + cam.cx * base.width, base.left, base.right, w / 2);
  final cy = fit(base.top + cam.cy * base.height, base.top, base.bottom, h / 2);
  return Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
}

/// Converts a point in the zoom-1 frame to a camera centre (0..1, 0..1).
Offset cameraCentreFromPoint(Size size, TimelapseSettings s, ui.Image img, Offset pt) {
  final base = photoBaseRect(size, s, img);
  return Offset(
    ((pt.dx - base.left) / base.width).clamp(0.0, 1.0),
    ((pt.dy - base.top) / base.height).clamp(0.0, 1.0),
  );
}

void _drawPhoto(Canvas canvas, Size size, TimelapseSettings s, ui.Image img, CameraFrame cam, double alpha) {
  final iw = img.width.toDouble(), ih = img.height.toDouble();
  final layer = alpha < 1;
  if (layer) {
    canvas.saveLayer(Offset.zero & size, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
  }
  final quality = Paint()..filterQuality = FilterQuality.high;

  Rect coverSrc(double z) {
    final scale = math.max(size.width / iw, size.height / ih) * z;
    final sw = size.width / scale, sh = size.height / scale;
    return Rect.fromCenter(center: Offset(iw / 2, ih / 2), width: sw, height: sh);
  }

  final zoom = cam.zoom < 1 ? 1.0 : cam.zoom;
  switch (s.fit) {
    case PhotoFit.fill:
      final base = coverSrc(1);
      final w = base.width / zoom, h = base.height / zoom;
      final cx = (base.left + cam.cx * base.width).clamp(base.left + w / 2, base.right - w / 2);
      final cy = (base.top + cam.cy * base.height).clamp(base.top + h / 2, base.bottom - h / 2);
      canvas.drawImageRect(img, Rect.fromCenter(center: Offset(cx, cy), width: w, height: h), Offset.zero & size, quality);
    case PhotoFit.fit:
    case PhotoFit.blurFill:
      if (s.fit == PhotoFit.blurFill) {
        canvas.saveLayer(
          Offset.zero & size,
          Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: size.height / 40, sigmaY: size.height / 40, tileMode: TileMode.clamp),
        );
        canvas.drawImageRect(img, coverSrc(1.1), Offset.zero & size, quality);
        canvas.restore();
        canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x66000000));
      }
      final dst = photoBaseRect(size, s, img);
      // Show exactly the camera's view rectangle across the whole frame.
      final view = cameraRectInFrame(size, s, img, CameraFrame(zoom, cam.cx, cam.cy));
      canvas.save();
      canvas.clipRect(Offset.zero & size);
      canvas.translate(size.width / 2, size.height / 2);
      canvas.scale(zoom);
      canvas.translate(-view.center.dx, -view.center.dy);
      canvas.drawImageRect(img, Rect.fromLTWH(0, 0, iw, ih), dst, quality);
      canvas.restore();
  }
  if (layer) canvas.restore();
}

// ------------------------------------------------------------------ text helpers

TextPainter _text(String text, double fontSize,
    {FontWeight weight = FontWeight.w500,
    Color color = Colors.white,
    double letterSpacing = 0,
    double maxWidth = double.infinity,
    int maxLines = 1,
    bool shadow = false,
    FontStyle style = FontStyle.normal,
    TextAlign align = TextAlign.left}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        fontStyle: style,
        height: 1.15,
        shadows: shadow
            ? [Shadow(color: const Color(0xCC000000), blurRadius: fontSize * 0.35, offset: Offset(0, fontSize * 0.06))]
            : null,
      ),
    ),
    textDirection: ui.TextDirection.ltr,
    maxLines: maxLines,
    ellipsis: '…',
    textAlign: align,
  );
  tp.layout(maxWidth: maxWidth);
  return tp;
}

String formatDate(DateTime d, DateStyle style) => switch (style) {
      DateStyle.long => DateFormat('EEEE, MMMM d, yyyy').format(d),
      DateStyle.medium => DateFormat('MMM d, yyyy').format(d),
      DateStyle.numeric => DateFormat('yyyy-MM-dd').format(d),
    };

double _unit(Size size, TimelapseSettings s) =>
    math.min(size.width, size.height) / 1080 * s.textScale;

// ------------------------------------------------------------------ overlays

void _paintOverlays(Canvas canvas, Size size, TimelapsePlan plan, FrameInfo info, ui.Image? logo) {
  final s = plan.settings;
  final u = _unit(size, s);
  final base = math.min(size.width, size.height) / 1080; // margins don't grow with text size
  final slot = plan.slots[info.labelSlot];
  final accent = s.accentColor;
  final shadow = s.cardStyle == CardStyle.none;
  final margin = 44 * base;
  final barSpace = s.showProgressBar ? 70 * base : 0.0;

  // Text lines
  final maxTextW = size.width * (s.corner == OverlayCorner.bottomBand ? 0.7 : 0.55);
  final lines = <TextPainter>[];
  final gaps = <double>[];
  final top = [
    if (s.showWeek) 'WEEK ${slot.week}',
    if (s.showDayCounter) 'DAY ${slot.dayNumber}',
  ].join('  ·  ');
  if (top.isNotEmpty) {
    lines.add(_text(top, 22 * u, weight: FontWeight.w800, color: accent, letterSpacing: 2.5 * u, maxWidth: maxTextW, shadow: shadow));
    gaps.add(6 * u);
  }
  if (s.showDate) {
    lines.add(_text(formatDate(slot.date, s.dateStyle), 44 * u, weight: FontWeight.w700, maxWidth: maxTextW, shadow: shadow));
    gaps.add(6 * u);
  }
  final place = [if (s.showBuilding && slot.building.isNotEmpty) slot.building, if (s.showView && slot.view.isNotEmpty) slot.view]
      .join('  ·  ');
  if (place.isNotEmpty) {
    lines.add(_text(place, 30 * u, weight: FontWeight.w600, color: const Color(0xFFEDEDED), maxWidth: maxTextW, shadow: shadow));
    gaps.add(4 * u);
  }
  if (s.showProject && plan.projectName.isNotEmpty) {
    lines.add(_text(plan.projectName, 22 * u, weight: FontWeight.w500, color: const Color(0xCCFFFFFF), maxWidth: maxTextW, shadow: shadow));
    gaps.add(4 * u);
  }
  if (s.showNote && slot.note.isNotEmpty) {
    lines.add(_text(slot.note, 22 * u,
        style: FontStyle.italic, color: const Color(0xE6FFFFFF), maxWidth: maxTextW, maxLines: 2, shadow: shadow));
    gaps.add(0);
  }

  final hasSymbol = s.timeSymbol != TimeSymbol.none;
  if (lines.isNotEmpty || hasSymbol) {
    double textW = 0, textH = 0;
    for (var i = 0; i < lines.length; i++) {
      textW = math.max(textW, lines[i].width);
      textH += lines[i].height + (i < lines.length - 1 ? gaps[i] : 0);
    }
    final symbolSize = math.max(textH, 96 * u).clamp(80 * u, 150 * u).toDouble();
    final pad = 22 * u;
    final gap = (hasSymbol && lines.isNotEmpty) ? 24 * u : 0.0;
    final contentW = (hasSymbol ? symbolSize : 0) + gap + textW;
    final contentH = math.max(textH, hasSymbol ? symbolSize : 0);

    Rect card;
    if (s.corner == OverlayCorner.bottomBand) {
      final h = contentH + pad * 2;
      card = Rect.fromLTWH(0, size.height - barSpace - h, size.width, h);
    } else {
      final w = contentW + pad * 2 + (s.cardStyle == CardStyle.none ? 0 : 6 * u);
      final h = contentH + pad * 2;
      final left = s.corner == OverlayCorner.topLeft || s.corner == OverlayCorner.bottomLeft;
      final topSide = s.corner == OverlayCorner.topLeft || s.corner == OverlayCorner.topRight;
      final x = left ? margin : size.width - margin - w;
      final y = topSide ? margin : size.height - margin - barSpace - h;
      card = Rect.fromLTWH(x, y, w, h);
    }

    // Card background
    final radius = s.corner == OverlayCorner.bottomBand ? Radius.zero : Radius.circular(18 * u);
    if (s.cardStyle != CardStyle.none) {
      final bg = s.cardStyle == CardStyle.glass ? const Color(0x99000000) : const Color(0xF01E2A33);
      canvas.drawRRect(RRect.fromRectAndRadius(card, radius), Paint()..color = bg);
      if (s.corner == OverlayCorner.bottomBand) {
        canvas.drawRect(Rect.fromLTWH(card.left, card.top, card.width, 4 * u), Paint()..color = accent);
      } else {
        canvas.save();
        canvas.clipRRect(RRect.fromRectAndRadius(card, radius));
        canvas.drawRect(Rect.fromLTWH(card.left, card.top, 6 * u, card.height), Paint()..color = accent);
        canvas.restore();
      }
    }

    var x = card.left + pad + (s.cardStyle == CardStyle.none || s.corner == OverlayCorner.bottomBand ? 0 : 6 * u);
    if (s.corner == OverlayCorner.bottomBand) x = margin;
    final cy = card.center.dy;
    if (hasSymbol) {
      final r = Rect.fromLTWH(x, cy - symbolSize / 2, symbolSize, symbolSize);
      switch (s.timeSymbol) {
        case TimeSymbol.clock:
          _clock(canvas, r, info, accent, u);
        case TimeSymbol.calendar:
          _calendar(canvas, r, slot.date, accent, u);
        case TimeSymbol.hourglass:
          _hourglass(canvas, r, info.global, accent, u);
        case TimeSymbol.none:
          break;
      }
      x += symbolSize + gap;
    }
    var y = cy - textH / 2;
    for (var i = 0; i < lines.length; i++) {
      lines[i].paint(canvas, Offset(x, y));
      y += lines[i].height + (i < lines.length - 1 ? gaps[i] : 0);
    }
  }

  if (s.showProgressBar) _progressBar(canvas, size, plan, info, accent, base, u);

  if (s.showLogo && logo != null) {
    final ls = 84 * base;
    final right = s.corner != OverlayCorner.topRight;
    final dst = Rect.fromLTWH(right ? size.width - margin - ls : margin, margin, ls, ls);
    canvas.drawImageRect(
      logo,
      Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
      dst,
      Paint()
        ..filterQuality = FilterQuality.high
        ..color = const Color(0xDDFFFFFF),
    );
  }
}

void _progressBar(Canvas canvas, Size size, TimelapsePlan plan, FrameInfo info, Color accent, double base, double u) {
  final margin = 44 * base;
  final y = size.height - 34 * base;
  final x0 = margin, x1 = size.width - margin;
  final w = x1 - x0;
  final h = 6 * base;
  final track = RRect.fromRectAndRadius(Rect.fromLTWH(x0, y - h / 2, w, h), Radius.circular(h));
  canvas.drawRRect(track, Paint()..color = const Color(0x55FFFFFF));
  final px = x0 + w * info.global;
  canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x0, y - h / 2, px - x0, h), Radius.circular(h)), Paint()..color = accent);

  // A tick for every capture date
  final n = plan.slots.length;
  final seen = <String>{};
  for (var i = 0; i < n; i++) {
    final key = plan.slots[i].date.toIso8601String();
    if (!seen.add(key)) continue;
    final t = n <= 1 ? 1.0 : i / (n - 1);
    final tx = x0 + w * t;
    canvas.drawCircle(Offset(tx, y), 4.5 * base,
        Paint()..color = t <= info.global ? Colors.white : const Color(0x88FFFFFF));
  }
  canvas.drawCircle(Offset(px, y), 12 * base, Paint()..color = Colors.white);
  canvas.drawCircle(Offset(px, y), 8 * base, Paint()..color = accent);

  if (plan.slots.isNotEmpty) {
    final a = _text(DateFormat('MMM d, yyyy').format(plan.slots.first.date), 17 * base,
        color: const Color(0xCCFFFFFF), shadow: true, weight: FontWeight.w600);
    final b = _text(DateFormat('MMM d, yyyy').format(plan.slots.last.date), 17 * base,
        color: const Color(0xCCFFFFFF), shadow: true, weight: FontWeight.w600);
    a.paint(canvas, Offset(x0, y - 16 * base - a.height));
    b.paint(canvas, Offset(x1 - b.width, y - 16 * base - b.height));
  }
}

// ------------------------------------------------------------------ time symbols

/// Hour hand sweeps once across the whole video, minute hand once per photo.
void _clock(Canvas canvas, Rect r, FrameInfo info, Color accent, double u) {
  final c = r.center;
  final rad = r.width / 2;
  canvas.drawCircle(c, rad, Paint()..color = const Color(0x33FFFFFF));
  canvas.drawCircle(
      c,
      rad - 2 * u,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * u
        ..color = accent);
  for (var i = 0; i < 12; i++) {
    final a = i * math.pi / 6;
    final outer = rad - 9 * u;
    final inner = rad - (i % 3 == 0 ? 20 : 15) * u;
    canvas.drawLine(
      c + Offset(math.sin(a) * inner, -math.cos(a) * inner),
      c + Offset(math.sin(a) * outer, -math.cos(a) * outer),
      Paint()
        ..color = Colors.white
        ..strokeWidth = (i % 3 == 0 ? 3.5 : 2) * u
        ..strokeCap = StrokeCap.round,
    );
  }
  void hand(double turns, double len, double width, Color color) {
    final a = turns * 2 * math.pi;
    canvas.drawLine(
      c,
      c + Offset(math.sin(a) * len, -math.cos(a) * len),
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  final minuteTurns = info.slot + info.local;
  hand(info.global, rad * 0.45, 6 * u, Colors.white);
  hand(minuteTurns, rad * 0.68, 4 * u, accent);
  canvas.drawCircle(c, 6 * u, Paint()..color = Colors.white);
}

void _calendar(Canvas canvas, Rect r, DateTime d, Color accent, double u) {
  final rr = RRect.fromRectAndRadius(r.deflate(4 * u), Radius.circular(14 * u));
  canvas.drawRRect(rr, Paint()..color = Colors.white);
  final band = Rect.fromLTWH(rr.left, rr.top, rr.width, rr.height * 0.3);
  canvas.save();
  canvas.clipRRect(rr);
  canvas.drawRect(band, Paint()..color = accent);
  canvas.restore();
  final month = _text(DateFormat('MMM').format(d).toUpperCase(), rr.height * 0.17,
      weight: FontWeight.w800, letterSpacing: 1.5 * u);
  month.paint(canvas, Offset(band.center.dx - month.width / 2, band.center.dy - month.height / 2));
  final day = _text('${d.day}', rr.height * 0.42, weight: FontWeight.w800, color: const Color(0xFF1E2A33));
  day.paint(canvas, Offset(rr.center.dx - day.width / 2, band.bottom + rr.height * 0.02));
  final wd = _text(DateFormat('EEE').format(d).toUpperCase(), rr.height * 0.12,
      weight: FontWeight.w700, color: const Color(0xFF6B7780), letterSpacing: 1 * u);
  wd.paint(canvas, Offset(rr.center.dx - wd.width / 2, rr.bottom - wd.height - rr.height * 0.05));
  // Binding rings
  for (final fx in [0.3, 0.7]) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(rr.left + rr.width * fx, rr.top), width: 7 * u, height: 18 * u),
          Radius.circular(4 * u)),
      Paint()..color = const Color(0xFF1E2A33),
    );
  }
}

/// Sand runs from top to bottom over the whole video.
void _hourglass(Canvas canvas, Rect r, double t, Color accent, double u) {
  final w = r.width * 0.62;
  final left = r.center.dx - w / 2, right = r.center.dx + w / 2;
  final top = r.top + r.height * 0.1, bottom = r.bottom - r.height * 0.1;
  final mid = r.center.dy;
  final neck = w * 0.08;

  final glass = Path()
    ..moveTo(left, top)
    ..lineTo(right, top)
    ..lineTo(r.center.dx + neck, mid)
    ..lineTo(right, bottom)
    ..lineTo(left, bottom)
    ..lineTo(r.center.dx - neck, mid)
    ..close();
  canvas.drawPath(glass, Paint()..color = const Color(0x33FFFFFF));

  canvas.save();
  canvas.clipPath(glass);
  final sand = Paint()..color = accent;
  // Top chamber: remaining sand sits at the bottom of the top chamber.
  final topH = (mid - top) * (1 - t);
  canvas.drawRect(Rect.fromLTRB(left, mid - topH, right, mid), sand);
  // Bottom chamber fills from the bottom.
  final botH = (bottom - mid) * t;
  canvas.drawRect(Rect.fromLTRB(left, bottom - botH, right, bottom), sand);
  if (t > 0 && t < 1) {
    canvas.drawLine(Offset(r.center.dx, mid), Offset(r.center.dx, bottom - botH),
        Paint()
          ..color = accent
          ..strokeWidth = 3 * u);
  }
  canvas.restore();

  canvas.drawPath(
      glass,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * u
        ..color = Colors.white);
  final cap = Paint()..color = Colors.white;
  canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(left - 8 * u, top - 9 * u, right + 8 * u, top), Radius.circular(3 * u)), cap);
  canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(left - 8 * u, bottom, right + 8 * u, bottom + 9 * u), Radius.circular(3 * u)),
      cap);
}

// ------------------------------------------------------------------ title card

void _paintTitle(Canvas canvas, Size size, TimelapsePlan plan, FrameInfo info, SlotImage imageFor, ui.Image? logo) {
  final s = plan.settings;
  final u = math.min(size.width, size.height) / 1080;
  final p = info.titleProgress;
  final first = imageFor(0);
  if (first != null) {
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: size.height / 30, sigmaY: size.height / 30, tileMode: TileMode.clamp),
    );
    final iw = first.width.toDouble(), ih = first.height.toDouble();
    final scale = math.max(size.width / iw, size.height / ih) * 1.1;
    final sw = size.width / scale, sh = size.height / scale;
    canvas.drawImageRect(first, Rect.fromCenter(center: Offset(iw / 2, ih / 2), width: sw, height: sh),
        Offset.zero & size, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
  }
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xB3101820));

  final fadeIn = (p / 0.25).clamp(0.0, 1.0);
  canvas.saveLayer(Offset.zero & size, Paint()..color = Color.fromRGBO(0, 0, 0, fadeIn));
  final maxW = size.width * 0.85;
  final title = s.titleText.trim().isNotEmpty ? s.titleText.trim() : plan.projectName;
  final subtitle = s.subtitleText.trim().isNotEmpty ? s.subtitleText.trim() : plan.scopeLabel;
  final kicker = _text('SITE PROGRESS TIMELAPSE', 24 * u,
      weight: FontWeight.w800, color: s.accentColor, letterSpacing: 4 * u, align: TextAlign.center, maxWidth: maxW);
  final t = _text(title, 76 * u, weight: FontWeight.w800, maxWidth: maxW, maxLines: 2, align: TextAlign.center);
  final sub = _text(subtitle, 38 * u, weight: FontWeight.w600, color: const Color(0xFFE6E6E6), maxWidth: maxW, align: TextAlign.center);
  final range = _text(plan.dateRange, 30 * u, color: const Color(0xCCFFFFFF), maxWidth: maxW, align: TextAlign.center);
  final total = kicker.height + 18 * u + t.height + 16 * u + sub.height + 14 * u + range.height;
  var y = size.height / 2 - total / 2 - (1 - fadeIn) * 20 * u;
  for (final (tp, after) in [(kicker, 18 * u), (t, 16 * u), (sub, 14 * u), (range, 0.0)]) {
    tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, y));
    y += tp.height + after;
  }
  canvas.drawRect(
      Rect.fromCenter(center: Offset(size.width / 2, y + 30 * u), width: 120 * u, height: 5 * u),
      Paint()..color = s.accentColor);
  if (s.showLogo && logo != null) {
    final ls = 110 * u;
    canvas.drawImageRect(logo, Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
        Rect.fromLTWH(size.width / 2 - ls / 2, y + 60 * u, ls, ls), Paint()..filterQuality = FilterQuality.high);
  }
  canvas.restore();

  // Dissolve into the first photo during the last fifth of the title.
  if (p > 0.8 && first != null) {
    final a = ((p - 0.8) / 0.2).clamp(0.0, 1.0);
    _drawPhoto(canvas, size, s, first, plan.cameraFor(const FrameInfo()), a);
  }
}
