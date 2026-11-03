import 'dart:ui';

enum VideoAspect { landscape, square, vertical }

enum VideoResolution { hd720, hd1080, qhd1440, uhd4k }

enum PhotoFit { fill, fit, blurFill }

enum PhotoTransition { cut, crossfade }

enum PhotosPerDate { first, all }

enum OverlayCorner { topLeft, topRight, bottomLeft, bottomRight, bottomBand }

enum TimeSymbol { none, clock, calendar, hourglass }

enum DateStyle { long, medium, numeric }

enum TextSize { small, medium, large, extraLarge }

enum CardStyle { glass, solid, none }

enum Quality { standard, high, maximum }

enum MotionMode { none, slowZoom, custom }

enum MotionScope { wholeVideo, eachPhoto }

/// Where the virtual camera looks: zoom (1 = whole photo) and the centre of
/// the view as a fraction of the photo (0..1, 0..1).
class CameraFrame {
  const CameraFrame(this.zoom, this.cx, this.cy);
  final double zoom;
  final double cx;
  final double cy;

  static const whole = CameraFrame(1, 0.5, 0.5);

  CameraFrame copyWith({double? zoom, double? cx, double? cy}) =>
      CameraFrame(zoom ?? this.zoom, cx ?? this.cx, cy ?? this.cy);

  static CameraFrame lerp(CameraFrame a, CameraFrame b, double t) => CameraFrame(
        a.zoom + (b.zoom - a.zoom) * t,
        a.cx + (b.cx - a.cx) * t,
        a.cy + (b.cy - a.cy) * t,
      );

  Map<String, dynamic> toJson() => {'zoom': zoom, 'cx': cx, 'cy': cy};
  static CameraFrame fromJson(Object? j, CameraFrame fallback) {
    if (j is! Map) return fallback;
    double d(String k, double f) => (j[k] as num?)?.toDouble() ?? f;
    return CameraFrame(d('zoom', fallback.zoom), d('cx', fallback.cx), d('cy', fallback.cy));
  }
}

const accentChoices = <int>[
  0xFFE8742A, // Christman orange
  0xFF4FA3E0, // blue
  0xFF3FBF7F, // green
  0xFFF2C94C, // yellow
  0xFFE5484D, // red
  0xFFFFFFFF, // white
];

/// Every option of the timelapse maker. Saved between sessions.
class TimelapseSettings {
  // Source
  PhotosPerDate photosPerDate = PhotosPerDate.first;

  // Video
  VideoAspect aspect = VideoAspect.landscape;
  VideoResolution resolution = VideoResolution.hd1080;
  int fps = 30;
  Quality quality = Quality.high;

  // Timing & motion
  double secondsPerPhoto = 1.5;
  PhotoTransition transition = PhotoTransition.crossfade;
  double transitionSeconds = 0.5;
  PhotoFit fit = PhotoFit.fill;
  MotionMode motion = MotionMode.slowZoom;
  MotionScope motionScope = MotionScope.wholeVideo;
  CameraFrame startFrame = const CameraFrame(1.0, 0.5, 0.5);
  CameraFrame endFrame = const CameraFrame(1.6, 0.5, 0.5);
  bool easeMotion = true;
  double endHoldSeconds = 2.0;

  // Overlay content
  bool showDate = true;
  DateStyle dateStyle = DateStyle.long;
  bool showWeek = true;
  bool showBuilding = true;
  bool showView = true;
  bool showProject = true;
  bool showDayCounter = false;
  bool showNote = false;
  TimeSymbol timeSymbol = TimeSymbol.clock;
  bool showProgressBar = true;
  bool showLogo = true;

  // Overlay style
  OverlayCorner corner = OverlayCorner.bottomLeft;
  TextSize textSize = TextSize.medium;
  CardStyle cardStyle = CardStyle.glass;
  int accent = accentChoices.first;

  // Title & music
  bool titleCard = true;
  double titleSeconds = 2.5;
  String titleText = '';
  String subtitleText = '';
  String? musicPath;

  Color get accentColor => Color(accent);

  Size get outputSize {
    final h = switch (resolution) {
      VideoResolution.hd720 => 720,
      VideoResolution.hd1080 => 1080,
      VideoResolution.qhd1440 => 1440,
      VideoResolution.uhd4k => 2160,
    };
    return switch (aspect) {
      VideoAspect.landscape => Size((h * 16 / 9).roundToDouble(), h.toDouble()),
      VideoAspect.square => Size(h.toDouble(), h.toDouble()),
      VideoAspect.vertical => Size(h.toDouble(), (h * 16 / 9).roundToDouble()),
    };
  }

  double get textScale => switch (textSize) {
        TextSize.small => 0.8,
        TextSize.medium => 1.0,
        TextSize.large => 1.3,
        TextSize.extraLarge => 1.65,
      };

  int get crf => switch (quality) {
        Quality.standard => 23,
        Quality.high => 18,
        Quality.maximum => 14,
      };

  String get preset => quality == Quality.maximum ? 'medium' : 'veryfast';

  Map<String, dynamic> toJson() => {
        'photosPerDate': photosPerDate.name,
        'aspect': aspect.name,
        'resolution': resolution.name,
        'fps': fps,
        'quality': quality.name,
        'secondsPerPhoto': secondsPerPhoto,
        'transition': transition.name,
        'transitionSeconds': transitionSeconds,
        'fit': fit.name,
        'motion': motion.name,
        'motionScope': motionScope.name,
        'startFrame': startFrame.toJson(),
        'endFrame': endFrame.toJson(),
        'easeMotion': easeMotion,
        'endHoldSeconds': endHoldSeconds,
        'showDate': showDate,
        'dateStyle': dateStyle.name,
        'showWeek': showWeek,
        'showBuilding': showBuilding,
        'showView': showView,
        'showProject': showProject,
        'showDayCounter': showDayCounter,
        'showNote': showNote,
        'timeSymbol': timeSymbol.name,
        'showProgressBar': showProgressBar,
        'showLogo': showLogo,
        'corner': corner.name,
        'textSize': textSize.name,
        'cardStyle': cardStyle.name,
        'accent': accent,
        'titleCard': titleCard,
        'titleSeconds': titleSeconds,
      };

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }

  static TimelapseSettings fromJson(Map<String, dynamic>? j) {
    final s = TimelapseSettings();
    if (j == null) return s;
    double d(String k, double f) => (j[k] as num?)?.toDouble() ?? f;
    bool b(String k, bool f) => j[k] as bool? ?? f;
    s
      ..photosPerDate = _enum(PhotosPerDate.values, j['photosPerDate'], s.photosPerDate)
      ..aspect = _enum(VideoAspect.values, j['aspect'], s.aspect)
      ..resolution = _enum(VideoResolution.values, j['resolution'], s.resolution)
      ..fps = (j['fps'] as num?)?.toInt() ?? s.fps
      ..quality = _enum(Quality.values, j['quality'], s.quality)
      ..secondsPerPhoto = d('secondsPerPhoto', s.secondsPerPhoto)
      ..transition = _enum(PhotoTransition.values, j['transition'], s.transition)
      ..transitionSeconds = d('transitionSeconds', s.transitionSeconds)
      ..fit = _enum(PhotoFit.values, j['fit'], s.fit)
      ..motion = j.containsKey('motion')
          ? _enum(MotionMode.values, j['motion'], s.motion)
          : (b('kenBurns', true) ? MotionMode.slowZoom : MotionMode.none)
      ..motionScope = _enum(MotionScope.values, j['motionScope'], s.motionScope)
      ..startFrame = CameraFrame.fromJson(j['startFrame'], s.startFrame)
      ..endFrame = CameraFrame.fromJson(j['endFrame'], s.endFrame)
      ..easeMotion = b('easeMotion', s.easeMotion)
      ..endHoldSeconds = d('endHoldSeconds', s.endHoldSeconds)
      ..showDate = b('showDate', s.showDate)
      ..dateStyle = _enum(DateStyle.values, j['dateStyle'], s.dateStyle)
      ..showWeek = b('showWeek', s.showWeek)
      ..showBuilding = b('showBuilding', s.showBuilding)
      ..showView = b('showView', s.showView)
      ..showProject = b('showProject', s.showProject)
      ..showDayCounter = b('showDayCounter', s.showDayCounter)
      ..showNote = b('showNote', s.showNote)
      ..timeSymbol = _enum(TimeSymbol.values, j['timeSymbol'], s.timeSymbol)
      ..showProgressBar = b('showProgressBar', s.showProgressBar)
      ..showLogo = b('showLogo', s.showLogo)
      ..corner = _enum(OverlayCorner.values, j['corner'], s.corner)
      ..textSize = _enum(TextSize.values, j['textSize'], s.textSize)
      ..cardStyle = _enum(CardStyle.values, j['cardStyle'], s.cardStyle)
      ..accent = (j['accent'] as num?)?.toInt() ?? s.accent
      ..titleCard = b('titleCard', s.titleCard)
      ..titleSeconds = d('titleSeconds', s.titleSeconds);
    return s;
  }
}
