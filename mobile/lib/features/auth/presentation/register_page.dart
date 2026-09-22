import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/auth_scaffold.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/auth_repository.dart';

enum _Role { client, chauffeur }

/// Écran d'inscription unifié : un sélecteur en haut choisit le rôle
/// (Client ou Chauffeur), qui détermine à la fois les champs affichés
/// (véhicule pour un chauffeur) et l'endpoint appelé à la validation.
/// Remplace les anciens écrans séparés ClientRegisterPage /
/// ConducteurRegisterPage.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key, this.roleInitial = 'client'});

  /// 'client' ou 'chauffeur' — détermine le rôle pré-sélectionné selon le
  /// point d'entrée (ex : lien "Créer un compte" côté conducteur).
  final String roleInitial;

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
  final _vehiculeController = TextEditingController();
  final _authRepository = AuthRepository();

  late _Role _role;
  bool _motDePasseVisible = false;
  bool _enCours = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _role = widget.roleInitial == 'chauffeur' ? _Role.chauffeur : _Role.client;
  }

  @override
  void dispose() {
    _nomController.dispose();
    _emailController.dispose();
    _telephoneController.dispose();
    _motDePasseController.dispose();
    _confirmationController.dispose();
    _parrainageController.dispose();
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
      if (_role == _Role.client) {
        await _authRepository.inscrireClient(
          nom: _nomController.text.trim(),
          telephone: _telephoneController.text.trim(),
          motDePasse: _motDePasseController.text,
        );
        if (!mounted) return;
        context.pop(true);
      } else {
        await _authRepository.inscrireConducteur(
          nom: _nomController.text.trim(),
          telephone: _telephoneController.text.trim(),
          motDePasse: _motDePasseController.text,
          vehiculeId: _vehiculeController.text,
        );
        if (!mounted) return;
        context.go(AppRoutes.conducteur);
      }
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
      subtitle: 'Rejoignez Sprint en tant que client ou chauffeur',
      form: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SelecteurRole(
              role: _role,
              onChanged: (role) => setState(() => _role = role),
            ),
            const SizedBox(height: 18),
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
            if (_role == _Role.chauffeur) ...[
              const SizedBox(height: 14),
              AppTextField(
                label: 'Véhicule',
                hint: 'Ex : Bajaj Boxer',
                controller: _vehiculeController,
                prefixIcon: Icons.two_wheeler_rounded,
              ),
            ],
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

class _SelecteurRole extends StatelessWidget {
  const _SelecteurRole({required this.role, required this.onChanged});

  final _Role role;
  final ValueChanged<_Role> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.greyLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(child: _Segment(
            label: 'Client',
            selectionne: role == _Role.client,
            onTap: () => onChanged(_Role.client),
          )),
          Expanded(child: _Segment(
            label: 'Chauffeur',
            selectionne: role == _Role.chauffeur,
            onTap: () => onChanged(_Role.chauffeur),
          )),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selectionne,
    required this.onTap,
  });

  final String label;
  final bool selectionne;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selectionne ? AppColors.background : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          boxShadow: selectionne
              ? const [
                  BoxShadow(
                    color: AppColors.shadowSoft,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
            color: selectionne ? AppColors.text : AppColors.grey,
          ),
        ),
      ),
    );
  }
}
