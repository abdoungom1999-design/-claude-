import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/auth_repository.dart';

/// Connexion Client. Poussé contextuellement lorsqu'une action protégée
/// (ex : commander une course) est déclenchée sans session active ; un
/// succès renvoie `true` à l'appelant via [context.pop].
class ClientLoginPage extends StatefulWidget {
  const ClientLoginPage({super.key});

  @override
  State<ClientLoginPage> createState() => _ClientLoginPageState();
}

class _ClientLoginPageState extends State<ClientLoginPage> {
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
      await _authRepository.connecterClient(
        telephone: _telephoneController.text.trim(),
        motDePasse: _motDePasseController.text,
      );
      if (!mounted) return;
      context.pop(true);
    } on ApiException catch (e) {
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _allerVersInscription() async {
    final inscrit = await context.push<bool>(AppRoutes.clientRegister);
    if (inscrit == true && mounted) {
      context.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connexion')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Connectez-vous pour réserver une course ou envoyer un colis',
                  style: TextStyle(fontSize: 14, color: AppColors.grey),
                ),
                const SizedBox(height: 24),
                AppTextField(
                  label: 'Téléphone',
                  controller: _telephoneController,
                  keyboardType: TextInputType.phone,
                  prefixIcon: Icons.phone_outlined,
                  validator: (valeur) => (valeur == null || valeur.trim().isEmpty)
                      ? 'Numéro requis'
                      : null,
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: _allerVersInscription,
                    child: const Text('Pas encore de compte ? Créer un compte'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
