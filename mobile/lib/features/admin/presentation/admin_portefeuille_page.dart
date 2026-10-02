import 'package:flutter/material.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/onyx_light.dart';
import '../../../core/utils/format_fcfa.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../portefeuille/data/portefeuille_service.dart';
import '../../portefeuille/presentation/mouvements_portefeuille_page.dart';

/// Portefeuille d'un client vu par l'Admin : solde, contrôle de cohérence
/// (la somme du livre de comptes doit égaler le solde), historique complet
/// et ajustement manuel motivé (journalisé côté serveur).
class AdminPortefeuillePage extends StatefulWidget {
  AdminPortefeuillePage({super.key, required this.clientId, required this.nomClient, PortefeuilleService? service})
      : service = service ?? PortefeuilleService();

  final String clientId;
  final String nomClient;
  final PortefeuilleService service;

  @override
  State<AdminPortefeuillePage> createState() => _AdminPortefeuillePageState();
}

class _AdminPortefeuillePageState extends State<AdminPortefeuillePage> {
  // Plusieurs écouteurs (cohérence du livre, liste) : flux partagé.
  late final Stream<Portefeuille> _portefeuille = widget.service.streamPortefeuille(widget.clientId).asBroadcastStream();
  late final Stream<List<MouvementPortefeuille>> _mouvements =
      widget.service.streamMouvements(widget.clientId).asBroadcastStream();
  final _montant = TextEditingController();
  final _motif = TextEditingController();
  bool _envoi = false;

  @override
  void dispose() {
    _montant.dispose();
    _motif.dispose();
    super.dispose();
  }

  Future<void> _ajuster() async {
    final montant = int.tryParse(_montant.text.trim().replaceAll(' ', '').replaceFirst('+', ''));
    final motif = _motif.text.trim();
    if (montant == null || montant == 0) {
      _message('Saisissez un montant entier non nul (négatif pour débiter).');
      return;
    }
    if (motif.isEmpty) {
      _message('Indiquez le motif de l\'ajustement.');
      return;
    }
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(montant > 0 ? 'Créditer le portefeuille ?' : 'Débiter le portefeuille ?'),
        content: Text(
          '${montant > 0 ? 'Créditer' : 'Débiter'} ${formaterFcfa(montant.abs())} '
          'sur le portefeuille de ${widget.nomClient}.\nMotif : $motif\n\nCette opération est journalisée.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Confirmer')),
        ],
      ),
    );
    if (confirme != true || !mounted) return;
    setState(() => _envoi = true);
    try {
      final solde = await widget.service.ajuster(clientId: widget.clientId, montantFcfa: montant, motif: motif);
      if (!mounted) return;
      _montant.clear();
      _motif.clear();
      _message('Ajustement enregistré. Nouveau solde : ${formaterFcfa(solde)}.');
    } on ApiException catch (e) {
      _message(e.message);
    } on Object {
      _message('Ajustement impossible. Vérifiez votre connexion.');
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  void _message(String texte) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte)));
  }

  @override
  Widget build(BuildContext context) {
    return EcranOnyxLight(
      flou: false,
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: AppColors.fondClairHaut,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.onyx,
        title: Text(
          'Portefeuille · ${widget.nomClient}',
          style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.onyx),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          StreamBuilder<Portefeuille>(
            stream: _portefeuille,
            builder: (context, solde) => StreamBuilder<List<MouvementPortefeuille>>(
              stream: _mouvements,
              builder: (context, mouvements) {
                final soldeFcfa = solde.data?.soldeFcfa;
                final somme = mouvements.data?.fold<int>(0, (total, m) => total + m.montantFcfa);
                final coherent = soldeFcfa != null && somme != null ? soldeFcfa == somme : null;
                return AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Solde', style: TextStyle(fontSize: 12.5, color: AppColors.grey)),
                      const SizedBox(height: 4),
                      Text(
                        soldeFcfa == null ? '…' : formaterFcfa(soldeFcfa),
                        key: const ValueKey('solde-admin'),
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      if (coherent == true)
                        const Row(children: [
                          Icon(Icons.verified_outlined, size: 18, color: AppColors.onyx),
                          SizedBox(width: 6),
                          Text('Livre de comptes cohérent', style: TextStyle(color: AppColors.onyx, fontSize: 13)),
                        ])
                      else if (coherent == false)
                        Row(children: [
                          const Icon(Icons.error_outline, size: 18, color: Colors.red),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'INCOHÉRENCE : la somme des mouvements (${formaterFcfa(somme!)}) '
                              'diffère du solde (${formaterFcfa(soldeFcfa!)}).',
                              key: const ValueKey('incoherence'),
                              style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ]),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ajustement manuel', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text(
                  'Positif pour créditer, négatif pour débiter. Le solde reste entre 0 et '
                  '200 000 FCFA. Journalisé.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('ajustement-montant'),
                  controller: _montant,
                  keyboardType: const TextInputType.numberWithOptions(signed: true),
                  decoration: const InputDecoration(labelText: 'Montant (FCFA)', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('ajustement-motif'),
                  controller: _motif,
                  maxLength: 300,
                  decoration: const InputDecoration(labelText: 'Motif (obligatoire)', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 10),
                PrimaryButton(label: 'Enregistrer l\'ajustement', onPressed: _envoi ? null : _ajuster, isLoading: _envoi),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Mouvements', style: styleTitreSection),
          ListeMouvements(flux: _mouvements, shrinkWrap: true),
        ],
      ),
      ),
    );
  }
}
