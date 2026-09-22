import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/auth_scaffold.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/auth_repository.dart';

/// Inscription Client. Un succès renvoie `true` à l'appelant (la page de
/// connexion, qui relaie ensuite le succès à son propre appelant).
class ClientRegisterPage extends StatefulWidget {
  const ClientRegisterPage({super.key});

  @override
  State<ClientRegisterPage> createState() => _ClientRegisterPageState();
}

class _ClientRegisterPageState extends State<ClientRegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomController = TextEditingController();
  final _telephoneController = TextEditingController();
  final _motDePasseController = TextEditingController();
  final _authRepository = AuthRepository();

  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _nomController.dispose();
    _telephoneController.dispose();
    _motDePasseController.dispose();
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
      subtitle: 'Quelques informations pour commencer avec Sprint',
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
