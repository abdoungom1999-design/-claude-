import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_fcfa.dart';
import '../../../core/widgets/onyx_light.dart';
import '../data/portefeuille_service.dart';

/// Historique du portefeuille du client : chaque crédit et débit, avec le
/// solde qui en résulte (livre de comptes tenu par le serveur).
class MouvementsPortefeuillePage extends StatelessWidget {
  MouvementsPortefeuillePage({super.key, PortefeuilleService? service, this.uid})
      : service = service ?? PortefeuilleService();

  final PortefeuilleService service;

  /// Injectable pour les tests ; sinon le client connecté.
  final String? uid;

  @override
  Widget build(BuildContext context) {
    final client = uid ?? FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.fondClair,
      appBar: AppBar(
        backgroundColor: AppColors.fondClairHaut,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.onyx,
        title: const Text(
          'Mouvements du portefeuille',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.onyx),
        ),
      ),
      body: FondOnyxLight(
        child: client == null
            ? const _Vide(message: 'Connectez-vous pour voir votre portefeuille.')
            : ListeMouvements(flux: service.streamMouvements(client)),
      ),
    );
  }
}

/// Liste des mouvements d'un flux (client ou vue Admin).
class ListeMouvements extends StatelessWidget {
  const ListeMouvements({super.key, required this.flux, this.shrinkWrap = false});

  final Stream<List<MouvementPortefeuille>> flux;

  /// Pour l'insérer dans une autre liste (vue Admin).
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MouvementPortefeuille>>(
      stream: flux,
      builder: (context, instantane) {
        if (instantane.hasError) {
          return const _Vide(message: "Impossible de lire l'historique. Vérifiez votre connexion.");
        }
        final mouvements = instantane.data;
        if (mouvements == null) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator(color: AppColors.orange)),
          );
        }
        if (mouvements.isEmpty) {
          return const _Vide(message: 'Aucun mouvement pour le moment. Rechargez votre portefeuille pour commencer.');
        }
        return ListView.separated(
          shrinkWrap: shrinkWrap,
          physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          itemCount: mouvements.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.greyBorder),
          itemBuilder: (_, i) => _LigneMouvement(mouvement: mouvements[i]),
        );
      },
    );
  }
}

class _LigneMouvement extends StatelessWidget {
  const _LigneMouvement({required this.mouvement});

  final MouvementPortefeuille mouvement;

  static String _date(DateTime d) {
    String deux(int n) => n.toString().padLeft(2, '0');
    return '${deux(d.day)}/${deux(d.month)}/${d.year} ${deux(d.hour)}:${deux(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final credit = mouvement.montantFcfa > 0;
    final couleur = credit ? AppColors.orange : AppColors.onyx;
    final creeLe = mouvement.creeLe;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: credit ? AppColors.orangeLight : AppColors.fondClair,
              shape: BoxShape.circle,
            ),
            child: Icon(
              credit ? Icons.south_west_rounded : Icons.north_east_rounded,
              size: 18,
              color: couleur,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mouvement.libelle, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.onyx)),
                if (mouvement.note case final note? when note.isNotEmpty)
                  Text(note, style: const TextStyle(fontSize: 12, color: AppColors.grey)),
                if (creeLe != null)
                  Text(_date(creeLe), style: const TextStyle(fontSize: 12, color: AppColors.grey)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${credit ? '+' : '−'} ${formaterFcfa(mouvement.montantFcfa.abs())}',
                style: TextStyle(fontWeight: FontWeight.w800, color: couleur),
              ),
              Text(
                'Solde ${formaterFcfa(mouvement.soldeApresFcfa)}',
                style: const TextStyle(fontSize: 12, color: AppColors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Vide extends StatelessWidget {
  const _Vide({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.grey, height: 1.4)),
      ),
    );
  }
}
