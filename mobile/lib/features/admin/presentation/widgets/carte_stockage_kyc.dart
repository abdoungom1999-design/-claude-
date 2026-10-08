import 'package:flutter/material.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../../data/admin_kyc_service.dart';

/// Stockage des pièces KYC des chauffeurs : combien sont encore en Base64
/// dans Firestore (repli utilisé tant que Firebase Storage n'était pas
/// activé), et bouton pour les déplacer dans Storage. L'Admin relance
/// jusqu'à « 0 pièce restante » (un lot de chauffeurs par clic).
class CarteStockageKyc extends StatefulWidget {
  const CarteStockageKyc({super.key, this.service});

  /// Injectable pour les tests.
  final AdminKycService? service;

  @override
  State<CarteStockageKyc> createState() => _CarteStockageKycState();
}

class _CarteStockageKycState extends State<CarteStockageKyc> {
  late final AdminKycService _service = widget.service ?? AdminKycService();
  BilanMigrationKyc? _bilan;
  String? _message;
  bool _erreur = false;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    _actualiser();
  }

  Future<void> _lancer(Future<BilanMigrationKyc> Function() action, {String Function(BilanMigrationKyc)? messageApres}) async {
    setState(() {
      _enCours = true;
      _message = null;
    });
    try {
      final bilan = await action();
      if (!mounted) return;
      setState(() {
        _bilan = bilan;
        _erreur = false;
        _message = messageApres?.call(bilan);
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _erreur = true;
          _message = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _erreur = true;
          _message = "L'opération a échoué. Réessayez.";
        });
      }
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _actualiser() => _lancer(() => _service.migrerDocumentsKyc(apercu: true));

  /// Déplace un lot, puis relit l'état réel (le bilan du lot ne dit pas
  /// combien de chauffeurs restent concernés).
  Future<void> _migrer() async {
    String? message;
    await _lancer(() async {
      final lot = await _service.migrerDocumentsKyc();
      message = lot.restants == 0
          ? 'Migration terminée : ${lot.migres} pièce(s) déplacée(s) dans Firebase Storage.'
          : '${lot.migres} pièce(s) déplacée(s). Relancez pour continuer (${lot.restants} restante(s)).';
      return _service.migrerDocumentsKyc(apercu: true);
    }, messageApres: (_) => message ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final bilan = _bilan;
    final restantes = bilan?.restants ?? 0;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: AppCard(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Stockage des documents KYC', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'Permis, carte grise, attestation VTC et photo de profil des chauffeurs. Les nouvelles pièces vont '
              'dans Firebase Storage dès que le service est activé ; les anciennes, encore encodées dans la base, '
              'peuvent y être déplacées ici.',
              style: TextStyle(fontSize: 12.5, color: AppColors.texteDiscret, height: 1.4),
            ),
            const SizedBox(height: 18),
            if (bilan == null && _enCours)
              const Center(child: CircularProgressIndicator(color: AppColors.vert))
            else if (bilan != null)
              Text(
                restantes == 0
                    ? 'Aucune pièce en Base64 : tout est dans Firebase Storage.'
                    : '$restantes pièce(s) encore en Base64, chez ${bilan.chauffeursConcernes} chauffeur(s).',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.texte),
              ),
            if (_message case final message?) ...[
              const SizedBox(height: 10),
              Text(
                message,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: _erreur ? AppColors.danger : AppColors.texte,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _enCours ? null : _actualiser,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Actualiser'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.texte),
                ),
                if (restantes > 0)
                  FilledButton.icon(
                    onPressed: _enCours ? null : _migrer,
                    icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: const Text('Migrer vers Storage'),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.vert),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
