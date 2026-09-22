import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/auth_scaffold.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/auth_repository.dart';

/// Écran d'inscription Client. L'inscription Chauffeur suit désormais
/// son propre parcours d'intégration (KYC) en 3 étapes, voir
/// [ConducteurOnboardingPage] — un chauffeur ne peut pas se créer un
/// compte en quelques champs comme un client, ses documents et son
/// véhicule doivent être soumis puis validés.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomController = TextEditingController();
  final _emailController = TextEditingController();
  final _telephoneController = TextEditingController();
  final _motDePasseController = TextEditingController();
  final _confirmationController = TextEditingController();
  final _parrainageController = TextEditingController();
  final _authRepository = AuthRepository();

  bool _motDePasseVisible = false;
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _nomController.dispose();
    _emailController.dispose();
    _telephoneController.dispose();
    _motDePasseController.dispose();
    _confirmationController.dispose();
    _parrainageController.dispose();
    super.dispose();
  }

  Future<void> _sInscrire() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await _authRepository.inscrireClient(
        nom: _nomController.text.trim(),
        telephone: _telephoneController.text.trim(),
        motDePasse: _motDePasseController.text,
      );
      if (!mounted) return;
      AppSnackbar.succes(
        context,
        'Un email de confirmation vous a été envoyé pour valider votre compte.',
      );
      context.pop(true);
    } on ApiException catch (e) {
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      icon: Icons.person_add_alt_1_rounded,
      title: 'Créer un compte',
      subtitle: 'Rejoignez Sprint pour réserver vos courses',
      form: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'Nom complet',
              controller: _nomController,
              prefixIcon: Icons.person_outline,
              validator: (valeur) => (valeur == null || valeur.trim().length < 2)
                  ? 'Nom trop court'
                  : null,
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Email',
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              prefixIcon: Icons.mail_outline,
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Téléphone',
              controller: _telephoneController,
              keyboardType: TextInputType.phone,
              prefixIcon: Icons.phone_outlined,
              validator: (valeur) => (valeur == null || valeur.trim().isEmpty)
                  ? 'Numéro requis'
                  : null,
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Mot de passe',
              controller: _motDePasseController,
              obscureText: !_motDePasseVisible,
              prefixIcon: Icons.lock_outline,
              suffixIcon: IconButton(
                icon: Icon(
                  _motDePasseVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.grey,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _motDePasseVisible = !_motDePasseVisible),
              ),
              validator: (valeur) => (valeur == null || valeur.length < 8)
                  ? '8 caractères minimum'
                  : null,
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Confirmation du mot de passe',
              controller: _confirmationController,
              obscureText: !_motDePasseVisible,
              prefixIcon: Icons.lock_outline,
              validator: (valeur) => valeur != _motDePasseController.text
                  ? 'Les mots de passe ne correspondent pas'
                  : null,
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Code de parrainage (optionnel)',
              controller: _parrainageController,
              prefixIcon: Icons.card_giftcard_outlined,
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 12),
              Text(
                _erreur!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Créer mon compte',
              isLoading: _enCours,
              onPressed: _sInscrire,
            ),
          ],
        ),
      ),
    );
  }
}
