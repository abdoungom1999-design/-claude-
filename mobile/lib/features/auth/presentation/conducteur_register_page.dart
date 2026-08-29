import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/auth_repository.dart';

class ConducteurRegisterPage extends StatefulWidget {
  const ConducteurRegisterPage({super.key});

  @override
  State<ConducteurRegisterPage> createState() =>
      _ConducteurRegisterPageState();
}

class _ConducteurRegisterPageState extends State<ConducteurRegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomController = TextEditingController();
  final _telephoneController = TextEditingController();
  final _motDePasseController = TextEditingController();
  final _vehiculeController = TextEditingController();
  final _authRepository = AuthRepository();

  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _nomController.dispose();
    _telephoneController.dispose();
    _motDePasseController.dispose();
    _vehiculeController.dispose();
    super.dispose();
  }

  Future<void> _sInscrire() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await _authRepository.inscrireConducteur(
        nom: _nomController.text.trim(),
        telephone: _telephoneController.text.trim(),
        motDePasse: _motDePasseController.text,
        vehiculeId: _vehiculeController.text,
      );
      if (!mounted) return;
      context.go(AppRoutes.conducteur);
    } on ApiException catch (e) {
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Créer un compte conducteur')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
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
                const SizedBox(height: 12),
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
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Véhicule',
                  hint: 'Ex : Bajaj Boxer',
                  controller: _vehiculeController,
                  prefixIcon: Icons.two_wheeler_rounded,
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
        ),
      ),
    );
  }
}
