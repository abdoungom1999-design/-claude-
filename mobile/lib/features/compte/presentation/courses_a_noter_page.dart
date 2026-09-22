import 'package:flutter/material.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/premium_dialog.dart';
import '../../../core/widgets/primary_button.dart';

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
        child: courses.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Vous avez noté toutes vos dernières courses. Merci !',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.grey),
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: courses.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final course = courses[index];
                  return AppCard(
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
                  );
                },
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
