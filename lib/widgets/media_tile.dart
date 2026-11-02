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
  });

  final MediaItem item;
  final VoidCallback onOpen;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggleSelect;

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
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.selecting ? widget.onToggleSelect : widget.onOpen,
        onLongPress: widget.onToggleSelect,
        onSecondaryTap: widget.onToggleSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.selected ? scheme.primary : Colors.transparent,
              width: 3,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                MediaThumb(item: item),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 18, 8, 6),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xCC000000)],
                      ),
                    ),
                    child: Row(
                      children: [
                        if (item.type == MediaType.video)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.videocam, size: 14, color: Colors.white70),
                          ),
                        Expanded(
                          child: Text(
                            item.originalName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                        Text(prettySize(item.sizeBytes),
                            style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
                if (showCheck)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: widget.onToggleSelect,
                      child: Container(
                        decoration: BoxDecoration(
                          color: widget.selected ? scheme.primary : const Color(0x88000000),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: Icon(Icons.check,
                            size: 16,
                            color: widget.selected ? Colors.white : Colors.white54),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
