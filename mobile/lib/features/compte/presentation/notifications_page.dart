import 'package:flutter/material.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';

/// Préférences de notifications (démo : état conservé en mémoire).
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            AppCard(
              child: Column(
                children: [
                  _LigneToggle(
                    icon: Icons.two_wheeler_rounded,
                    titre: 'Suivi de course',
                    sousTitre: 'Statut du chauffeur, arrivée, fin de course',
                    valeur: DemoData.notifCourses,
                    onChanged: (v) => setState(() => DemoData.notifCourses = v),
                  ),
                  const Divider(height: 24),
                  _LigneToggle(
                    icon: Icons.local_offer_outlined,
                    titre: 'Promotions',
                    sousTitre: 'Codes promo et offres spéciales',
                    valeur: DemoData.notifPromotions,
                    onChanged: (v) => setState(() => DemoData.notifPromotions = v),
                  ),
                  const Divider(height: 24),
                  _LigneToggle(
                    icon: Icons.campaign_outlined,
                    titre: 'Actualités Sprint',
                    sousTitre: 'Nouveautés et actualités de Groupe Santine',
                    valeur: DemoData.notifActualites,
                    onChanged: (v) => setState(() => DemoData.notifActualites = v),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LigneToggle extends StatelessWidget {
  const _LigneToggle({
    required this.icon,
    required this.titre,
    required this.sousTitre,
    required this.valeur,
    required this.onChanged,
  });

  final IconData icon;
  final String titre;
  final String sousTitre;
  final bool valeur;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.orangeLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.orange, size: 19),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titre, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text(sousTitre, style: const TextStyle(fontSize: 11.5, color: AppColors.grey)),
            ],
          ),
        ),
        Switch(value: valeur, activeThumbColor: AppColors.orange, onChanged: onChanged),
      ],
    );
  }
}
