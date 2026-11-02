import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

/// Plays one or more videos in order (e.g. every week's site video back to
/// back), showing which week is on screen.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    super.key,
    required this.files,
    required this.labels,
    this.startIndex = 0,
  });

  final List<String> files;
  final List<String> labels;
  final int startIndex;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  StreamSubscription<Playlist>? _sub;
  late int _index = widget.startIndex;

  @override
  void initState() {
    super.initState();
    _sub = _player.stream.playlist.listen((pl) {
      if (mounted) setState(() => _index = pl.index);
    });
    _player.open(
      Playlist(
        [for (final f in widget.files) Media(Uri.file(f).toString())],
        index: widget.startIndex,
      ),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.files.length;
    final label = _index < widget.labels.length ? widget.labels[_index] : '';
    final name = _index < n ? p.basename(widget.files[_index]) : '';

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.pageDown): () => _player.next(),
        const SingleActivator(LogicalKeyboardKey.pageUp): () => _player.previous(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(n > 1 ? 'Video ${_index + 1} of $n · $name' : name,
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
            actions: [
              if (n > 1) ...[
                IconButton(
                  tooltip: 'Previous video (PgUp)',
                  onPressed: _index > 0 ? () => _player.previous() : null,
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                IconButton(
                  tooltip: 'Next video (PgDn)',
                  onPressed: _index < n - 1 ? () => _player.next() : null,
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ],
              const SizedBox(width: 8),
            ],
          ),
          body: Video(controller: _controller),
        ),
      ),
    );
  }
}
