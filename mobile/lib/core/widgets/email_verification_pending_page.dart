import 'dart:async';

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
///
/// Se débloque automatiquement, sans action de l'utilisateur : un
/// polling toutes les 4 secondes interroge Firebase
/// (`user.reload()`), et un [WidgetsBindingObserver] relance
/// immédiatement une vérification dès que l'utilisateur revient sur
/// l'app (après avoir cliqué le lien reçu par email dans un autre
/// onglet/une autre app). Le bouton manuel reste disponible en repli.
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
    extends State<EmailVerificationPendingPage> with WidgetsBindingObserver {
  final _authRepository = AuthRepository();
  Timer? _minuteurPolling;
  bool _verificationEnCours = false;
  bool _enCoursRenvoi = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _minuteurPolling = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _verifierEtRedirigerSiValide(depuisPolling: true),
    );
  }

  @override
  void dispose() {
    _minuteurPolling?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // L'utilisateur revient probablement de sa boîte mail (autre onglet
    // ou autre app) après avoir cliqué le lien : on vérifie tout de
    // suite plutôt que d'attendre le prochain tick du polling.
    if (state == AppLifecycleState.resumed) {
      _verifierEtRedirigerSiValide(depuisPolling: true);
    }
  }

  /// Vérifie si l'email est désormais confirmé et redirige
  /// automatiquement si c'est le cas. Utilisé aussi bien par le
  /// polling/l'écouteur de cycle de vie (silencieux, sans indicateur de
  /// chargement) que par le bouton manuel "J'ai vérifié, réessayer"
  /// (avec indicateur et message d'échec explicite).
  Future<void> _verifierEtRedirigerSiValide({required bool depuisPolling}) async {
    if (_verificationEnCours) return;
    if (!depuisPolling) {
      setState(() {
        _verificationEnCours = true;
        _message = null;
      });
    }
    try {
      final verifie = await _authRepository.rafraichirEtVerifierEmail();
      if (!mounted) return;
      if (verifie) {
        _minuteurPolling?.cancel();
        context.go(widget.destinationApresVerification);
        return;
      }
      if (!depuisPolling) {
        setState(() {
          _message = "Toujours pas vérifié. Cliquez d'abord sur le lien "
              'reçu par email — la page se débloquera automatiquement.';
        });
      }
    } catch (_) {
      // En arrière-plan (polling silencieux), un aléa réseau ponctuel
      // ne doit pas afficher d'erreur : le prochain tick réessaiera.
      // Sur un clic manuel en revanche, rester muet donnerait
      // l'impression d'un bouton qui ne répond pas — on informe donc
      // l'utilisateur explicitement.
      if (!depuisPolling) {
        setState(() {
          _message = 'Impossible de vérifier pour le moment. Vérifiez votre '
              'connexion et réessayez.';
        });
      }
    } finally {
      if (mounted && !depuisPolling) {
        setState(() => _verificationEnCours = false);
      }
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
    _minuteurPolling?.cancel();
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
                'Cliquez sur le lien dans votre boîte mail : cette page se '
                'débloquera automatiquement, sans rien faire de plus.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.grey, height: 1.6),
              ),
              const SizedBox(height: 20),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.orange),
                ),
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
                  onPressed: _verificationEnCours
                      ? null
                      : () => _verifierEtRedirigerSiValide(depuisPolling: false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _verificationEnCours
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
