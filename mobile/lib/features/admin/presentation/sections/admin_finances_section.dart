import 'package:flutter/material.dart';
import '../../../../core/demo/admin_demo_data.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format_fcfa.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/premium_dialog.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/stat_tile.dart';
import '../../../../firebase_options.dart';
import '../../../courses/data/course_service.dart';
import '../../../finances/data/comptabilite.dart';
import '../../../finances/data/finance_service.dart';
import '../../data/suivi_direct_service.dart';

/// Page "Finances" de l'Admin. En Firebase réel : chiffre d'affaires de
/// la plateforme, commissions, et solde de chaque chauffeur (qui doit
/// combien à qui après compensation espèces / mobile money), avec
/// saisie des règlements. En mode démo : ancien formulaire de réglages,
/// simulé ([AdminDemoData]).
class AdminFinancesSection extends StatelessWidget {
  const AdminFinancesSection({super.key, this.service, this.noms, this.maintenant});

  /// Injectables pour les tests.
  final FinanceService? service;
  final Stream<Map<String, String>>? noms;
  final DateTime? maintenant;

  @override
  Widget build(BuildContext context) {
    if (!DefaultFirebaseOptions.estConfigure && service == null) return const _FinancesDemo();
    return _FinancesReelles(
      service: service ?? FinanceService(),
      noms: noms ?? SuiviDirectService().streamNomsChauffeurs(),
      maintenant: maintenant,
    );
  }
}

class _FinancesReelles extends StatefulWidget {
  const _FinancesReelles({required this.service, required this.noms, this.maintenant});

  final FinanceService service;
  final Stream<Map<String, String>> noms;
  final DateTime? maintenant;

  @override
  State<_FinancesReelles> createState() => _FinancesReellesState();
}

class _FinancesReellesState extends State<_FinancesReelles> {
  late final _courses = widget.service.streamToutesCourses();
  late final _reglements = widget.service.streamTousReglements();

  Future<void> _regler(String chauffeurId, String nom, int soldeFcfa) async {
    final enregistre = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogReglement(service: widget.service, chauffeurId: chauffeurId, nom: nom, soldeFcfa: soldeFcfa),
    );
    if (enregistre == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Règlement enregistré pour $nom.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LigneCourse>>(
      stream: _courses,
      builder: (context, courses) => StreamBuilder<List<Reglement>>(
        stream: _reglements,
        builder: (context, reglements) => StreamBuilder<Map<String, String>>(
          stream: widget.noms,
          builder: (context, noms) {
            if (courses.hasError || reglements.hasError) {
              return const AppCard(
                child: Text(
                  'Lecture impossible. Vérifiez que vous êtes connecté avec le compte Admin '
                  'et que les règles Firestore sont publiées.',
                  style: TextStyle(color: AppColors.grey),
                ),
              );
            }
            if (!courses.hasData || !reglements.hasData) {
              return const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator(color: AppColors.orange)),
              );
            }
            return _VueFinances(
              compte: Compte(courses: courses.data!, reglements: reglements.data!),
              noms: noms.data ?? const {},
              maintenant: widget.maintenant ?? DateTime.now(),
              onRegler: _regler,
            );
          },
        ),
      ),
    );
  }
}

class _VueFinances extends StatelessWidget {
  const _VueFinances({required this.compte, required this.noms, required this.maintenant, required this.onRegler});

  final Compte compte;
  final Map<String, String> noms;
  final DateTime maintenant;
  final void Function(String chauffeurId, String nom, int soldeFcfa) onRegler;

  @override
  Widget build(BuildContext context) {
    final aujourdhui = compte.depuis(Periodes.debutJour(maintenant));
    final semaine = compte.depuis(Periodes.debutSemaine(maintenant));
    final ids = {
      for (final c in compte.courses) c.chauffeurId,
      for (final r in compte.reglements) r.chauffeurId,
    }..remove('');
    final comptes = [for (final id in ids) (id, compte.duChauffeur(id))]
      ..sort((a, b) => b.$2.soldeFcfa.abs().compareTo(a.$2.soldeFcfa.abs()));
    final duParChauffeurs = comptes.fold(0, (t, e) => e.$2.soldeFcfa < 0 ? t - e.$2.soldeFcfa : t);
    final duAuxChauffeurs = comptes.fold(0, (t, e) => e.$2.soldeFcfa > 0 ? t + e.$2.soldeFcfa : t);

    Widget tuile(String libelle, int montant, IconData icone, {Color accent = AppColors.orange}) => SizedBox(
          width: 250,
          child: StatTile(label: libelle, valeur: formaterFcfa(montant), icon: icone, accent: accent),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            tuile("CA aujourd'hui", aujourdhui.chiffreAffairesFcfa, Icons.today_outlined),
            tuile('CA cette semaine', semaine.chiffreAffairesFcfa, Icons.date_range_outlined),
            tuile('CA total', compte.chiffreAffairesFcfa, Icons.account_balance_outlined),
            tuile('Commissions Sprint (total)', compte.commissionsFcfa, Icons.percent_rounded, accent: AppColors.vert),
            tuile('Dû par les chauffeurs', duParChauffeurs, Icons.call_received_rounded, accent: Colors.red.shade700),
            tuile('Dû aux chauffeurs', duAuxChauffeurs, Icons.call_made_rounded, accent: Colors.blue.shade700),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Commission : ${Commission.pourcentage} % de chaque course terminée, figée à la fin de la course '
          '(imposée par les règles Firestore). ${compte.nombreCourses} courses terminées au total, dont '
          '${formaterFcfa(compte.especesFcfa)} en espèces et ${formaterFcfa(compte.mobileMoneyFcfa)} '
          'par Wave / Orange Money (encore en mode test : aucun argent réellement encaissé).',
          style: const TextStyle(fontSize: 12, color: AppColors.grey, height: 1.4),
        ),
        const SizedBox(height: 22),
        AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Soldes des chauffeurs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              if (comptes.isEmpty)
                const Text('Aucune course terminée pour le moment.', style: TextStyle(color: AppColors.grey))
              else ...[
                const _LigneTableau(
                  entete: true,
                  cellules: ['Chauffeur', 'Courses', 'CA', 'Commission', 'Solde', ''],
                ),
                const Divider(color: AppColors.greyBorder),
                for (final (id, c) in comptes)
                  _LigneTableau(
                    cellules: [
                      noms[id] ?? 'Chauffeur ${id.substring(0, id.length < 6 ? id.length : 6)}',
                      '${c.nombreCourses}',
                      formaterFcfa(c.chiffreAffairesFcfa),
                      formaterFcfa(c.commissionsFcfa),
                      '',
                      '',
                    ],
                    solde: c.soldeFcfa,
                    onRegler: () => onRegler(id, noms[id] ?? 'ce chauffeur', c.soldeFcfa),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LigneTableau extends StatelessWidget {
  const _LigneTableau({required this.cellules, this.entete = false, this.solde, this.onRegler});

  final List<String> cellules;
  final bool entete;
  final int? solde;
  final VoidCallback? onRegler;

  static const _flex = [3, 1, 2, 2, 3, 2];

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 13,
      fontWeight: entete ? FontWeight.w700 : FontWeight.w500,
      color: entete ? AppColors.grey : AppColors.text,
    );
    final solde = this.solde;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          for (var i = 0; i < 4; i++) Expanded(flex: _flex[i], child: Text(cellules[i], style: style)),
          Expanded(
            flex: _flex[4],
            child: solde == null
                ? Text(cellules[4], style: style)
                : Text(
                    switch (sensDuSolde(solde)) {
                      SensSolde.chauffeurDoit => 'Doit ${formaterFcfa(-solde)}',
                      SensSolde.plateformeDoit => 'À reverser ${formaterFcfa(solde)}',
                      SensSolde.equilibre => 'À jour',
                    },
                    style: style.copyWith(
                      fontWeight: FontWeight.w800,
                      color: switch (sensDuSolde(solde)) {
                        SensSolde.chauffeurDoit => Colors.red.shade700,
                        SensSolde.plateformeDoit => Colors.blue.shade700,
                        SensSolde.equilibre => AppColors.grey,
                      },
                    ),
                  ),
          ),
          Expanded(
            flex: _flex[5],
            child: onRegler == null
                ? Text(cellules[5], style: style)
                : Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton(onPressed: onRegler, child: const Text('Règlement')),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Saisie d'un règlement : le sens et le montant sont préremplis d'après
/// le solde (montant qui le remet à zéro), modifiables.
class _DialogReglement extends StatefulWidget {
  const _DialogReglement({required this.service, required this.chauffeurId, required this.nom, required this.soldeFcfa});

  final FinanceService service;
  final String chauffeurId;
  final String nom;
  final int soldeFcfa;

  @override
  State<_DialogReglement> createState() => _DialogReglementState();
}

class _DialogReglementState extends State<_DialogReglement> {
  late String _sens =
      widget.soldeFcfa > 0 ? SensReglement.plateformeVersChauffeur : SensReglement.chauffeurVersPlateforme;
  late final _montant = TextEditingController(text: widget.soldeFcfa == 0 ? '' : '${widget.soldeFcfa.abs()}');
  final _note = TextEditingController();
  bool _envoi = false;
  String? _erreur;

  @override
  void dispose() {
    _montant.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final montant = int.tryParse(_montant.text.replaceAll(RegExp(r'[\s\u202F\u00A0]'), ''));
    if (montant == null || montant <= 0) {
      setState(() => _erreur = 'Montant invalide.');
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      await widget.service.enregistrerReglement(
        chauffeurId: widget.chauffeurId,
        montantFcfa: montant,
        sens: _sens,
        note: _note.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _envoi = false;
          _erreur = 'Enregistrement impossible. Vérifiez votre connexion et vos droits Admin.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Règlement : ${widget.nom}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadioGroup<String>(
              groupValue: _sens,
              onChanged: (sens) => setState(() => _sens = sens ?? _sens),
              child: const Column(
                children: [
                  RadioListTile<String>(
                    value: SensReglement.chauffeurVersPlateforme,
                    title: Text('Le chauffeur a versé sa commission à Sprint'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<String>(
                    value: SensReglement.plateformeVersChauffeur,
                    title: Text('Sprint a reversé sa part au chauffeur'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _montant,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Montant (FCFA)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Note (facultatif)',
                hintText: 'Ex. : versement Wave du 27/09',
                border: OutlineInputBorder(),
              ),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 10),
              Text(_erreur!, style: TextStyle(color: Colors.red.shade700, fontSize: 12.5)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _envoi ? null : () => Navigator.of(context).pop(false), child: const Text('Annuler')),
        FilledButton(
          onPressed: _envoi ? null : _enregistrer,
          style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

/// Version démo (sans Firebase) : formulaire simulé, inchangé.
class _FinancesDemo extends StatefulWidget {
  const _FinancesDemo();

  @override
  State<_FinancesDemo> createState() => _FinancesDemoState();
}

class _FinancesDemoState extends State<_FinancesDemo> {
  late final _commissionController = TextEditingController(
    text: AdminDemoData.commissionPourcent.toStringAsFixed(1),
  );
  late final _prixBaseController = TextEditingController(
    text: '${AdminDemoData.prixBaseFcfa}',
  );
  late final _prixKmController = TextEditingController(
    text: '${AdminDemoData.prixParKmFcfa}',
  );

  @override
  void dispose() {
    _commissionController.dispose();
    _prixBaseController.dispose();
    _prixKmController.dispose();
    super.dispose();
  }

  void _sauvegarder() {
    final commission = double.tryParse(_commissionController.text.replaceAll(',', '.'));
    final prixBase = int.tryParse(_prixBaseController.text);
    final prixKm = int.tryParse(_prixKmController.text);

    if (commission == null || prixBase == null || prixKm == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merci de saisir des valeurs numériques valides.')),
      );
      return;
    }

    AdminDemoData.mettreAJourConfigFinance(
      commissionPourcent: commission,
      prixBaseFcfa: prixBase,
      prixParKmFcfa: prixKm,
    );

    PremiumDialog.afficher(
      context,
      icon: Icons.savings_outlined,
      titre: 'Configuration enregistrée',
      message: 'Les nouveaux paramètres financiers ont bien été sauvegardés.',
      succes: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: AppCard(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paramètres financiers',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Ces valeurs pilotent la commission Santine et la tarification des courses.',
              style: TextStyle(fontSize: 12.5, color: AppColors.grey),
            ),
            const SizedBox(height: 28),
            _ChampFinance(
              label: 'Commission prélevée (%)',
              controller: _commissionController,
              suffixe: '%',
            ),
            const SizedBox(height: 18),
            _ChampFinance(
              label: 'Prix de base de la course (FCFA)',
              controller: _prixBaseController,
              suffixe: 'FCFA',
            ),
            const SizedBox(height: 18),
            _ChampFinance(
              label: 'Prix par kilomètre (FCFA)',
              controller: _prixKmController,
              suffixe: 'FCFA/km',
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              label: 'Sauvegarder la configuration',
              icon: Icons.save_outlined,
              onPressed: _sauvegarder,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChampFinance extends StatelessWidget {
  const _ChampFinance({
    required this.label,
    required this.controller,
    required this.suffixe,
  });

  final String label;
  final TextEditingController controller;
  final String suffixe;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            suffixText: suffixe,
            filled: true,
            fillColor: AppColors.greyLight,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
