import 'package:flutter/material.dart';
import '../../../../core/demo/admin_demo_data.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';

/// Page "Clients" : liste des comptes clients de la plateforme.
class AdminClientsSection extends StatelessWidget {
  const AdminClientsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final clients = AdminDemoData.clients();

    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Tous les clients',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              Text(
                '${clients.length} client(s)',
                style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  'Client',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.grey),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'Téléphone',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.grey),
                ),
              ),
              SizedBox(
                width: 110,
                child: Text(
                  'Courses',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.grey),
                ),
              ),
              SizedBox(
                width: 120,
                child: Text(
                  'Inscrit le',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.grey),
                ),
              ),
            ],
          ),
          const Divider(height: 24, color: AppColors.greyBorder),
          for (final client in clients)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(client.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Expanded(flex: 2, child: Text(client.telephone, style: const TextStyle(fontSize: 13))),
                  SizedBox(width: 110, child: Text('${client.coursesTotal}', style: const TextStyle(fontSize: 13))),
                  SizedBox(
                    width: 120,
                    child: Text(
                      client.inscritLe,
                      style: const TextStyle(fontSize: 13, color: AppColors.grey),
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
