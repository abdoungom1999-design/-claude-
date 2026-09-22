import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/premium_dialog.dart';

/// Écran d'accueil pré-authentification : héros premium en noir profond,
/// slogan, et les trois entrées de connexion empilées. Aucune photo de
/// véhicule n'est utilisée (pas de banque d'images de marque disponible
/// dans cet environnement) : une moto animée (glissement fluide en
/// boucle, voir [_MotoAnimee]) tient lieu de visuel héros, dans le même
/// esprit premium.
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            children: [
              const Spacer(),
              const _MotoAnimee(),
              const SizedBox(height: 36),
              const Text(
                'Sprint',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Votre chauffeur en quelques secondes',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 15,
                ),
              ),
              const Spacer(flex: 2),
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
                onPressed: () =>
                    PremiumDialog.bientotDisponible(context, 'Connexion Apple'),
              ),
              const SizedBox(height: 20),
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

/// Moto animée : glissement fluide en va-et-vient (translation + très
/// léger tangage), avec de fines lignes de vitesse qui pulsent derrière
/// elle, pour un héros vivant sans dépendre d'une image.
class _MotoAnimee extends StatefulWidget {
  const _MotoAnimee();

  @override
  State<_MotoAnimee> createState() => _MotoAnimeeState();
}

class _MotoAnimeeState extends State<_MotoAnimee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _glissement;
  late final Animation<double> _tangage;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _glissement = Tween<double>(begin: -16, end: 16).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
    _tangage = Tween<double>(begin: -3, end: 3).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 150,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final avance = _glissement.value > 0;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Lignes de vitesse, du côté opposé au sens du glissement.
              Positioned(
                left: avance ? null : 6,
                right: avance ? 6 : null,
                child: Opacity(
                  opacity: (_glissement.value.abs() / 16).clamp(0.15, 1.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(3, (i) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Container(
                          width: 18.0 - (i * 4),
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(_glissement.value, _tangage.value),
                child: Transform.rotate(
                  angle: (_glissement.value / 16) * 0.05,
                  child: Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.orange, AppColors.orangeDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(36),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.orange.withValues(alpha: 0.35),
                          blurRadius: 40,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.two_wheeler_rounded,
                      color: Colors.white,
                      size: 64,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
