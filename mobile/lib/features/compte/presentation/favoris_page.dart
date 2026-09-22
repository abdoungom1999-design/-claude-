import 'package:flutter/material.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/premium_dialog.dart';

IconData _iconePour(String type) {
  switch (type) {
    case 'maison':
      return Icons.home_outlined;
    case 'travail':
      return Icons.work_outline_rounded;
    default:
      return Icons.location_on_outlined;
  }
}

/// Adresses enregistrées par le client.
class FavorisPage extends StatelessWidget {
  const FavorisPage({super.key});

  @override
  Widget build(BuildContext context) {
    final favoris = DemoData.favoris();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favoris'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => PremiumDialog.bientotDisponible(
              context,
              'Ajouter une adresse favorite',
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: favoris.isEmpty
            ? const Center(
                child: Text(
                  'Aucune adresse enregistrée',
                  style: TextStyle(color: AppColors.grey),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: favoris.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final favori = favoris[index];
                  return AppCard(
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.orangeLight,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(
                            _iconePour(favori.icon),
                            color: AppColors.orange,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                favori.libelle,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                favori.adresse,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: AppColors.grey),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
