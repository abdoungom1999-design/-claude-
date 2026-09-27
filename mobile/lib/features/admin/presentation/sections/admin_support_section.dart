import 'package:flutter/material.dart';
import '../../../../core/demo/admin_demo_data.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../firebase_options.dart';

/// Page "Support" : file des tickets clients à traiter. Il n'existe pas
/// encore de système de tickets dans l'application : en Firebase réel,
/// la page le dit au lieu d'afficher les tickets de la maquette.
class AdminSupportSection extends StatelessWidget {
  const AdminSupportSection({super.key, this.demo});

  /// Force la version démo ou réelle (tests) ; par défaut, selon Firebase.
  final bool? demo;

  @override
  Widget build(BuildContext context) {
    if (!(demo ?? !DefaultFirebaseOptions.estConfigure)) {
      return const AppCard(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tickets support', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            SizedBox(height: 12),
            Text(
              "Aucun ticket : l'application ne permet pas encore aux clients d'ouvrir une "
              'demande de support. Les tickets de démonstration ont été retirés pour que '
              "cette page n'affiche que des données réelles.",
              style: TextStyle(fontSize: 13, color: AppColors.grey, height: 1.5),
            ),
          ],
        ),
      );
    }
    final tickets = AdminDemoData.tickets();
    final ouverts = tickets.where((t) => t.statut != StatutTicket.resolu).length;

    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Tickets support',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              Text(
                '$ouverts en attente de traitement',
                style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (final ticket in tickets)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.greyLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ticket.sujet,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Client : ${ticket.client}',
                            style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
                          ),
                        ],
                      ),
                    ),
                    _BadgeTicket(statut: ticket.statut),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BadgeTicket extends StatelessWidget {
  const _BadgeTicket({required this.statut});

  final StatutTicket statut;

  @override
  Widget build(BuildContext context) {
    final (label, couleur) = switch (statut) {
      StatutTicket.ouvert => ('Ouvert', Colors.redAccent),
      StatutTicket.enCours => ('En cours', AppColors.orange),
      StatutTicket.resolu => ('Résolu', AppColors.vert),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: couleur, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}
