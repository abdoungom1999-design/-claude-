import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/premium_dialog.dart';

/// URL de la photo héros (moto noire, sportive, de profil). Libre de
/// droits (licence Unsplash). Ce bac à sable bloque l'accès sortant vers
/// les CDN d'images (Unsplash, Wikimedia, Pexels, Pixabay — testé et
/// confirmé), donc cette URL précise n'a pas pu être chargée ni vérifiée
/// depuis cet environnement. [_HeroMoto] a un `errorBuilder` de repli
/// pour ne jamais afficher une image cassée si jamais elle ne se charge
/// pas : changez uniquement cette constante pour la remplacer.
const _urlPhotoHero =
    'https://images.unsplash.com/photo-1558981806-ec527fa84c39'
    '?auto=format&fit=crop&w=1200&q=80';

/// Écran d'accueil pré-authentification : héros premium en noir profond,
/// slogan, et les trois entrées de connexion empilées. Photo réelle
/// (voir [_urlPhotoHero]) avec un effet Ken Burns (zoom lent en boucle)
/// plutôt qu'une illustration vectorielle.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  Future<void> _seConnecter(BuildContext context) async {
    final connecte = await context.push<bool>(AppRoutes.clientLogin);
    if (connecte == true && context.mounted) {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.noirProfond,
      body: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.42,
            width: double.infinity,
            child: const _HeroMoto(),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Sprint',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Votre chauffeur en quelques secondes',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _BoutonAuth(
                      label: 'Continuer avec mon numéro',
                      orange: true,
                      onPressed: () => _seConnecter(context),
                    ),
                    const SizedBox(height: 12),
                    _BoutonAuth(
                      label: 'Continuer avec mon email',
                      orange: false,
                      onPressed: () => _seConnecter(context),
                    ),
                    const SizedBox(height: 12),
                    _BoutonAuth(
                      label: 'Continuer avec Apple',
                      orange: false,
                      icon: Icons.apple,
                      onPressed: () => PremiumDialog.bientotDisponible(
                        context,
                        'Connexion Apple',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => context.push(AppRoutes.espacePro),
                      child: Text(
                        'Espace conducteur / admin',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoutonAuth extends StatelessWidget {
  const _BoutonAuth({
    required this.label,
    required this.orange,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final bool orange;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: orange ? AppColors.orange : Colors.white,
          foregroundColor: orange ? Colors.white : AppColors.text,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 8),
            ],
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// Photo héros plein cadre (voir [_urlPhotoHero]) avec un effet Ken
/// Burns : zoom très lent et continu en boucle, pour donner de la vie à
/// l'image sans mouvement saccadé "dessin animé". Un dégradé sombre en
/// haut assure la lisibilité de la barre de statut, un second en bas
/// fond l'image dans le noir profond de l'écran. Si la photo ne charge
/// pas (réseau du visiteur, ou URL à remplacer), un repli dégradé
/// orange/noir avec pictogramme moto s'affiche à la place — jamais
/// d'icône d'image cassée.
class _HeroMoto extends StatefulWidget {
  const _HeroMoto();

  @override
  State<_HeroMoto> createState() => _HeroMotoState();
}

class _HeroMotoState extends State<_HeroMoto> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _zoom;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat(reverse: true);
    _zoom = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform.scale(
              scale: _zoom.value,
              child: child,
            ),
            child: Image.network(
              _urlPhotoHero,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.orange,
                    strokeWidth: 2.5,
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) => const _HeroMotoRepli(),
            ),
          ),
          // Dégradé haut : lisibilité de la barre de statut.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xB3000000), Colors.transparent],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.35],
              ),
            ),
          ),
          // Dégradé bas : fond l'image dans AppColors.noirProfond.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, AppColors.noirProfond],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.55, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Repli affiché si la photo réseau ne charge pas (voir [_HeroMoto]).
class _HeroMotoRepli extends StatelessWidget {
  const _HeroMotoRepli();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.noirProfondClair, AppColors.noirProfond],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.orange, AppColors.orangeDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: AppColors.orange.withValues(alpha: 0.35),
              blurRadius: 32,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: const Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 54),
      ),
    );
  }
}
