import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../core/demo/demo_data.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/onyx_vert.dart';
import '../../../../firebase_options.dart';
import '../../../evaluations/data/evaluation_service.dart';

/// Onglet Évaluations du chauffeur. En Firebase réel : sa note moyenne
/// officielle (celle que voient les clients), la répartition des notes
/// et les avis reçus, tirés de la collection `evaluations` (anonymes).
/// En mode démo (pas de projet Firebase configuré) : données de
/// [DemoData], avec badges de compliments façon Uber.
class ConducteurEvaluationsTab extends StatelessWidget {
  const ConducteurEvaluationsTab({super.key, this.service, this.chauffeurId});

  /// Injectables pour les tests.
  final EvaluationService? service;
  final String? chauffeurId;

  @override
  Widget build(BuildContext context) {
    if (!DefaultFirebaseOptions.estConfigure && service == null) {
      return const _EvaluationsDemo();
    }
    final uid = chauffeurId ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    return _EvaluationsReelles(service: service ?? EvaluationService(), chauffeurId: uid);
  }
}

class _EvaluationsReelles extends StatefulWidget {
  const _EvaluationsReelles({required this.service, required this.chauffeurId});

  final EvaluationService service;
  final String chauffeurId;

  @override
  State<_EvaluationsReelles> createState() => _EvaluationsReellesState();
}

class _EvaluationsReellesState extends State<_EvaluationsReelles> {
  late final Stream<NoteChauffeur> _note = widget.service.streamNoteChauffeur(widget.chauffeurId);
  late final Stream<List<EvaluationRecue>> _avis = widget.service.streamEvaluationsRecues(widget.chauffeurId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: StreamBuilder<NoteChauffeur>(
          stream: _note,
          builder: (context, note) => StreamBuilder<List<EvaluationRecue>>(
            stream: _avis,
            builder: (context, avis) {
              if (note.hasError || avis.hasError) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Impossible de charger vos évaluations pour le moment.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.texteDiscret),
                    ),
                  ),
                );
              }
              if (!note.hasData || !avis.hasData) {
                return const Center(child: CircularProgressIndicator(color: AppColors.vert));
              }
              return _VueEvaluations(note: note.data!, avis: avis.data!);
            },
          ),
        ),
      ),
    );
  }
}

class _VueEvaluations extends StatelessWidget {
  const _VueEvaluations({required this.note, required this.avis});

  final NoteChauffeur note;
  final List<EvaluationRecue> avis;

  @override
  Widget build(BuildContext context) {
    final moyenne = note.moyenne;
    final repartition = List.filled(5, 0);
    for (final a in avis) {
      repartition[a.note - 1]++;
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Évaluations', style: styleTitreEcran),
        const SizedBox(height: 18),
        CarteVerre(
          rayon: 28,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                Text(
                  moyenne == null ? '—' : note.moyenneTexte,
                  style: const TextStyle(color: AppColors.texte, fontSize: 52, fontWeight: FontWeight.w800, letterSpacing: -1.5),
                ),
                const SizedBox(height: 8),
                _Etoiles(valeur: moyenne ?? 0, taille: 24),
                const SizedBox(height: 8),
                Text(
                  note.aDesAvis
                      ? 'Basé sur ${note.nombreTexte}'
                      : 'Pas encore d\'avis : vos premières notes apparaîtront ici après vos courses.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.texteDiscret),
                ),
              ],
            ),
          ),
        ),
        if (avis.isNotEmpty) ...[
          const SizedBox(height: 26),
          const Text('Répartition des notes', style: styleTitreSection),
          const SizedBox(height: 12),
          for (var etoiles = 5; etoiles >= 1; etoiles--)
            _LigneRepartition(etoiles: etoiles, nombre: repartition[etoiles - 1], total: avis.length),
          const SizedBox(height: 26),
          const Text('Avis récents', style: styleTitreSection),
          const SizedBox(height: 12),
          for (final a in avis.take(50))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _CarteAvis(avis: a),
            ),
        ],
      ],
    );
  }
}

/// Étoiles pleines, demi-étoile au-delà de ,25 et ,75 arrondi au-dessus.
class _Etoiles extends StatelessWidget {
  const _Etoiles({required this.valeur, required this.taille});

  final double valeur;
  final double taille;

  @override
  Widget build(BuildContext context) {
    const or = AppColors.vert;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            valeur >= i - 0.25
                ? Icons.star_rounded
                : valeur >= i - 0.75
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
            color: valeur >= i - 0.75 ? or : AppColors.bord,
            size: taille,
          ),
      ],
    );
  }
}

class _LigneRepartition extends StatelessWidget {
  const _LigneRepartition({required this.etoiles, required this.nombre, required this.total});

  final int etoiles;
  final int nombre;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Row(
              children: [
                Text('$etoiles', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(width: 2),
                const Icon(Icons.star_rounded, size: 14, color: AppColors.vert),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : nombre / total,
                minHeight: 8,
                backgroundColor: AppColors.carteHaute,
                color: AppColors.vert,
              ),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text('$nombre', textAlign: TextAlign.end, style: const TextStyle(fontSize: 12.5, color: AppColors.texteDiscret)),
          ),
        ],
      ),
    );
  }
}

class _CarteAvis extends StatelessWidget {
  const _CarteAvis({required this.avis});

  final EvaluationRecue avis;

  @override
  Widget build(BuildContext context) {
    final date = avis.creeLe;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Client Sprint', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              _Etoiles(valeur: avis.note.toDouble(), taille: 15),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            avis.commentaire ?? 'Note sans commentaire.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.texteDiscret,
              height: 1.4,
              fontStyle: avis.commentaire == null ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          if (date != null) ...[
            const SizedBox(height: 6),
            Text(
              '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
              style: const TextStyle(fontSize: 11, color: AppColors.texteDiscret),
            ),
          ],
        ],
      ),
    );
  }
}

/// Version démo (sans Firebase), inchangée.
class _EvaluationsDemo extends StatelessWidget {
  const _EvaluationsDemo();

  static const _iconesCompliments = {
    'Excellente conduite': Icons.thumb_up_alt_outlined,
    'Voiture impeccable': Icons.auto_awesome_outlined,
    'Bonne conversation': Icons.chat_bubble_outline_rounded,
    'Trajet efficace': Icons.bolt_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final avis = DemoData.avisConducteur();
    final compliments = DemoData.complimentsConducteur();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Évaluations', style: styleTitreEcran),
            const SizedBox(height: 18),
            CarteVerre(
              rayon: 28,
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    Text(
                      DemoData.noteMoyenneConducteur.toStringAsFixed(2),
                      style: const TextStyle(color: AppColors.texte, fontSize: 52, fontWeight: FontWeight.w800, letterSpacing: -1.5),
                    ),
                    const SizedBox(height: 8),
                    const _Etoiles(valeur: 5, taille: 24),
                    const SizedBox(height: 8),
                    Text(
                      'Basé sur ${avis.length} avis récents',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.texteDiscret),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 26),
            const Text('Compliments reçus', style: styleTitreSection),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final compliment in compliments)
                  _BadgeCompliment(compliment: compliment, icon: _iconesCompliments[compliment.label]),
              ],
            ),
            const SizedBox(height: 26),
            const Text('Avis récents', style: styleTitreSection),
            const SizedBox(height: 12),
            ...avis.map(
              (a) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            a.auteur,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          Row(
                            children: List.generate(
                              5,
                              (i) => Icon(
                                i < a.note ? Icons.star_rounded : Icons.star_border_rounded,
                                color: AppColors.vert,
                                size: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        a.commentaire,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.texteDiscret, height: 1.4),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${a.date.day.toString().padLeft(2, '0')}/'
                        '${a.date.month.toString().padLeft(2, '0')}/'
                        '${a.date.year}',
                        style: const TextStyle(fontSize: 11, color: AppColors.texteDiscret),
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

class _BadgeCompliment extends StatelessWidget {
  const _BadgeCompliment({required this.compliment, this.icon});

  final ComplimentConducteur compliment;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.vertTeinte,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.emoji_events_outlined, size: 16, color: AppColors.vert),
          const SizedBox(width: 8),
          Text(
            compliment.label,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.vert,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${compliment.compte}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.onyx,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
