import 'package:flutter/material.dart';
import '../../../../core/demo/admin_demo_data.dart';
import '../../../../core/demo/demo_data.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/premium_dialog.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/utils/format_fcfa.dart';
import '../../../../firebase_options.dart';
import '../../../courses/data/course_service.dart';
import '../widgets/carte_stockage_kyc.dart';

/// Page "Paramètres". En Firebase réel : les règles réellement
/// appliquées par l'application (grille tarifaire, commission, moyens de
/// paiement), en lecture seule — elles ne sont pas encore modifiables
/// depuis l'Admin. En mode démo : réglages simulés (villes actives, mode
/// maintenance), qui n'agissent sur rien.
class AdminParametresSection extends StatefulWidget {
  const AdminParametresSection({super.key, this.demo});

  /// Force la version démo ou réelle (tests) ; par défaut, selon Firebase.
  final bool? demo;

  @override
  State<AdminParametresSection> createState() => _AdminParametresSectionState();
}

class _AdminParametresSectionState extends State<AdminParametresSection> {
  late final Set<String> _villesActives = {...AdminDemoData.villesActives};
  late bool _modeMaintenance = AdminDemoData.modeMaintenance;

  void _sauvegarder() {
    AdminDemoData.mettreAJourParametresPlateforme(
      villesActives: _villesActives,
      modeMaintenance: _modeMaintenance,
    );
    PremiumDialog.afficher(
      context,
      icon: Icons.tune_rounded,
      titre: 'Paramètres enregistrés',
      message: 'La configuration de la plateforme a bien été mise à jour.',
      succes: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!(widget.demo ?? !DefaultFirebaseOptions.estConfigure)) return const _ReglesEnVigueur();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: AppCard(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paramètres de la plateforme',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Application Sprint · v1.4.0',
              style: TextStyle(fontSize: 12.5, color: AppColors.grey),
            ),
            const SizedBox(height: 26),
            const Text(
              'Villes actives',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final ville in AdminDemoData.villesDisponibles)
                  FilterChip(
                    label: Text(ville),
                    selected: _villesActives.contains(ville),
                    selectedColor: AppColors.bleuClair,
                    checkmarkColor: AppColors.bleu,
                    labelStyle: TextStyle(
                      color: _villesActives.contains(ville)
                          ? AppColors.bleuFonce
                          : AppColors.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                    backgroundColor: AppColors.fondClair,
                    side: BorderSide.none,
                    onSelected: (selectionne) => setState(() {
                      if (selectionne) {
                        _villesActives.add(ville);
                      } else {
                        _villesActives.remove(ville);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.fondClair,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Mode maintenance',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _modeMaintenance
                              ? "L'application est actuellement fermée aux nouvelles commandes."
                              : "L'application fonctionne normalement.",
                          style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _modeMaintenance,
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.bleu,
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: const Color(0xFFD1D1D6),
                    trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
                    onChanged: (valeur) => setState(() => _modeMaintenance = valeur),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              label: 'Enregistrer',
              icon: Icons.save_outlined,
              onPressed: _sauvegarder,
            ),
          ],
        ),
      ),
    );
  }
}

/// Règles réellement appliquées par l'application. Les exemples de prix
/// sont calculés par le moteur de tarification lui-même
/// ([DemoData.estimerPrix]) : ils ne peuvent pas diverger de la réalité.
class _ReglesEnVigueur extends StatelessWidget {
  const _ReglesEnVigueur();

  static int _prix(double km, int heureUtc) => DemoData.estimerPrix(
        type: 'PASSAGER',
        distanceKm: km,
        maintenant: DateTime.utc(2026, 1, 5, heureUtc),
      ).prixFcfa;

  @override
  Widget build(BuildContext context) {
    Widget ligne(String libelle, String valeur) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Expanded(child: Text(libelle, style: const TextStyle(fontSize: 13, color: AppColors.grey))),
              Text(valeur, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
        );
    const titre = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);

    final regles = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: AppCard(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Règles en vigueur', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              "Appliquées aujourd'hui par l'application (moto et colis). Lecture seule : les modifier "
              'demande pour l\'instant une mise à jour de l\'application.',
              style: TextStyle(fontSize: 12.5, color: AppColors.grey, height: 1.4),
            ),
            const SizedBox(height: 22),
            const Text('Tarifs', style: titre),
            ligne('Prise en charge', formaterFcfa(300)),
            ligne('Prix par kilomètre', formaterFcfa(200)),
            ligne('Prix minimum', formaterFcfa(1000)),
            ligne('Distance facturée', 'Par la route (Google)'),
            ligne('Heures de pointe (7 h – 10 h, 17 h – 20 h)', '× 1,2'),
            ligne('Tarif de nuit (22 h – 5 h)', '× 1,2'),
            const SizedBox(height: 6),
            Text(
              'Exemples calculés : 5 km à midi = ${formaterFcfa(_prix(5, 12))} · 5 km à 8 h = '
              '${formaterFcfa(_prix(5, 8))} · 15 km à midi = ${formaterFcfa(_prix(15, 12))}.',
              style: const TextStyle(fontSize: 12, color: AppColors.grey, height: 1.4),
            ),
            const SizedBox(height: 4),
            const Text(
              'Si Google ne répond pas, la distance est estimée (vol d\'oiseau + 10 %) pour ne jamais '
              'bloquer une commande.',
              style: TextStyle(fontSize: 12, color: AppColors.grey, height: 1.4),
            ),
            const Divider(height: 36, color: AppColors.greyBorder),
            const Text('Commission et paiement', style: titre),
            ligne('Commission Sprint', '${Commission.pourcentage} % du prix'),
            ligne('Part du chauffeur', '${100 - Commission.pourcentage} % du prix'),
            ligne('Moyens de paiement', 'Wave, solde Sprint (Orange Money bientôt)'),
            ligne('Encaissement', 'Mode test (aucun débit réel)'),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [regles, const SizedBox(height: 20), const CarteStockageKyc()],
    );
  }
}
