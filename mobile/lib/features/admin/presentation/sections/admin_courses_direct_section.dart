import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/demo/admin_demo_data.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';

/// Page "Courses en direct" : carte (OpenStreetMap, sans clé API) avec
/// les chauffeurs actuellement en course positionnés dessus, et une
/// petite carte d'info par course sur le côté.
class AdminCoursesDirectSection extends StatelessWidget {
  const AdminCoursesDirectSection({super.key});

  static const _centreDakar = LatLng(14.6928, -17.4467);

  @override
  Widget build(BuildContext context) {
    final courses = AdminDemoData.coursesEnDirect();

    return SizedBox(
      height: 620,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: AppCard(
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: FlutterMap(
                  options: const MapOptions(
                    initialCenter: _centreDakar,
                    initialZoom: 12.5,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'sn.groupesantine.sprint',
                    ),
                    MarkerLayer(
                      markers: [
                        for (final course in courses)
                          Marker(
                            point: LatLng(course.latitude, course.longitude),
                            width: 46,
                            height: 46,
                            child: const _MarqueurChauffeur(),
                          ),
                      ],
                    ),
                    const RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('© OpenStreetMap contributors'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 1,
            child: ListView(
              children: [
                Text(
                  '${courses.length} courses en cours',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                for (final course in courses)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _CarteCourseEnDirect(course: course),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MarqueurChauffeur extends StatelessWidget {
  const _MarqueurChauffeur();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.orange,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: AppColors.orange.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 20),
    );
  }
}

class _CarteCourseEnDirect extends StatelessWidget {
  const _CarteCourseEnDirect({required this.course});

  final CourseEnDirect course;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.vert,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Course ${course.id}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            course.description,
            style: const TextStyle(fontSize: 12.5, color: AppColors.text),
          ),
          const SizedBox(height: 6),
          Text(
            'Chauffeur : ${course.chauffeur}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
          ),
        ],
      ),
    );
  }
}
