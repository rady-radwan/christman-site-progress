import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../library_store.dart';
import '../models.dart';
import 'media_tile.dart';

/// Icons a project can use as its symbol on the home page.
const projectIcons = <String, IconData>{
  'apartment': Icons.apartment_rounded,
  'hospital': Icons.local_hospital_rounded,
  'business': Icons.business_rounded,
  'school': Icons.school_rounded,
  'factory': Icons.factory_rounded,
  'warehouse': Icons.warehouse_rounded,
  'home': Icons.home_work_rounded,
  'domain': Icons.domain_rounded,
  'construction': Icons.construction_rounded,
  'engineering': Icons.engineering_rounded,
  'architecture': Icons.architecture_rounded,
  'foundation': Icons.foundation_rounded,
  'crane': Icons.precision_manufacturing_rounded,
  'tunnel': Icons.subway_rounded,
  'bridge': Icons.water_rounded,
  'road': Icons.add_road_rounded,
  'terrain': Icons.terrain_rounded,
  'park': Icons.park_rounded,
  'stadium': Icons.stadium_rounded,
  'hotel': Icons.hotel_rounded,
  'store': Icons.storefront_rounded,
  'church': Icons.church_rounded,
  'power': Icons.bolt_rounded,
  'drone': Icons.flight_rounded,
};

const coverColors = <int>[
  0xFFE8742A, 0xFF1E2A33, 0xFF2F6FB0, 0xFF2E8B57, 0xFF7B4FB8,
  0xFFC0392B, 0xFFB8860B, 0xFF00838F, 0xFF5D6D7E, 0xFFAD1457,
];

/// The picture at the top of a project card.
class ProjectCover extends StatelessWidget {
  const ProjectCover({super.key, required this.project, this.iconSize = 64});

  final Project project;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final store = context.read<LibraryStore>();
    switch (project.coverMode) {
      case CoverMode.image:
        final f = store.coverFile(project);
        if (f != null) {
          return Image.file(
            f,
            fit: BoxFit.cover,
            cacheWidth: 900,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => _iconCover(context),
          );
        }
        return _iconCover(context);
      case CoverMode.icon:
        return _iconCover(context);
      case CoverMode.auto:
        final photo = project.coverPhoto;
        return photo == null ? _iconCover(context) : MediaThumb(item: photo, decodeWidth: 900);
    }
  }

  Widget _iconCover(BuildContext context) {
    final c = Color(project.coverColor);
    final hsl = HSLColor.fromColor(c);
    final darker = hsl.withLightness((hsl.lightness - 0.18).clamp(0.0, 1.0)).toColor();
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c, darker],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(projectIcons[project.coverIcon] ?? Icons.apartment_rounded,
          size: iconSize, color: Colors.white.withValues(alpha: 0.95)),
    );
  }
}
