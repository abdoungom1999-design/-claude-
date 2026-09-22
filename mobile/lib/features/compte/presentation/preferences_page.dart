import 'package:flutter/material.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/premium_dialog.dart';
import '../../../core/widgets/primary_button.dart';

/// Préférences d'utilisation de l'app (démo : état conservé en mémoire,
/// n'affecte pas le thème réel de l'application — voir note dans le
/// bloc Thème).
class PreferencesPage extends StatefulWidget {
  const PreferencesPage({super.key});

  @override
  State<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends State<PreferencesPage> {
  late String _ville = DemoData.villeActivite;
  late String _theme = DemoData.theme;
  late String _uniteDistance = DemoData.uniteDistance;
  late String _formatHeure = DemoData.formatHeure;
  late String _devise = DemoData.devise;

  void _enregistrer() {
    DemoData.villeActivite = _ville;
    DemoData.theme = _theme;
    DemoData.uniteDistance = _uniteDistance;
    DemoData.formatHeure = _formatHeure;
    DemoData.devise = _devise;
    PremiumDialog.afficher(
      context,
      icon: Icons.tune_rounded,
      titre: 'Préférences enregistrées',
      message: 'Vos préférences ont bien été mises à jour.',
      succes: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Préférences')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _BlocRadio<String>(
              titre: 'Localisation',
              sousTitre: 'Ville d\'activité',
              valeur: _ville,
              options: const ['Dakar', 'Thiès', 'Saint-Louis', 'Mbour'],
              onChanged: (v) => setState(() => _ville = v),
            ),
            const SizedBox(height: 16),
            _BlocRadio<String>(
              titre: 'Thème',
              valeur: _theme,
              options: const ['Clair', 'Sombre', 'Système'],
              onChanged: (v) => setState(() => _theme = v),
            ),
            const SizedBox(height: 16),
            _BlocRadio<String>(
              titre: 'Unité de distance',
              valeur: _uniteDistance,
              options: const ['km', 'mi'],
              onChanged: (v) => setState(() => _uniteDistance = v),
            ),
            const SizedBox(height: 16),
            _BlocRadio<String>(
              titre: 'Format d\'heure',
              valeur: _formatHeure,
              options: const ['24h', '12h'],
              onChanged: (v) => setState(() => _formatHeure = v),
            ),
            const SizedBox(height: 16),
            _BlocRadio<String>(
              titre: 'Devise',
              valeur: _devise,
              options: const ['Automatique', 'Euro', 'FCFA'],
              onChanged: (v) => setState(() => _devise = v),
            ),
            const SizedBox(height: 28),
            PrimaryButton(label: 'Enregistrer', onPressed: _enregistrer),
          ],
        ),
      ),
    );
  }
}

class _BlocRadio<T> extends StatelessWidget {
  const _BlocRadio({
    required this.titre,
    this.sousTitre,
    required this.valeur,
    required this.options,
    required this.onChanged,
  });

  final String titre;
  final String? sousTitre;
  final T valeur;
  final List<T> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                if (sousTitre != null)
                  Text(sousTitre!, style: const TextStyle(fontSize: 11.5, color: AppColors.grey)),
              ],
            ),
          ),
          ...options.map(
            (option) => RadioListTile<T>(
              value: option,
              groupValue: valeur,
              onChanged: (v) => onChanged(v as T),
              activeColor: AppColors.orange,
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              title: Text('$option', style: const TextStyle(fontSize: 13.5)),
            ),
          ),
        ],
      ),
    );
  }
}
