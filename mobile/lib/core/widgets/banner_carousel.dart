import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../router/app_routes.dart';
import '../theme/app_colors.dart';
import 'premium_dialog.dart';

/// Description d'une bannière promotionnelle. [imageUrl] est une vraie
/// photographie (voir note en tête de [BannerCarousel] sur sa
/// vérifiabilité) ; quand il est absent, la bannière utilise un fond en
/// dégradé avec une icône, comme pour "Forfait Aéroport".
class BannerData {
  const BannerData({
    required this.titre,
    required this.sousTitre,
    this.imageUrl,
    this.icon,
    this.iconColor = Colors.white,
    this.gradientColors = const [AppColors.noirProfond, AppColors.noirProfondClair],
    this.ctaLabel,
    this.onTap,
  });

  final String titre;
  final String sousTitre;
  final String? imageUrl;
  final IconData? icon;
  final Color iconColor;
  final List<Color> gradientColors;
  final String? ctaLabel;
  final void Function(BuildContext context)? onTap;
}

/// Carrousel de bannières promotionnelles (écran Accueil) : défilement
/// automatique, vraies photographies avec dégradé sombre superposé pour
/// la lisibilité du texte, pagination par points.
///
/// Note de transparence : les URLs Unsplash ci-dessous n'ont pas pu être
/// chargées ni vérifiées depuis cet environnement de développement (accès
/// direct aux CDN d'images bloqué par le bac à sable — testé sur
/// Unsplash, Wikimedia, Pexels, Pixabay). Elles restent en place pour la
/// production comme demandé ; chaque [Image.network] a un `errorBuilder`
/// qui affiche un repli en dégradé + icône, jamais une image cassée, si
/// une URL ne se charge pas chez un visiteur.
class BannerCarousel extends StatefulWidget {
  const BannerCarousel({super.key});

  static final _bannieres = [
    BannerData(
      titre: 'Livrée chez vous !',
      sousTitre: 'Livraison rapide à domicile.',
      imageUrl:
          'https://images.unsplash.com/photo-1615529182904-14819c35db37'
          '?auto=format&fit=crop&w=1200&q=80',
      icon: Icons.inventory_2_outlined,
      ctaLabel: 'Faire mes courses',
      onTap: (context) => context.push(AppRoutes.clientColis),
    ),
    const BannerData(
      titre: 'Sprint en direct',
      sousTitre: 'Forfaits transferts aéroports',
      icon: Icons.flight_takeoff_rounded,
      iconColor: AppColors.or,
      gradientColors: [AppColors.noirProfond, AppColors.noirProfondClair],
    ),
    BannerData(
      titre: "L'excellence à chaque trajet",
      sousTitre: 'Commandez votre VTC.',
      imageUrl:
          'https://images.unsplash.com/photo-1563720223185-11003d516935'
          '?auto=format&fit=crop&w=1200&q=80',
      icon: Icons.workspace_premium_outlined,
      onTap: (context) => context.push(AppRoutes.clientPassager),
    ),
  ];

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  final _controller = PageController(viewportFraction: 0.9);
  int _page = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _avancer());
  }

  void _avancer() {
    if (!_controller.hasClients) return;
    final suivante = (_page + 1) % BannerCarousel._bannieres.length;
    _controller.animateToPage(
      suivante,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 172,
          child: PageView.builder(
            controller: _controller,
            itemCount: BannerCarousel._bannieres.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _BanniereCard(
                  banniere: BannerCarousel._bannieres[index],
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

class _BanniereCard extends StatelessWidget {
  const _BanniereCard({required this.banniere});

  final BannerData banniere;

  void _onTap(BuildContext context) {
    if (banniere.onTap != null) {
      banniere.onTap!(context);
      return;
    }
    PremiumDialog.bientotDisponible(context, banniere.titre);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: () => _onTap(context),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (banniere.imageUrl != null)
              Image.network(
                banniere.imageUrl!,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return _BanniereRepli(banniere: banniere);
                },
                errorBuilder: (context, error, stackTrace) =>
                    _BanniereRepli(banniere: banniere),
              )
            else
              _BanniereRepli(banniere: banniere),
            // Dégradé sombre pour la lisibilité du texte, plus marqué en bas.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: banniere.imageUrl != null ? 0.75 : 0.15),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.25, 1.0],
                ),
              ),
            ),
            if (banniere.icon != null && banniere.imageUrl != null)
              Positioned(
                top: 14,
                right: 14,
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(banniere.icon, color: banniere.iconColor, size: 20),
                ),
              ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    banniere.titre,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      shadows: [Shadow(color: Colors.black45, blurRadius: 6)],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    banniere.sousTitre,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      shadows: [Shadow(color: Colors.black45, blurRadius: 6)],
                    ),
                  ),
                  if (banniere.ctaLabel != null) ...[
                    const SizedBox(height: 10),
                    _BoutonCta(label: banniere.ctaLabel!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton d'appel à l'action purement visuel : la carte entière est déjà
/// cliquable ([_BanniereCard]'s InkWell porte l'action réelle).
class _BoutonCta extends StatelessWidget {
  const _BoutonCta({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.orange,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 14),
        ],
      ),
    );
  }
}

/// Repli affiché pendant le chargement, ou si la photo réseau ne charge
/// pas : dégradé de la bannière + icône, jamais d'image cassée.
class _BanniereRepli extends StatelessWidget {
  const _BanniereRepli({required this.banniere});

  final BannerData banniere;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: banniere.gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: banniere.icon != null
          ? Align(
              alignment: const Alignment(0.75, -0.15),
              child: Icon(
                banniere.icon,
                color: banniere.iconColor.withValues(
                  alpha: banniere.imageUrl != null ? 0.3 : 0.85,
                ),
                size: banniere.imageUrl != null ? 46 : 72,
              ),
            )
          : null,
    );
  }
}
