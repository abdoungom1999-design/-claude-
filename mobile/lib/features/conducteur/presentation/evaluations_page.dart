import 'package:flutter/material.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';

/// Note moyenne du conducteur et avis reçus des clients.
class EvaluationsPage extends StatelessWidget {
  const EvaluationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final avis = DemoData.avisConducteur();

    return Scaffold(
      appBar: AppBar(title: const Text('Évaluations')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            AppCard(
              child: Column(
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 40),
                  const SizedBox(height: 8),
                  const Text(
                    '${DemoData.noteMoyenneConducteur}',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Basé sur ${avis.length} avis récents',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Avis récents',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ...avis.map(
              (a) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            a.auteur,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          Row(
                            children: List.generate(
                              5,
                              (i) => Icon(
                                i < a.note ? Icons.star_rounded : Icons.star_border_rounded,
                                color: Colors.amber.shade700,
                                size: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        a.commentaire,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.grey, height: 1.4),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${a.date.day.toString().padLeft(2, '0')}/'
                        '${a.date.month.toString().padLeft(2, '0')}/'
                        '${a.date.year}',
                        style: const TextStyle(fontSize: 11, color: AppColors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
