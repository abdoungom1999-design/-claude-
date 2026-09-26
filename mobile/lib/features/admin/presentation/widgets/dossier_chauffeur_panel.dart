import 'dart:math';

import 'package:flutter/material.dart';
import '../../../../core/models/statut_compte.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/image_document.dart';
import '../../data/admin_kyc_service.dart';
import 'visionneuse_document.dart';

const _documentsKyc = [
  ('permis', 'Permis de conduire', Icons.badge_outlined),
  ('carteGrise', 'Carte grise', Icons.description_outlined),
  ('attestationVtc', 'Attestation VTC', Icons.shield_outlined),
];

/// Ouvre le Dossier Chauffeur dans un panneau latéral large : identité,
/// pièces justificatives (agrandissables en plein écran), validation
/// KYC et modération du compte. Écoute le document Firestore du
/// chauffeur en direct : chaque décision s'y reflète immédiatement.
Future<void> ouvrirDossierChauffeur(
  BuildContext context, {
  required String uid,
  required AdminKycService service,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fermer le dossier',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, __, ___) => Align(
      alignment: Alignment.centerRight,
      child: _DossierChauffeurPanel(uid: uid, service: service),
    ),
    transitionBuilder: (_, animation, __, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

class _DossierChauffeurPanel extends StatefulWidget {
  const _DossierChauffeurPanel({required this.uid, required this.service});

  final String uid;
  final AdminKycService service;

  @override
  State<_DossierChauffeurPanel> createState() => _DossierChauffeurPanelState();
}

class _DossierChauffeurPanelState extends State<_DossierChauffeurPanel> {
  late final Stream<ConducteurKycAdmin?> _flux = widget.service.streamConducteur(widget.uid);
  bool _enCours = false;
  String? _erreur;

  Future<void> _executer(Future<void> Function() action) async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _erreur = "L'opération a échoué. Réessayez.");
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _moderer(ConducteurKycAdmin c, String statut) async {
    if (statut != StatutCompte.actif) {
      final confirme = await _confirmerSanction(c, statut);
      if (confirme != true) return;
    }
    await _executer(() => widget.service.definirStatutCompte(c.id, statut));
  }

  Future<bool?> _confirmerSanction(ConducteurKycAdmin c, String statut) {
    final bannir = statut == StatutCompte.banni;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(bannir ? 'Bannir ${c.nom} ?' : 'Suspendre ${c.nom} ?'),
        content: Text(
          bannir
              ? "Le chauffeur est déconnecté immédiatement et ne pourra plus jamais accéder à l'application. "
                  "Cette décision n'est pas réversible depuis le panneau Admin."
              : 'Le chauffeur est déconnecté immédiatement et ne peut plus se connecter '
                  "jusqu'à la réactivation de son compte.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: bannir ? Colors.red.shade700 : AppColors.orange),
            child: Text(bannir ? 'Bannir définitivement' : 'Suspendre'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final largeur = min(780.0, MediaQuery.sizeOf(context).width * 0.94);

    return Material(
      color: AppColors.background,
      elevation: 16,
      child: SizedBox(
        width: largeur,
        height: double.infinity,
        child: StreamBuilder<ConducteurKycAdmin?>(
          stream: _flux,
          builder: (context, snapshot) {
            final c = snapshot.data;
            if (c == null) {
              return Center(
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const CircularProgressIndicator(color: AppColors.orange)
                    : const Text('Chauffeur introuvable.'),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
              children: [
                _EnTete(conducteur: c),
                const SizedBox(height: 28),
                const _TitreSection('Pièces justificatives'),
                const SizedBox(height: 4),
                const Text(
                  'Cliquez sur une pièce pour l\'ouvrir en plein écran (zoom, rotation).',
                  style: TextStyle(fontSize: 12.5, color: AppColors.grey),
                ),
                const SizedBox(height: 14),
                for (final (cle, label, icone) in _documentsKyc) ...[
                  _PieceJustificative(label: label, icone: icone, source: c.documents[cle] as String?),
                  const SizedBox(height: 14),
                ],
                const SizedBox(height: 14),
                const _TitreSection('Validation du dossier (KYC)'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _BoutonAction(
                        label: 'Rejeter le dossier',
                        icone: Icons.close_rounded,
                        couleur: Colors.redAccent,
                        plein: false,
                        onPressed: _enCours || c.statutValidation == 'rejete'
                            ? null
                            : () => _executer(() => widget.service.rejeterConducteur(c.id)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _BoutonAction(
                        label: 'Approuver le chauffeur',
                        icone: Icons.check_rounded,
                        couleur: AppColors.vert,
                        onPressed: _enCours || c.statutValidation == 'valide' || !c.aDesDocuments
                            ? null
                            : () => _executer(() => widget.service.approuverConducteur(c.id)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                const _TitreSection('Modération du compte'),
                const SizedBox(height: 12),
                _ZoneModeration(
                  conducteur: c,
                  enCours: _enCours,
                  onModerer: (statut) => _moderer(c, statut),
                ),
                if (_erreur != null) ...[
                  const SizedBox(height: 14),
                  Text(_erreur!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EnTete extends StatelessWidget {
  const _EnTete({required this.conducteur});

  final ConducteurKycAdmin conducteur;

  @override
  Widget build(BuildContext context) {
    final c = conducteur;
    final vehicule = [c.vehiculeId, c.plaqueImmatriculation]
        .where((v) => v != null && v.isNotEmpty)
        .join(' - ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipOval(
          child: ImageDocument(
            source: c.documents['photoProfil'] as String?,
            width: 68,
            height: 68,
            placeholder: Container(
              width: 68,
              height: 68,
              color: AppColors.orange,
              alignment: Alignment.center,
              child: Text(
                c.nom.isNotEmpty ? c.nom[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('DOSSIER CHAUFFEUR',
                  style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: AppColors.grey, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(c.nom, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                [c.telephone, if (vehicule.isNotEmpty) vehicule].where((v) => v.isNotEmpty).join(' · '),
                style: const TextStyle(fontSize: 13, color: AppColors.grey),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  BadgeStatutValidation(statutValidation: c.statutValidation),
                  BadgeStatutCompte(statutCompte: c.statutCompte),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Fermer',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}

class _PieceJustificative extends StatelessWidget {
  const _PieceJustificative({required this.label, required this.icone, required this.source});

  final String label;
  final IconData icone;
  final String? source;

  @override
  Widget build(BuildContext context) {
    final envoyee = source != null && source!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.greyBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Icon(icone, size: 19),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (envoyee)
                  TextButton.icon(
                    onPressed: () => ouvrirVisionneuseDocument(context, titre: label, source: source!),
                    icon: const Icon(Icons.open_in_full_rounded, size: 16),
                    label: const Text('Plein écran'),
                  )
                else
                  const Text('Non envoyé', style: TextStyle(fontSize: 12.5, color: AppColors.grey)),
              ],
            ),
          ),
          InkWell(
            onTap: envoyee ? () => ouvrirVisionneuseDocument(context, titre: label, source: source!) : null,
            child: Container(
              height: 280,
              color: const Color(0xFF15171C),
              child: ImageDocument(
                source: source,
                width: double.infinity,
                height: 280,
                fit: BoxFit.contain,
                placeholder: const Center(
                  child: Icon(Icons.image_not_supported_outlined, color: Colors.white24, size: 36),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoneModeration extends StatelessWidget {
  const _ZoneModeration({required this.conducteur, required this.enCours, required this.onModerer});

  final ConducteurKycAdmin conducteur;
  final bool enCours;
  final ValueChanged<String> onModerer;

  @override
  Widget build(BuildContext context) {
    final statut = conducteur.statutCompte;

    if (statut == StatutCompte.banni) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.gpp_bad_rounded, color: Colors.red.shade700),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                "Compte banni définitivement. Le chauffeur ne peut plus accéder à l'application.",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          statut == StatutCompte.suspendu
              ? 'Compte suspendu : le chauffeur ne peut pas se connecter. Vous pouvez le réactiver ou le bannir.'
              : 'Une sanction déconnecte immédiatement le chauffeur, même si son dossier KYC est validé.',
          style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: statut == StatutCompte.suspendu
                  ? _BoutonAction(
                      label: 'Réactiver le compte',
                      icone: Icons.lock_open_rounded,
                      couleur: AppColors.vert,
                      onPressed: enCours ? null : () => onModerer(StatutCompte.actif),
                    )
                  : _BoutonAction(
                      label: 'Suspendre le compte',
                      icone: Icons.pause_circle_outline_rounded,
                      couleur: AppColors.orange,
                      onPressed: enCours ? null : () => onModerer(StatutCompte.suspendu),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BoutonAction(
                label: 'Bannir définitivement',
                icone: Icons.block_rounded,
                couleur: Colors.red.shade700,
                onPressed: enCours ? null : () => onModerer(StatutCompte.banni),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TitreSection extends StatelessWidget {
  const _TitreSection(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Text(texte, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800));
  }
}

class _BoutonAction extends StatelessWidget {
  const _BoutonAction({
    required this.label,
    required this.icone,
    required this.couleur,
    required this.onPressed,
    this.plein = true,
  });

  final String label;
  final IconData icone;
  final Color couleur;
  final VoidCallback? onPressed;
  final bool plein;

  @override
  Widget build(BuildContext context) {
    final forme = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    const marge = EdgeInsets.symmetric(vertical: 16);

    if (!plein) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icone, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: couleur,
          side: BorderSide(color: onPressed == null ? AppColors.greyBorder : couleur),
          padding: marge,
          shape: forme,
        ),
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icone, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(backgroundColor: couleur, padding: marge, shape: forme),
    );
  }
}

class BadgeStatutValidation extends StatelessWidget {
  const BadgeStatutValidation({super.key, required this.statutValidation});

  final String? statutValidation;

  @override
  Widget build(BuildContext context) {
    final (label, couleur) = switch (statutValidation) {
      'valide' => ('KYC validé', AppColors.vert),
      'en_attente' => ('KYC en attente', AppColors.orange),
      'rejete' => ('KYC rejeté', Colors.redAccent),
      _ => ('KYC non soumis', AppColors.grey),
    };
    return _Pastille(label: label, couleur: couleur);
  }
}

class BadgeStatutCompte extends StatelessWidget {
  const BadgeStatutCompte({super.key, required this.statutCompte});

  final String statutCompte;

  @override
  Widget build(BuildContext context) {
    final (label, couleur) = switch (statutCompte) {
      StatutCompte.suspendu => ('Suspendu', AppColors.orange),
      StatutCompte.banni => ('Banni', Colors.red.shade700),
      _ => ('Actif', AppColors.vert),
    };
    return _Pastille(label: label, couleur: couleur);
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille({required this.label, required this.couleur});

  final String label;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: couleur, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
