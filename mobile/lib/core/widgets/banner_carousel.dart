import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class BannerData {
  const BannerData({
    required this.icon,
    required this.titre,
    required this.sousTitre,
    required this.colors,
  });

  final IconData icon;
  final String titre;
  final String sousTitre;
  final List<Color> colors;
}

/// Carrousel de bannières promotionnelles (écran Accueil). Contenu
/// éditorial statique — pas une donnée métier, ne dépend donc pas de
/// [DemoData].
class BannerCarousel extends StatefulWidget {
  const BannerCarousel({super.key});

  static const _bannieres = [
    BannerData(
      icon: Icons.inventory_2_outlined,
      titre: 'Envoyez un colis',
      sousTitre: 'Livraison rapide partout à Dakar',
      colors: [AppColors.orange, AppColors.orangeDark],
    ),
    BannerData(
      icon: Icons.card_giftcard_rounded,
      titre: 'Parrainez un ami',
      sousTitre: 'Gagnez des courses offertes',
      colors: [AppColors.noirProfond, AppColors.noirProfondClair],
    ),
    BannerData(
      icon: Icons.local_taxi_outlined,
      titre: 'Devenez chauffeur',
      sousTitre: 'Rejoignez Sprint et gagnez chaque jour',
      colors: [AppColors.orangeDark, AppColors.orange],
    ),
  ];

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  final _controller = PageController(viewportFraction: 0.88);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 110,
          child: PageView.builder(
            controller: _controller,
            itemCount: BannerCarousel._bannieres.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (context, index) {
              final banniere = BannerCarousel._bannieres[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: banniere.colors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(banniere.icon, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              banniere.titre,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              banniere.sousTitre,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            BannerCarousel._bannieres.length,
            (index) => AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _page == index ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: _page == index ? AppColors.orange : AppColors.greyBorder,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
