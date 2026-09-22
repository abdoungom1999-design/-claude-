import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/auth_scaffold.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/auth_repository.dart';

/// Connexion Conducteur. Contrairement au flux Client, l'accès au
/// tableau de bord Conducteur exige une session dès l'entrée (le
/// tableau de bord affiche des données de compte).
class ConducteurLoginPage extends StatefulWidget {
  const ConducteurLoginPage({super.key});

  @override
  State<ConducteurLoginPage> createState() => _ConducteurLoginPageState();
}

class _ConducteurLoginPageState extends State<ConducteurLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _telephoneController = TextEditingController();
  final _motDePasseController = TextEditingController();
  final _authRepository = AuthRepository();

  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _telephoneController.dispose();
    _motDePasseController.dispose();
    super.dispose();
  }

  Future<void> _seConnecter() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await _authRepository.connecterConducteur(
        telephone: _telephoneController.text.trim(),
        motDePasse: _motDePasseController.text,
      );
      if (!mounted) return;
      AppSnackbar.succes(
        context,
        'Un email de confirmation vous a été envoyé pour valider votre compte.',
      );
      context.go(AppRoutes.conducteur);
    } on ApiException catch (e) {
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      icon: Icons.two_wheeler_rounded,
      title: 'Espace Conducteur',
      subtitle: 'Connectez-vous pour prendre des courses',
      form: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
              obscureText: true,
              prefixIcon: Icons.lock_outline,
              validator: (valeur) => (valeur == null || valeur.length < 8)
                  ? '8 caractères minimum'
                  : null,
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
              label: 'Se connecter',
              isLoading: _enCours,
              onPressed: _seConnecter,
            ),
          ],
        ),
      ),
      footer: Center(
        child: TextButton(
          onPressed: () => context.push(AppRoutes.conducteurRegister),
          child: const Text(
            'Pas encore de compte ? Créer un compte',
            style: TextStyle(color: AppColors.grey, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}
