import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/data/auth_repository.dart';
import '../network/api_exception.dart';
import '../router/app_routes.dart';
import '../theme/app_colors.dart';

/// Écran de blocage affiché tant que l'adresse email du compte n'a pas
/// été vérifiée (lien envoyé par email à l'inscription, via
/// [AuthRepository.inscrireClient]/[inscrireConducteur]). Bloque
/// l'accès aux fonctionnalités de l'app (courses, carte, etc.) — voir
/// `HomeShellPage` et `ConducteurShellPage`, qui affichent cette page à
/// la place du tableau de bord tant que
/// `FirebaseAuth.currentUser.emailVerified` est faux.
class EmailVerificationPendingPage extends StatefulWidget {
  const EmailVerificationPendingPage({
    super.key,
    required this.destinationApresVerification,
  });

  /// Route vers laquelle naviguer une fois l'email vérifié (différente
  /// pour Client et Conducteur : chacun revient sur son propre tableau
  /// de bord).
  final String destinationApresVerification;

  @override
  State<EmailVerificationPendingPage> createState() =>
      _EmailVerificationPendingPageState();
}

class _EmailVerificationPendingPageState
    extends State<EmailVerificationPendingPage> {
  final _authRepository = AuthRepository();
  bool _enCoursVerification = false;
  bool _enCoursRenvoi = false;
  String? _message;

  Future<void> _jaiVerifie() async {
    setState(() {
      _enCoursVerification = true;
      _message = null;
    });
    try {
      final verifie = await _authRepository.rafraichirEtVerifierEmail();
      if (!mounted) return;
      if (verifie) {
        context.go(widget.destinationApresVerification);
      } else {
        setState(() {
          _message = "Toujours pas vérifié. Cliquez d'abord sur le lien "
              'reçu par email, puis réessayez.';
        });
      }
    } finally {
      if (mounted) setState(() => _enCoursVerification = false);
    }
  }

  Future<void> _renvoyerEmail() async {
    setState(() {
      _enCoursRenvoi = true;
      _message = null;
    });
    try {
      await _authRepository.renvoyerEmailVerification();
      if (!mounted) return;
      setState(() => _message = 'Email de vérification renvoyé.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _enCoursRenvoi = false);
    }
  }

  Future<void> _seDeconnecter() async {
    await _authRepository.deconnecter();
    if (mounted) context.go(AppRoutes.espacePro);
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(
                  color: AppColors.orangeLight,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.mark_email_unread_outlined,
                  color: AppColors.orange,
                  size: 52,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Vérifiez votre adresse email',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                'Un email de confirmation vous a été envoyé'
                '${email != null && email.isNotEmpty ? ' à $email' : ''}. '
                'Veuillez cliquer sur le lien dans votre boîte mail pour '
                'valider votre compte, puis reconnectez-vous.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.grey, height: 1.6),
              ),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(
                  _message!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _enCoursVerification ? null : _jaiVerifie,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _enCoursVerification
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          "J'ai vérifié, réessayer",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _enCoursRenvoi ? null : _renvoyerEmail,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  side: const BorderSide(color: AppColors.greyBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  _enCoursRenvoi ? 'Envoi en cours…' : "Renvoyer l'email",
                  style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _seDeconnecter,
                child: const Text(
                  'Se déconnecter',
                  style: TextStyle(color: AppColors.grey, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
