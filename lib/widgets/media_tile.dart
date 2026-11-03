import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../library_store.dart';
import '../models.dart';

/// A thumbnail for a photo or video. Photos are decoded at a reduced size for
/// the grid only; the original file on disk is never changed.
class MediaThumb extends StatelessWidget {
  const MediaThumb({super.key, required this.item, this.fit = BoxFit.cover, this.decodeWidth = 520});

  final MediaItem item;
  final BoxFit fit;
  final int decodeWidth;

  @override
  Widget build(BuildContext context) {
    final store = context.read<LibraryStore>();
    final file = store.fileFor(item);
    final scheme = Theme.of(context).colorScheme;

    if (item.isDisplayablePhoto) {
      return Image.file(
        file,
        fit: fit,
        cacheWidth: decodeWidth,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 200),
          child: child,
        ),
        errorBuilder: (context, e, s) => _FileBadge(item: item, icon: Icons.broken_image_outlined),
      );
    }
    if (item.type == MediaType.video) {
      return Container(
        color: const Color(0xFF0E1418),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
              ),
            ),
          ],
        ),
      );
    }
    return _FileBadge(item: item, icon: Icons.image_outlined);
  }
}

class _FileBadge extends StatelessWidget {
  const _FileBadge({required this.item, required this.icon});
  final MediaItem item;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: scheme.onSurfaceVariant),
          const SizedBox(height: 6),
          Text(item.extension.replaceFirst('.', '').toUpperCase(),
              style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class MediaTile extends StatefulWidget {
  const MediaTile({
    super.key,
    required this.item,
    required this.onOpen,
    required this.selecting,
    required this.selected,
    required this.onToggleSelect,
    this.onTimelapse,
    this.decodeWidth = 520,
    this.fit = BoxFit.cover,
  });

  final BoxFit fit;

  final MediaItem item;
  final VoidCallback onOpen;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggleSelect;

  /// Plays a timelapse of this building/view across all weeks.
  final VoidCallback? onTimelapse;
  final int decodeWidth;

  @override
  State<MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<MediaTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = widget.item;
    final showCheck = widget.selecting || _hover;
    final isVideo = item.type == MediaType.video;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.selected ? scheme.primary : (Theme.of(context).dividerTheme.color ?? Colors.transparent),
            width: widget.selected ? 3 : 1,
          ),
          boxShadow: _hover ? const [BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 4))] : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: widget.selecting ? widget.onToggleSelect : widget.onOpen,
                    onLongPress: widget.onToggleSelect,
                    onSecondaryTap: widget.onToggleSelect,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(
                          color: widget.fit == BoxFit.contain ? const Color(0xFF0B1014) : null,
                          child: MediaThumb(item: item, decodeWidth: widget.decodeWidth, fit: widget.fit),
                        ),
                        if (showCheck)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: widget.onToggleSelect,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: widget.selected ? scheme.primary : const Color(0x88000000),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 1.5),
                                ),
                                padding: const EdgeInsets.all(3),
                                child: Icon(Icons.check,
                                    size: 18, color: widget.selected ? Colors.white : Colors.white54),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 50,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  child: Row(
                    children: [
                      Icon(isVideo ? Icons.videocam_outlined : Icons.photo_outlined,
                          size: 18, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(item.fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                            Text(prettySize(item.sizeBytes),
                                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      if (widget.onTimelapse != null)
                        Tooltip(
                          message: 'Play a timelapse of this view across all weeks',
                          child: TextButton.icon(
                            onPressed: widget.onTimelapse,
                            icon: const Icon(Icons.movie_creation_outlined, size: 20),
                            label: const Text('Timelapse'),
                          ),
                        ),
                      IconButton(
                        tooltip: isVideo ? 'Play video' : 'Open full size',
                        onPressed: widget.onOpen,
                        icon: Icon(isVideo ? Icons.play_circle_outline_rounded : Icons.open_in_full_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
