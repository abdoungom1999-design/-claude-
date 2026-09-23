import 'package:flutter/material.dart';
import '../../features/auth/data/auth_repository.dart';
import '../network/api_exception.dart';
import '../theme/app_colors.dart';
import 'app_snackbar.dart';
import 'app_text_field.dart';

/// Boîte de dialogue "Mot de passe oublié ?", partagée entre la
/// connexion Client et Conducteur : demande une adresse email (pré-
/// remplie avec [emailInitial] si le champ mixte de l'écran de
/// connexion contenait déjà un email) et envoie le lien de
/// réinitialisation via [AuthRepository.reinitialiserMotDePasse].
Future<void> afficherDialogueMotDePasseOublie(
  BuildContext context, {
  String? emailInitial,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DialogueMotDePasseOublie(emailInitial: emailInitial),
  );
}

class _DialogueMotDePasseOublie extends StatefulWidget {
  const _DialogueMotDePasseOublie({this.emailInitial});

  final String? emailInitial;

  @override
  State<_DialogueMotDePasseOublie> createState() =>
      _DialogueMotDePasseOublieState();
}

class _DialogueMotDePasseOublieState extends State<_DialogueMotDePasseOublie> {
  late final _emailController = TextEditingController(
    text: (widget.emailInitial ?? '').contains('@') ? widget.emailInitial : '',
  );
  final _authRepository = AuthRepository();
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    final email = _emailController.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _erreur = 'Entrez une adresse email valide.');
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await _authRepository.reinitialiserMotDePasse(email);
      if (!mounted) return;
      Navigator.of(context).pop();
      AppSnackbar.succes(
        context,
        'Un email pour réinitialiser votre mot de passe vous a été envoyé.',
      );
    } on ApiException catch (e) {
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Mot de passe oublié',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Indiquez votre adresse email : nous vous enverrons un lien '
              'pour réinitialiser votre mot de passe.',
              style: TextStyle(fontSize: 13, color: AppColors.grey, height: 1.4),
            ),
            const SizedBox(height: 20),
            AppTextField(
              label: 'Email',
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              prefixIcon: Icons.mail_outline,
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 10),
              Text(
                _erreur!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _enCours ? null : () => Navigator.of(context).pop(),
                    child: const Text(
                      'Annuler',
                      style: TextStyle(color: AppColors.grey, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _enCours ? null : _envoyer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _enCours
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Envoyer',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
