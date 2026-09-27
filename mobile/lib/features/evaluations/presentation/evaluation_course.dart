import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../courses/data/course_service.dart';
import '../data/evaluation_service.dart';

/// Écran de fin de course côté client : note de 1 à 5 étoiles, avis
/// facultatif, "Envoyer" ou "Ignorer". Affiché automatiquement quand la
/// course passe à `terminee` (voir `SuiviCoursePage`).
class EvaluationCourse extends StatefulWidget {
  const EvaluationCourse({
    super.key,
    required this.course,
    required this.nomChauffeur,
    required this.onTerminer,
    this.service,
    this.titre = 'Vous êtes arrivé !',
    this.libelleIgnorer = 'Ignorer',
    this.libelleRetour = "Retour à l'accueil",
  });

  final CourseFirestore course;
  final String? nomChauffeur;

  /// Retour à l'accueil (après envoi, "Ignorer" ou course déjà notée).
  final VoidCallback onTerminer;

  /// Injectable pour les tests.
  final EvaluationService? service;

  final String titre;
  final String libelleIgnorer;
  final String libelleRetour;

  @override
  State<EvaluationCourse> createState() => _EvaluationCourseState();
}

enum _Etape { verification, saisie, envoi, merci }

class _EvaluationCourseState extends State<EvaluationCourse> {
  static const _libelles = ['Très décevant', 'Décevant', 'Correct', 'Bien', 'Excellent !'];

  late final EvaluationService _service = widget.service ?? EvaluationService();
  final _commentaire = TextEditingController();
  _Etape _etape = _Etape.verification;
  int _note = 0;

  @override
  void initState() {
    super.initState();
    _verifier();
  }

  @override
  void dispose() {
    _commentaire.dispose();
    super.dispose();
  }

  /// Course déjà notée (page rouverte) : on remercie directement.
  Future<void> _verifier() async {
    var deja = false;
    try {
      deja = await _service.dejaEvaluee(widget.course.id);
    } catch (_) {
      // En cas de doute, on propose la notation ; les règles refuseront
      // de toute façon une seconde évaluation.
    }
    if (mounted) setState(() => _etape = deja ? _Etape.merci : _Etape.saisie);
  }

  Future<void> _envoyer() async {
    setState(() => _etape = _Etape.envoi);
    try {
      await _service.evaluer(course: widget.course, note: _note, commentaire: _commentaire.text);
      if (mounted) setState(() => _etape = _Etape.merci);
    } catch (_) {
      if (!mounted) return;
      setState(() => _etape = _Etape.saisie);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Votre avis n'a pas pu être envoyé. Réessayez.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_etape) {
      _Etape.verification => const Center(child: CircularProgressIndicator(color: AppColors.orange)),
      _Etape.merci => _Merci(onTerminer: widget.onTerminer, libelle: widget.libelleRetour),
      _ => _saisie(context),
    };
  }

  Widget _saisie(BuildContext context) {
    final nom = widget.nomChauffeur?.trim();
    final envoi = _etape == _Etape.envoi;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.check_circle_rounded, size: 56, color: AppColors.vert),
          const SizedBox(height: 14),
          Text(
            widget.titre,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            nom == null || nom.isEmpty ? 'Comment s\'est passée votre course ?' : 'Comment s\'est passée votre course avec $nom ?',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppColors.grey, height: 1.4),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  tooltip: i == 1 ? '1 étoile' : '$i étoiles',
                  iconSize: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  onPressed: envoi ? null : () => setState(() => _note = i),
                  icon: Icon(
                    i <= _note ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: i <= _note ? AppColors.or : AppColors.greyBorder,
                  ),
                ),
            ],
          ),
          SizedBox(
            height: 22,
            child: Text(
              _note == 0 ? 'Touchez une étoile pour noter' : _libelles[_note - 1],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: _note == 0 ? AppColors.grey : AppColors.text,
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _commentaire,
            enabled: !envoi,
            maxLines: 3,
            maxLength: EvaluationService.longueurMaxCommentaire,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Laisser un avis (facultatif)',
              filled: true,
              fillColor: AppColors.greyLight,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _note == 0 || envoi ? null : _envoyer,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: envoi
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                  )
                : const Text("Envoyer l'évaluation", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: envoi ? null : widget.onTerminer,
            child: Text(
              widget.libelleIgnorer,
              style: const TextStyle(color: AppColors.grey, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Merci extends StatelessWidget {
  const _Merci({required this.onTerminer, required this.libelle});

  final VoidCallback onTerminer;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.favorite_rounded, size: 52, color: AppColors.orange),
            const SizedBox(height: 16),
            const Text(
              'Merci pour votre avis !',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Il aide les autres clients à choisir en confiance.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: AppColors.grey),
            ),
            const SizedBox(height: 24),
            OutlinedButton(onPressed: onTerminer, child: Text(libelle)),
          ],
        ),
      ),
    );
  }
}

/// "★ 4,8 · 23 avis", ou "Nouveau chauffeur" tant qu'il n'a pas d'avis.
class BadgeNoteChauffeur extends StatelessWidget {
  const BadgeNoteChauffeur({super.key, required this.note, this.taille = 13});

  final NoteChauffeur note;
  final double taille;

  @override
  Widget build(BuildContext context) {
    if (!note.aDesAvis) {
      return Text(
        'Nouveau chauffeur',
        style: TextStyle(fontSize: taille - 0.5, color: AppColors.grey, fontWeight: FontWeight.w600),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: taille + 3, color: AppColors.or),
        const SizedBox(width: 3),
        Text(note.moyenneTexte, style: TextStyle(fontSize: taille, fontWeight: FontWeight.w800)),
        Text(' · ${note.nombreTexte}', style: TextStyle(fontSize: taille - 0.5, color: AppColors.grey)),
      ],
    );
  }
}
