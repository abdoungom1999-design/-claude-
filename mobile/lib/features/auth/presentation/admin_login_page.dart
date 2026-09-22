import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/auth_scaffold.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/auth_repository.dart';

/// Connexion Admin. Comme pour le Conducteur, l'accès au tableau de bord
/// exige une session dès l'entrée. Aucune inscription publique : les
/// comptes admin sont créés hors application.
class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _motDePasseController = TextEditingController();
  final _authRepository = AuthRepository();

  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _emailController.dispose();
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
      await _authRepository.connecterAdmin(
        email: _emailController.text.trim(),
        motDePasse: _motDePasseController.text,
      );
      if (!mounted) return;
      context.go(AppRoutes.admin);
    } on ApiException catch (e) {
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      icon: Icons.admin_panel_settings_outlined,
      title: 'Espace Admin',
      subtitle: 'Gestion de la plateforme Sprint',
      form: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'Email',
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              prefixIcon: Icons.mail_outline,
              validator: (valeur) =>
                  (valeur == null || !valeur.contains('@'))
                  ? 'Email invalide'
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
    );
  }
}
