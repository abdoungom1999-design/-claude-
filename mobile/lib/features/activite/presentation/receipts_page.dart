import 'package:flutter/material.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';

/// Liste des reçus (factures) des courses passées.
class ReceiptsPage extends StatelessWidget {
  const ReceiptsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final historique = DemoData.historique();

    return Scaffold(
      appBar: AppBar(title: const Text('Reçus')),
      body: historique.isEmpty
          ? const Center(
              child: Text(
                'Aucun reçu pour le moment',
                style: TextStyle(color: AppColors.grey),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: historique.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final course = historique[index];
                return AppCard(
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.greyLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.receipt_long_outlined,
                          color: AppColors.text,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reçu #${course.id.split('-').last}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${course.date.day.toString().padLeft(2, '0')}/'
                              '${course.date.month.toString().padLeft(2, '0')}/'
                              '${course.date.year}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${course.prixFcfa} FCFA',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
