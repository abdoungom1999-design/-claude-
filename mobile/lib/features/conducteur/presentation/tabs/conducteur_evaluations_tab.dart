import 'package:flutter/material.dart';
import '../../../../core/demo/demo_data.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';

/// Onglet Évaluations : grosse note centrale, badges de compliments
/// (façon Uber) et avis récents des clients.
class ConducteurEvaluationsTab extends StatelessWidget {
  const ConducteurEvaluationsTab({super.key});

  static const _iconesCompliments = {
    'Excellente conduite': Icons.thumb_up_alt_outlined,
    'Voiture impeccable': Icons.auto_awesome_outlined,
    'Bonne conversation': Icons.chat_bubble_outline_rounded,
    'Trajet efficace': Icons.bolt_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final avis = DemoData.avisConducteur();
    final compliments = DemoData.complimentsConducteur();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Évaluations',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.noirProfond, AppColors.noirProfondClair],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                children: [
                  Text(
                    DemoData.noteMoyenneConducteur.toStringAsFixed(2),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 46,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      5,
                      (i) => const Icon(Icons.star_rounded, color: Color(0xFFFFC94D), size: 22),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Basé sur ${avis.length} avis récents',
                    style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            const Text(
              'Compliments reçus',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final compliment in compliments)
                  _BadgeCompliment(compliment: compliment, icon: _iconesCompliments[compliment.label]),
              ],
            ),
            const SizedBox(height: 26),
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

class _BadgeCompliment extends StatelessWidget {
  const _BadgeCompliment({required this.compliment, this.icon});

  final ComplimentConducteur compliment;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.orangeLight,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.emoji_events_outlined, size: 16, color: AppColors.orange),
          const SizedBox(width: 8),
          Text(
            compliment.label,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.orange,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${compliment.compte}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
