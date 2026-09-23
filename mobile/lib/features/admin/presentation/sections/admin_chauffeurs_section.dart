import 'package:flutter/material.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../firebase_options.dart';
import '../../data/admin_kyc_service.dart';
import '../../data/admin_repository.dart';
import '../widgets/examen_dossier_dialog.dart';

/// Page "Gestion des Chauffeurs" : supervision KYC.
///
/// En Firebase réel ([DefaultFirebaseOptions.estConfigure]), branchée
/// en temps réel sur la vraie collection Firestore `users` (voir
/// [AdminKycService]) : liste tous les chauffeurs avec leur vrai
/// `statutValidation`, et permet d'examiner leurs documents (voir
/// [afficherExamenDossierDialog]) pour approuver ou rejeter leur
/// dossier.
///
/// En mode démo (pas de projet Firebase configuré), conserve
/// entièrement l'ancien tableau connecté à [AdminRepository] (même
/// source de données démo qu'avant) : ce repository n'est pas migré,
/// `statutValidation` n'existe pas côté [DemoData].
class AdminChauffeursSection extends StatefulWidget {
  const AdminChauffeursSection({super.key});

  @override
  State<AdminChauffeursSection> createState() => _AdminChauffeursSectionState();
}

class _AdminChauffeursSectionState extends State<AdminChauffeursSection> {
  final _repository = AdminRepository();
  List<ConducteurAdmin> _conducteurs = [];
  bool _chargement = true;
  final Set<String> _enCours = {};

  @override
  void initState() {
    super.initState();
    if (!DefaultFirebaseOptions.estConfigure) _charger();
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    try {
      final conducteurs = await _repository.listerConducteurs();
      if (mounted) setState(() => _conducteurs = conducteurs);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _valider(ConducteurAdmin c) async {
    setState(() => _enCours.add(c.id));
    try {
      await _repository.validerConducteur(c.id);
      await _charger();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Documents de ${c.nom} validés.')));
    } finally {
      if (mounted) setState(() => _enCours.remove(c.id));
    }
  }

  Future<void> _basculerBlocage(ConducteurAdmin c) async {
    setState(() => _enCours.add(c.id));
    try {
      if (c.suspendu) {
        await _repository.debloquerConducteur(c.id);
      } else {
        await _repository.bloquerConducteur(c.id);
      }
      await _charger();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            c.suspendu ? '${c.nom} a été débloqué(e).' : '${c.nom} a été bloqué(e).',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _enCours.remove(c.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (DefaultFirebaseOptions.estConfigure) {
      return const _ChauffeursReelsSection();
    }
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Tous les chauffeurs',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              Text(
                '${_conducteurs.length} chauffeur(s)',
                style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_chargement)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.orange),
              ),
            )
          else ...[
            const _EnTeteTableau(),
            const Divider(height: 24, color: AppColors.greyBorder),
            for (final c in _conducteurs)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _LigneChauffeur(
                  conducteur: c,
                  enCours: _enCours.contains(c.id),
                  onValider: () => _valider(c),
                  onBasculerBlocage: () => _basculerBlocage(c),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _EnTeteTableau extends StatelessWidget {
  const _EnTeteTableau();

  static const _style = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w700,
    color: AppColors.grey,
    letterSpacing: 0.4,
  );

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SizedBox(width: 46),
        SizedBox(width: 14),
        Expanded(flex: 3, child: Text('Chauffeur', style: _style)),
        Expanded(flex: 2, child: Text('Véhicule', style: _style)),
        SizedBox(width: 80, child: Text('Note', style: _style)),
        SizedBox(width: 110, child: Text('Statut', style: _style)),
        SizedBox(width: 190, child: Text('Actions', style: _style)),
      ],
    );
  }
}

class _LigneChauffeur extends StatelessWidget {
  const _LigneChauffeur({
    required this.conducteur,
    required this.enCours,
    required this.onValider,
    required this.onBasculerBlocage,
  });

  final ConducteurAdmin conducteur;
  final bool enCours;
  final VoidCallback onValider;
  final VoidCallback onBasculerBlocage;

  String get _initiales {
    final mots = conducteur.nom.trim().split(RegExp(r'\s+'));
    if (mots.isEmpty) return '?';
    final premiere = mots.first.isNotEmpty ? mots.first[0] : '';
    final derniere = mots.length > 1 && mots.last.isNotEmpty ? mots.last[0] : '';
    return '$premiere$derniere'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.orange, AppColors.orangeDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              _initiales,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(conducteur.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  conducteur.telephone,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              conducteur.vehiculeId ?? 'Non renseigné',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          SizedBox(
            width: 80,
            child: conducteur.note > 0
                ? Row(
                    children: [
                      const Icon(Icons.star_rounded, size: 15, color: Colors.amber),
                      const SizedBox(width: 3),
                      Text(conducteur.note.toStringAsFixed(1)),
                    ],
                  )
                : const Text('—', style: TextStyle(color: AppColors.grey)),
          ),
          SizedBox(width: 110, child: _BadgeStatutChauffeur(conducteur: conducteur)),
          SizedBox(
            width: 190,
            child: enCours
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.orange),
                  )
                : Row(
                    children: [
                      if (!conducteur.estValide)
                        IconButton(
                          onPressed: onValider,
                          tooltip: 'Valider les documents',
                          icon: const Icon(
                            Icons.verified_outlined,
                            color: AppColors.vert,
                            size: 20,
                          ),
                        ),
                      TextButton.icon(
                        onPressed: onBasculerBlocage,
                        icon: Icon(
                          conducteur.suspendu
                              ? Icons.lock_open_rounded
                              : Icons.block_rounded,
                          size: 16,
                          color: conducteur.suspendu ? AppColors.vert : Colors.redAccent,
                        ),
                        label: Text(
                          conducteur.suspendu ? 'Débloquer' : 'Bloquer',
                          style: TextStyle(
                            fontSize: 12,
                            color: conducteur.suspendu ? AppColors.vert : Colors.redAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _BadgeStatutChauffeur extends StatelessWidget {
  const _BadgeStatutChauffeur({required this.conducteur});

  final ConducteurAdmin conducteur;

  @override
  Widget build(BuildContext context) {
    final (label, couleur) = conducteur.suspendu
        ? ('Suspendu', Colors.redAccent)
        : conducteur.estValide
        ? ('Actif', AppColors.vert)
        : ('En attente', AppColors.orange);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(color: couleur, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Tableau "Gestion des Chauffeurs" branché en temps réel sur Firestore
/// (voir [AdminKycService.streamConducteurs]), affiché à la place de
/// l'ancien tableau démo dès que Firebase est configuré.
class _ChauffeursReelsSection extends StatelessWidget {
  const _ChauffeursReelsSection();

  @override
  Widget build(BuildContext context) {
    final service = AdminKycService();

    return AppCard(
      padding: const EdgeInsets.all(24),
      child: StreamBuilder<List<ConducteurKycAdmin>>(
        stream: service.streamConducteurs(),
        builder: (context, snapshot) {
          final conducteurs = snapshot.data ?? [];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Tous les chauffeurs',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${conducteurs.length} chauffeur(s)',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (!snapshot.hasData)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: CircularProgressIndicator(color: AppColors.orange)),
                )
              else if (conducteurs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(
                    child: Text('Aucun chauffeur inscrit pour le moment.', style: TextStyle(color: AppColors.grey)),
                  ),
                )
              else ...[
                const _EnTeteTableauReel(),
                const Divider(height: 24, color: AppColors.greyBorder),
                for (final c in conducteurs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _LigneChauffeurReel(
                      conducteur: c,
                      onExaminer: c.aDesDocuments
                          ? () => afficherExamenDossierDialog(context, conducteur: c, service: service)
                          : null,
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _EnTeteTableauReel extends StatelessWidget {
  const _EnTeteTableauReel();

  static const _style = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w700,
    color: AppColors.grey,
    letterSpacing: 0.4,
  );

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SizedBox(width: 46),
        SizedBox(width: 14),
        Expanded(flex: 3, child: Text('Chauffeur', style: _style)),
        Expanded(flex: 2, child: Text('Véhicule', style: _style)),
        SizedBox(width: 130, child: Text('Statut du dossier', style: _style)),
        SizedBox(width: 170, child: Text('Actions', style: _style)),
      ],
    );
  }
}

class _LigneChauffeurReel extends StatelessWidget {
  const _LigneChauffeurReel({required this.conducteur, required this.onExaminer});

  final ConducteurKycAdmin conducteur;
  final VoidCallback? onExaminer;

  String get _initiales {
    final mots = conducteur.nom.trim().split(RegExp(r'\s+'));
    if (mots.isEmpty) return '?';
    final premiere = mots.first.isNotEmpty ? mots.first[0] : '';
    final derniere = mots.length > 1 && mots.last.isNotEmpty ? mots.last[0] : '';
    return '$premiere$derniere'.toUpperCase();
  }

  String get _vehicule {
    final valeur = [conducteur.vehiculeId, conducteur.plaqueImmatriculation]
        .where((v) => v != null && v.isNotEmpty)
        .join(' - ');
    return valeur.isEmpty ? 'Non renseigné' : valeur;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.orange, AppColors.orangeDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              _initiales,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(conducteur.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  conducteur.telephone,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(_vehicule, style: const TextStyle(fontSize: 13)),
          ),
          SizedBox(width: 130, child: _BadgeStatutValidation(statutValidation: conducteur.statutValidation)),
          SizedBox(
            width: 170,
            child: onExaminer != null
                ? OutlinedButton.icon(
                    onPressed: onExaminer,
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text('Examiner', style: TextStyle(fontSize: 12.5)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      side: const BorderSide(color: AppColors.greyBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  )
                : const Text(
                    'Aucun document',
                    style: TextStyle(fontSize: 12, color: AppColors.grey),
                  ),
          ),
        ],
      ),
    );
  }
}

class _BadgeStatutValidation extends StatelessWidget {
  const _BadgeStatutValidation({required this.statutValidation});

  final String? statutValidation;

  @override
  Widget build(BuildContext context) {
    final (label, couleur) = switch (statutValidation) {
      'valide' => ('Validé', AppColors.vert),
      'en_attente' => ('En attente', AppColors.orange),
      'rejete' => ('Rejeté', Colors.redAccent),
      _ => ('Non soumis', AppColors.grey),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(color: couleur, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}
