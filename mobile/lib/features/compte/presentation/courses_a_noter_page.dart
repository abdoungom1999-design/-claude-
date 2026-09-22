import 'package:flutter/material.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/premium_dialog.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/stat_tile.dart';

/// Courses terminées non encore notées par le client.
class CoursesANoterPage extends StatefulWidget {
  const CoursesANoterPage({super.key});

  @override
  State<CoursesANoterPage> createState() => _CoursesANoterPageState();
}

class _CoursesANoterPageState extends State<CoursesANoterPage> {
  List<CourseHistorique> get _aNoter =>
      DemoData.historique().where((c) => c.noteDonnee == null).toList();

  Future<void> _noter(CourseHistorique course) async {
    final note = await showDialog<int>(
      context: context,
      builder: (_) => _DialogNotation(course: course),
    );
    if (note == null) return;
    setState(() => course.noteDonnee = note);
    if (!mounted) return;
    PremiumDialog.afficher(
      context,
      icon: Icons.star_rounded,
      titre: 'Merci pour votre avis !',
      message: 'Votre note a bien été transmise au conducteur.',
      succes: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final courses = _aNoter;

    return Scaffold(
      appBar: AppBar(title: const Text('Courses à noter')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            StatTile(
              label: 'Avis en attente',
              valeur: '${courses.length}',
              icon: Icons.star_border_rounded,
              accent: courses.isEmpty ? Colors.green.shade600 : AppColors.orange,
            ),
            const SizedBox(height: 20),
            if (courses.isEmpty)
              const AppCard(
                child: Column(
                  children: [
                    Text('😊', style: TextStyle(fontSize: 40)),
                    SizedBox(height: 12),
                    Text(
                      'Tout est noté !',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Merci de partager vos retours sur vos dernières courses.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: AppColors.grey),
                    ),
                  ],
                ),
              )
            else
              ...courses.map(
                (course) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${course.adresseDepart} → ${course.adresseArrivee}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${course.prixFcfa} FCFA · '
                          '${course.date.day.toString().padLeft(2, '0')}/'
                          '${course.date.month.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 12, color: AppColors.grey),
                        ),
                        const SizedBox(height: 12),
                        PrimaryButton(
                          label: 'Noter cette course',
                          icon: Icons.star_border_rounded,
                          onPressed: () => _noter(course),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DialogNotation extends StatefulWidget {
  const _DialogNotation({required this.course});

  final CourseHistorique course;

  @override
  State<_DialogNotation> createState() => _DialogNotationState();
}

class _DialogNotationState extends State<_DialogNotation> {
  int _note = 5;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Comment s\'est passée votre course ?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final valeur = i + 1;
                return IconButton(
                  onPressed: () => setState(() => _note = valeur),
                  icon: Icon(
                    valeur <= _note ? Icons.star_rounded : Icons.star_border_rounded,
                    color: Colors.amber.shade700,
                    size: 32,
                  ),
                );
              }),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: 'Envoyer ma note',
              onPressed: () => Navigator.of(context).pop(_note),
            ),
          ],
        ),
      ),
    );
  }
}
