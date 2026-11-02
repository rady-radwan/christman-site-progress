import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../library_store.dart';
import '../models.dart';
import '../timelapse/frame_painter.dart';
import '../timelapse/timelapse_export.dart';
import '../timelapse/timelapse_plan.dart';
import '../timelapse/timelapse_settings.dart';
import '../util.dart';

/// Make Timelapse: pick photos, style the overlays, preview live, export MP4.
class TimelapseScreen extends StatefulWidget {
  const TimelapseScreen({
    super.key,
    required this.project,
    this.buildingId,
    this.viewId,
    this.autoPlay = false,
  });

  final Project project;
  final String? buildingId;
  final String? viewId;

  /// Opened from the play button under a photo: start playing, options hidden.
  final bool autoPlay;

  @override
  State<TimelapseScreen> createState() => _TimelapseScreenState();
}

class _TimelapseScreenState extends State<TimelapseScreen> with SingleTickerProviderStateMixin {
  TimelapseSettings _s = TimelapseSettings();
  String? _buildingId;
  String? _viewId;
  DateTime? _from;
  DateTime? _to;

  late TimelapsePlan _plan;
  late SlotImageCache _cache;
  ui.Image? _logo;
  int _frame = 0;
  late final Ticker _ticker;
  Duration _playStart = Duration.zero;
  int _playFromFrame = 0;
  bool _playing = false;
  bool _exporting = false;
  late bool _panelOpen = !widget.autoPlay;
  final _titleC = TextEditingController();
  final _subtitleC = TextEditingController();

  LibraryStore get _store => context.read<LibraryStore>();
  Project get _pr => widget.project;

  @override
  void initState() {
    super.initState();
    _buildingId = widget.buildingId;
    _viewId = widget.buildingId == null ? null : widget.viewId;
    _plan = _makePlan();
    _cache = SlotImageCache(_store, _plan, const Size(1280, 1280), capacity: 400);
    _ticker = createTicker(_onTick);
    _init();
  }

  Future<void> _init() async {
    final cfg = await LibraryStore.readConfig();
    final logo = await loadLogo();
    if (!mounted) return;
    setState(() {
      _s = TimelapseSettings.fromJson((cfg['timelapse'] as Map?)?.cast<String, dynamic>());
      _logo = logo;
      _replan();
      _frame = widget.autoPlay ? 0 : (_plan.titleFrames > 0 ? (_plan.titleFrames * 0.5).round() : 0);
    });
    if (widget.autoPlay && _plan.slots.isNotEmpty) {
      await _cache.ensure([0, 1, 2]);
      if (mounted && !_playing) _togglePlay();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _cache.clear();
    _logo?.dispose();
    _titleC.dispose();
    _subtitleC.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ plan

  String get _scopeLabel {
    if (_buildingId == null) return 'All buildings';
    final b = _pr.buildingById(_buildingId!);
    final v = b?.viewById(_viewId);
    return [b?.name ?? '', if (v != null) v.name].join(' · ');
  }

  List<DateTime> get _availableDates =>
      _pr.datesFor(_buildingId, viewId: _viewId, type: MediaType.photo);

  TimelapsePlan _makePlan() {
    _s.titleText = _titleC.text;
    _s.subtitleText = _subtitleC.text;
    return TimelapsePlan(
      settings: _s,
      slots: buildSlots(_pr,
          buildingId: _buildingId, viewId: _viewId, from: _from, to: _to, perDate: _s.photosPerDate),
      projectName: _pr.name,
      scopeLabel: _scopeLabel,
    );
  }

  void _replan() {
    _plan = _makePlan();
    _cache.plan = _plan;
    if (_frame >= _plan.totalFrames) _frame = (_plan.totalFrames - 1).clamp(0, 1 << 30);
  }

  void _update(VoidCallback change) {
    setState(() {
      change();
      _replan();
    });
  }

  // ------------------------------------------------------------ preview

  void _onTick(Duration elapsed) {
    final total = _plan.totalFrames;
    if (total == 0) return;
    var f = _playFromFrame + ((elapsed - _playStart).inMicroseconds * _plan.fps / 1e6).floor();
    if (f >= total) {
      _playFromFrame = 0;
      _playStart = elapsed;
      f = 0;
    }
    if (f != _frame) setState(() => _frame = f);
  }

  void _togglePlay() {
    setState(() {
      _playing = !_playing;
      if (_playing) {
        if (_frame >= _plan.totalFrames - 1) _frame = 0;
        _playFromFrame = _frame;
        _playStart = Duration.zero;
        _ticker.start();
      } else {
        _ticker.stop();
      }
    });
  }

  void _stopPlay() {
    if (_playing) {
      _ticker.stop();
      _playing = false;
    }
  }

  /// Loads the photos this frame (and the next ones) need, then repaints.
  void _prefetch(FrameInfo info) {
    if (_plan.slots.isEmpty) return;
    final base = info.isTitle ? 0 : info.slot;
    final want = {base, base + 1, base + 2, if (info.nextSlot != null) info.nextSlot!};
    final missing = want.where((i) => i < _plan.slots.length && !_cache.has(i)).toList();
    if (missing.isEmpty) return;
    _cache.ensure(want).then((_) {
      if (mounted) setState(() {});
    });
  }

  // ------------------------------------------------------------ export

  Future<void> _export() async {
    _stopPlay();
    if (_plan.slots.isEmpty) return;
    final safe = '${_pr.name} - $_scopeLabel timelapse'.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final loc = await getSaveLocation(
      suggestedName: '$safe.mp4',
      acceptedTypeGroups: const [XTypeGroup(label: 'MP4 video', extensions: ['mp4'], uniformTypeIdentifiers: ['public.mpeg-4'])],
      confirmButtonText: 'Export',
    );
    if (loc == null || !mounted) return;
    var out = loc.path;
    if (p.extension(out).toLowerCase() != '.mp4') out = '$out.mp4';
    await LibraryStore.setConfig('timelapse', _s.toJson());

    final progress = ValueNotifier<(int, int)>((0, _plan.totalFrames));
    final started = DateTime.now();
    final exporter = TimelapseExporter(plan: _makePlan(), store: _store, outputPath: out, logo: _logo);
    setState(() => _exporting = true);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Exporting timelapse'),
        content: SizedBox(
          width: 420,
          child: ValueListenableBuilder<(int, int)>(
            valueListenable: progress,
            builder: (context, v, _) {
              final (done, total) = v;
              final frac = total == 0 ? 0.0 : done / total;
              final elapsed = DateTime.now().difference(started);
              String eta = '';
              if (done > 10 && frac < 1) {
                final remain = elapsed * ((1 - frac) / frac);
                eta = ' · about ${_fmtDuration(remain)} left';
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.basename(out), style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: frac),
                  const SizedBox(height: 8),
                  Text('Frame $done of $total (${(frac * 100).toStringAsFixed(0)}%)$eta'),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: exporter.cancel, child: const Text('Cancel')),
        ],
      ),
    );

    Object? error;
    var cancelled = false;
    try {
      await exporter.run((d, t) => progress.value = (d, t));
    } on ExportCancelled {
      cancelled = true;
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    setState(() => _exporting = false);
    if (cancelled) {
      showSnack(context, 'Export cancelled');
      return;
    }
    if (error != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Export failed'),
          content: SizedBox(width: 480, child: SingleChildScrollView(child: SelectableText('$error'))),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }
    final size = await File(out).length();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline_rounded, size: 40),
        title: const Text('Timelapse saved'),
        content: Text('${p.basename(out)}\n${_fmtDuration(_plan.duration)} · ${prettySize(size)}'),
        actions: [
          if (isDesktop)
            TextButton(onPressed: () => revealFile(out), child: const Text('Show in folder')),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              openWithDefaultApp(out);
            },
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Play video'),
          ),
        ],
      ),
    );
  }

  static String _fmtDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return m > 0 ? '${m}m ${s.toString().padLeft(2, '0')}s' : '${s}s';
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final total = _plan.totalFrames;
    final frame = total == 0 ? 0 : _frame.clamp(0, total - 1);
    final info = _plan.at(frame);
    _prefetch(info);
    final out = _s.outputSize;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Make Timelapse', style: TextStyle(fontWeight: FontWeight.w700)),
              Text('${_pr.name} · $_scopeLabel', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () => setState(() => _panelOpen = !_panelOpen),
              icon: Icon(_panelOpen ? Icons.chevron_right_rounded : Icons.tune_rounded),
              label: Text(_panelOpen ? 'Hide options' : 'Customize'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _plan.slots.isEmpty || _exporting ? null : _export,
              icon: const Icon(Icons.movie_creation_outlined),
              label: const Text('Export MP4'),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: Row(
          children: [
            Expanded(
              child: Container(
                color: Colors.black,
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: _plan.slots.isEmpty
                              ? const Text('No photos match this selection.',
                                  style: TextStyle(color: Colors.white70))
                              : AspectRatio(
                                  aspectRatio: out.width / out.height,
                                  child: RepaintBoundary(
                                    child: CustomPaint(
                                      painter: _PreviewPainter(_plan, info, _cache, _logo, frame),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    _transport(total, frame, info),
                  ],
                ),
              ),
            ),
            if (_panelOpen) const VerticalDivider(width: 1),
            if (_panelOpen) SizedBox(width: 400, child: _panel()),
          ],
        ),
      ),
    );
  }

  Widget _transport(int total, int frame, FrameInfo info) {
    final scheme = Theme.of(context).colorScheme;
    final secs = total == 0 ? 0.0 : frame / _plan.fps;
    final slot = _plan.slots.isEmpty || info.isTitle ? null : _plan.slots[info.labelSlot];
    return Material(
      color: Theme.of(context).appBarTheme.backgroundColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 16, 6),
        child: Row(
          children: [
            IconButton.filled(
              tooltip: _playing ? 'Pause preview' : 'Play preview',
              onPressed: total == 0 ? null : _togglePlay,
              icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
            IconButton(
              tooltip: 'Previous photo',
              onPressed: total == 0
                  ? null
                  : () => setState(() {
                        _stopPlay();
                        final cur = info.isTitle ? 0 : info.slot;
                        _frame = cur == 0 && !info.isTitle ? 0 : _plan.frameOfSlot((cur - 1).clamp(0, 1 << 30));
                      }),
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            IconButton(
              tooltip: 'Next photo',
              onPressed: total == 0
                  ? null
                  : () => setState(() {
                        _stopPlay();
                        final next = info.isTitle ? 0 : info.slot + 1;
                        if (next < _plan.slots.length) _frame = _plan.frameOfSlot(next);
                      }),
              icon: const Icon(Icons.skip_next_rounded),
            ),
            Expanded(
              child: Slider(
                value: frame.toDouble(),
                max: (total - 1).clamp(1, 1 << 30).toDouble(),
                onChanged: total == 0
                    ? null
                    : (v) => setState(() {
                          _stopPlay();
                          _frame = v.round();
                        }),
              ),
            ),
            SizedBox(
              width: 210,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${secs.toStringAsFixed(1)}s / ${_fmtDuration(_plan.duration)}',
                      style: const TextStyle(fontFeatures: [ui.FontFeature.tabularFigures()])),
                  Text(
                    slot == null ? (info.isTitle ? 'Title card' : '') : 'Photo ${info.labelSlot + 1} of ${_plan.slots.length} · ${shortDay(slot.date)}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ settings panel

  Widget _panel() {
    final s = _s;
    final dates = _availableDates;
    final b = _buildingId == null ? null : _pr.buildingById(_buildingId!);
    final out = s.outputSize;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          '${_plan.slots.length} photos · ${_fmtDuration(_plan.duration)} · ${out.width.toInt()}×${out.height.toInt()} · ${s.fps} fps',
          style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700),
        ),
        _section('Photos', Icons.photo_library_outlined, [
          DropdownButtonFormField<String?>(
            key: ValueKey('b$_buildingId'),
            initialValue: _buildingId,
            isExpanded: true,
            decoration: _dec('Building / area'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All buildings')),
              for (final x in _pr.buildings) DropdownMenuItem<String?>(value: x.id, child: Text(x.name)),
            ],
            onChanged: (v) => _update(() {
              _buildingId = v;
              _viewId = null;
              _from = null;
              _to = null;
            }),
          ),
          if (b != null)
            DropdownButtonFormField<String?>(
              key: ValueKey('v$_buildingId$_viewId'),
              initialValue: _viewId,
              isExpanded: true,
              decoration: _dec('Camera view'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('All views')),
                for (final v in b.views) DropdownMenuItem<String?>(value: v.id, child: Text(v.name)),
              ],
              onChanged: (v) => _update(() {
                _viewId = v;
                _from = null;
                _to = null;
              }),
            ),
          if (_viewId == null && _buildingId != null)
            const _Hint('Tip: pick one camera view so every frame is shot from the same angle.'),
          if (dates.isNotEmpty)
            Row(
              children: [
                Expanded(child: _dateDrop('From', dates, _from ?? dates.first, (d) => _update(() => _from = d))),
                const SizedBox(width: 10),
                Expanded(child: _dateDrop('To', dates, _to ?? dates.last, (d) => _update(() => _to = d))),
              ],
            ),
          _seg<PhotosPerDate>(
            'Photos from each date',
            s.photosPerDate,
            const {PhotosPerDate.first: 'First photo', PhotosPerDate.all: 'All photos'},
            (v) => _update(() => s.photosPerDate = v),
          ),
        ]),
        _section('Video', Icons.movie_outlined, [
          _seg<VideoAspect>('Shape', s.aspect,
              const {VideoAspect.landscape: '16:9', VideoAspect.square: '1:1', VideoAspect.vertical: '9:16'},
              (v) => _update(() => s.aspect = v)),
          _seg<VideoResolution>(
              'Resolution',
              s.resolution,
              const {
                VideoResolution.hd720: '720p',
                VideoResolution.hd1080: '1080p',
                VideoResolution.qhd1440: '1440p',
                VideoResolution.uhd4k: '4K'
              },
              (v) => _update(() => s.resolution = v)),
          _seg<int>('Frame rate', s.fps, const {24: '24', 30: '30', 60: '60 fps'}, (v) => _update(() => s.fps = v)),
          _seg<Quality>('Quality', s.quality,
              const {Quality.standard: 'Standard', Quality.high: 'High', Quality.maximum: 'Maximum'},
              (v) => _update(() => s.quality = v)),
        ]),
        _section('Timing & motion', Icons.timer_outlined, [
          _slider('Seconds per photo', s.secondsPerPhoto, 0.2, 5, (v) => _update(() => s.secondsPerPhoto = v),
              suffix: 's'),
          _seg<PhotoTransition>('Between photos', s.transition,
              const {PhotoTransition.cut: 'Cut', PhotoTransition.crossfade: 'Cross-fade'},
              (v) => _update(() => s.transition = v)),
          if (s.transition == PhotoTransition.crossfade)
            _slider('Fade length', s.transitionSeconds, 0.1, 2, (v) => _update(() => s.transitionSeconds = v),
                suffix: 's'),
          _seg<PhotoFit>('Photo framing', s.fit,
              const {PhotoFit.fill: 'Fill', PhotoFit.fit: 'Fit', PhotoFit.blurFill: 'Fit + blur'},
              (v) => _update(() => s.fit = v)),
          _switch('Slow zoom (Ken Burns)', s.kenBurns, (v) => _update(() => s.kenBurns = v)),
          _slider('Hold last photo', s.endHoldSeconds, 0, 6, (v) => _update(() => s.endHoldSeconds = v), suffix: 's'),
        ]),
        _section('Text on video', Icons.text_fields_rounded, [
          _switch('Date', s.showDate, (v) => _update(() => s.showDate = v)),
          if (s.showDate)
            _seg<DateStyle>(
              null,
              s.dateStyle,
              const {DateStyle.long: 'Monday, Nov 2…', DateStyle.medium: 'Nov 2, 2026', DateStyle.numeric: '2026-11-02'},
              (v) => _update(() => s.dateStyle = v),
            ),
          _switch('Week number', s.showWeek, (v) => _update(() => s.showWeek = v)),
          _switch('Day counter (Day 1, Day 8…)', s.showDayCounter, (v) => _update(() => s.showDayCounter = v)),
          _switch('Building name', s.showBuilding, (v) => _update(() => s.showBuilding = v)),
          _switch('Camera view', s.showView, (v) => _update(() => s.showView = v)),
          _switch('Project name', s.showProject, (v) => _update(() => s.showProject = v)),
          _switch('Note for each date', s.showNote, (v) => _update(() => s.showNote = v)),
        ]),
        _section('Time symbol', Icons.schedule_rounded, [
          _seg<TimeSymbol>(
            null,
            s.timeSymbol,
            const {
              TimeSymbol.none: 'None',
              TimeSymbol.clock: 'Clock',
              TimeSymbol.calendar: 'Calendar',
              TimeSymbol.hourglass: 'Hourglass'
            },
            (v) => _update(() => s.timeSymbol = v),
          ),
          const _Hint('Clock hands turn as time passes · the calendar flips to each date · the hourglass empties over the video.'),
          _switch('Progress bar with every capture date', s.showProgressBar, (v) => _update(() => s.showProgressBar = v)),
        ]),
        _section('Style', Icons.palette_outlined, [
          _seg<OverlayCorner>(
            'Position',
            s.corner,
            const {
              OverlayCorner.topLeft: '↖',
              OverlayCorner.topRight: '↗',
              OverlayCorner.bottomLeft: '↙',
              OverlayCorner.bottomRight: '↘',
              OverlayCorner.bottomBand: 'Band',
            },
            (v) => _update(() => s.corner = v),
          ),
          _seg<TextSize>('Text size', s.textSize,
              const {TextSize.small: 'S', TextSize.medium: 'M', TextSize.large: 'L', TextSize.extraLarge: 'XL'},
              (v) => _update(() => s.textSize = v)),
          _seg<CardStyle>('Background', s.cardStyle,
              const {CardStyle.glass: 'Glass', CardStyle.solid: 'Solid', CardStyle.none: 'Shadow only'},
              (v) => _update(() => s.cardStyle = v)),
          Text('Accent color', style: Theme.of(context).textTheme.labelLarge),
          Wrap(
            spacing: 10,
            children: [
              for (final c in accentChoices)
                InkWell(
                  onTap: () => _update(() => s.accent = c),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: s.accent == c ? Theme.of(context).colorScheme.onSurface : Colors.black26,
                        width: s.accent == c ? 3 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          _switch('Logo', s.showLogo, (v) => _update(() => s.showLogo = v)),
        ]),
        _section('Title card & music', Icons.music_note_outlined, [
          _switch('Title card at the start', s.titleCard, (v) => _update(() => s.titleCard = v)),
          if (s.titleCard) ...[
            _slider('Title length', s.titleSeconds, 1, 6, (v) => _update(() => s.titleSeconds = v), suffix: 's'),
            TextField(
              controller: _titleC,
              decoration: _dec('Title').copyWith(hintText: _pr.name),
              onChanged: (_) => _update(() {}),
            ),
            TextField(
              controller: _subtitleC,
              decoration: _dec('Subtitle').copyWith(hintText: _scopeLabel),
              onChanged: (_) => _update(() {}),
            ),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  s.musicPath == null ? 'No background music' : p.basename(s.musicPath!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (s.musicPath != null)
                IconButton(
                  tooltip: 'Remove music',
                  onPressed: () => _update(() => s.musicPath = null),
                  icon: const Icon(Icons.close),
                ),
              OutlinedButton.icon(
                onPressed: () async {
                  final f = await openFile(acceptedTypeGroups: const [
                    XTypeGroup(
                      label: 'Audio',
                      extensions: ['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg', 'wma'],
                      uniformTypeIdentifiers: ['public.audio'],
                    ),
                  ]);
                  if (f != null) _update(() => s.musicPath = f.path);
                },
                icon: const Icon(Icons.library_music_outlined),
                label: const Text('Music…'),
              ),
            ],
          ),
          const _Hint('Music loops if it is shorter than the video and fades out at the end. It is not heard in the preview.'),
        ]),
      ],
    );
  }

  InputDecoration _dec(String label) =>
      InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true);

  Widget _section(String title, IconData icon, List<Widget> children) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(title.toUpperCase(),
                  style: TextStyle(
                      fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w800, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 10),
          for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 10), child: c),
          const Divider(),
        ],
      ),
    );
  }

  Widget _seg<T>(String? label, T value, Map<T, String> options, ValueChanged<T> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
        SegmentedButton<T>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            for (final e in options.entries)
              ButtonSegment<T>(value: e.key, label: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          selected: {value},
          onSelectionChanged: (v) => onChanged(v.first),
        ),
      ],
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value,
        onChanged: onChanged,
      );

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> onChanged,
      {String suffix = ''}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const Spacer(),
            Text('${value.toStringAsFixed(value < 10 ? 1 : 0)}$suffix'),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: ((max - min) * 10).round(),
          onChanged: (v) => onChanged((v * 10).roundToDouble() / 10),
        ),
      ],
    );
  }

  Widget _dateDrop(String label, List<DateTime> dates, DateTime value, ValueChanged<DateTime> onChanged) {
    final keys = dates.map(dayKey).toList();
    final current = keys.contains(dayKey(value)) ? dayKey(value) : keys.first;
    return DropdownButtonFormField<String>(
      key: ValueKey('$label$current${keys.length}'),
      initialValue: current,
      isExpanded: true,
      decoration: _dec(label),
      items: [for (final k in keys) DropdownMenuItem(value: k, child: Text(shortDay(parseDay(k)) + ', ${parseDay(k).year}'))],
      onChanged: (k) {
        if (k != null) onChanged(parseDay(k));
      },
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant));
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.plan, this.info, this.cache, this.logo, this.frame);

  final TimelapsePlan plan;
  final FrameInfo info;
  final SlotImageCache cache;
  final ui.Image? logo;
  final int frame;

  @override
  void paint(Canvas canvas, Size size) {
    final out = plan.settings.outputSize;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / out.width, size.height / out.height);
    paintFrame(canvas, out, plan, info, cache.get, logo);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => true;
}
