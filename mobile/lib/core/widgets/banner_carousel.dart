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
      gradientColors: [AppColors.vert, AppColors.vertFonce],
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
      gradientColors: const [AppColors.orange, AppColors.orangeDark],
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
    // Structure divisée : à gauche le panneau coloré (texte + CTA), à
    // droite la photo (ou, à défaut, un panneau icône plus sombre), les
    // deux se fondant l'un dans l'autre via un dégradé de transition.
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: () => _onTap(context),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: banniere.gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      banniere.titre,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      banniere.sousTitre,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                    if (banniere.ctaLabel != null) ...[
                      const SizedBox(height: 12),
                      _BoutonCta(label: banniere.ctaLabel!),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 4,
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
                  // Fondu du bord gauche de la photo vers la couleur du
                  // panneau, pour que les deux moitiés se fondent.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          banniere.gradientColors.first,
                          banniere.gradientColors.first.withValues(alpha: 0),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        stops: const [0.0, 0.5],
                      ),
                    ),
                  ),
                  if (banniere.icon != null && banniere.imageUrl != null)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(banniere.icon, color: Colors.white, size: 18),
                      ),
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

/// Bouton d'appel à l'action purement visuel : la carte entière est déjà
/// cliquable ([_BanniereCard]'s InkWell porte l'action réelle).
class _BoutonCta extends StatelessWidget {
  const _BoutonCta({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_forward_rounded, color: AppColors.text, size: 14),
        ],
      ),
    );
  }
}

/// Repli affiché pendant le chargement, ou si la photo réseau ne charge
/// pas : panneau uni dans la couleur de la bannière + icône, jamais
/// d'image cassée.
class _BanniereRepli extends StatelessWidget {
  const _BanniereRepli({required this.banniere});

  final BannerData banniere;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: banniere.gradientColors.last,
      alignment: Alignment.center,
      child: banniere.icon != null
          ? Icon(
              banniere.icon,
              color: Colors.white.withValues(alpha: 0.6),
              size: 40,
            )
          : null,
    );
  }
}
