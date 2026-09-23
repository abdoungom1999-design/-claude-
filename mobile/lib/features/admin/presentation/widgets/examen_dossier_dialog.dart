import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/admin_kyc_service.dart';

const _documentsAffiches = [
  ('permis', 'Permis de conduire', Icons.badge_outlined),
  ('carteGrise', 'Carte grise', Icons.description_outlined),
  ('attestationVtc', 'Attestation VTC', Icons.shield_outlined),
];

/// Ouvre le panneau d'examen du dossier KYC d'un chauffeur : affiche en
/// grand les 3 pièces justificatives envoyées (voir
/// [ConducteurDocumentsService], même encodage Base64) et propose
/// d'approuver ou de rejeter — voir [AdminKycService].
Future<void> afficherExamenDossierDialog(
  BuildContext context, {
  required ConducteurKycAdmin conducteur,
  required AdminKycService service,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ExamenDossierDialog(conducteur: conducteur, service: service),
  );
}

class _ExamenDossierDialog extends StatefulWidget {
  const _ExamenDossierDialog({required this.conducteur, required this.service});

  final ConducteurKycAdmin conducteur;
  final AdminKycService service;

  @override
  State<_ExamenDossierDialog> createState() => _ExamenDossierDialogState();
}

class _ExamenDossierDialogState extends State<_ExamenDossierDialog> {
  bool _enCours = false;
  String? _erreur;

  Future<void> _decider(Future<void> Function(String uid) action) async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await action(widget.conducteur.id);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _erreur = "Échec de l'opération. Réessayez.";
          _enCours = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conducteur;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.nom,
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            c.telephone,
                            [c.vehiculeId, c.plaqueImmatriculation]
                                .where((v) => v != null && v.isNotEmpty)
                                .join(' - '),
                          ].where((v) => v.isNotEmpty).join(' · '),
                          style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _enCours ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (cle, label, icon) in _documentsAffiches) ...[
                        _CarteDocument(
                          label: label,
                          icon: icon,
                          dataUri: c.documents[cle] as String?,
                        ),
                        const SizedBox(height: 14),
                      ],
                    ],
                  ),
                ),
              ),
              if (_erreur != null) ...[
                const SizedBox(height: 4),
                Text(
                  _erreur!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _enCours ? null : () => _decider(widget.service.rejeterConducteur),
                      icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 18),
                      label: const Text('Rejeter'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _enCours ? null : () => _decider(widget.service.approuverConducteur),
                      icon: _enCours
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                      label: const Text('Approuver le chauffeur'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.vert,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CarteDocument extends StatelessWidget {
  const _CarteDocument({required this.label, required this.icon, required this.dataUri});

  final String label;
  final IconData icon;
  final String? dataUri;

  Uint8List? get _octets {
    if (dataUri == null || dataUri!.isEmpty) return null;
    try {
      return base64Decode(dataUri!.split(',').last);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final octets = _octets;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.greyLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.greyBorder),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.text),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (octets == null)
                const Text(
                  'Non envoyé',
                  style: TextStyle(fontSize: 11.5, color: AppColors.grey, fontWeight: FontWeight.w600),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: octets != null
                ? Image.memory(
                    octets,
                    width: double.infinity,
                    height: 220,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const _PlaceholderDocument(),
                  )
                : const _PlaceholderDocument(),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderDocument extends StatelessWidget {
  const _PlaceholderDocument();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 120,
      color: AppColors.background,
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported_outlined, color: AppColors.greyBorder, size: 32),
    );
  }
}
