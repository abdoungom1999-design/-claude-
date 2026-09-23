import 'package:flutter/material.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/premium_dialog.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/data/auth_repository.dart';

/// Formulaire des informations personnelles du client, chargé et
/// enregistré depuis le vrai document Firestore `users/{uid}` (voir
/// [AuthRepository.chargerProfilUtilisateur]/[AuthRepository.mettreAJourProfil]).
/// En mode démo (pas de projet Firebase configuré), retombe sur
/// [DemoData] pour continuer à fonctionner.
class InformationsPersonnellesPage extends StatefulWidget {
  const InformationsPersonnellesPage({super.key});

  @override
  State<InformationsPersonnellesPage> createState() =>
      _InformationsPersonnellesPageState();
}

class _InformationsPersonnellesPageState
    extends State<InformationsPersonnellesPage> {
  final _formKey = GlobalKey<FormState>();
  final _authRepository = AuthRepository();
  final _nomController = TextEditingController();
  final _telephoneController = TextEditingController();
  final _emailController = TextEditingController();

  bool _chargement = true;
  bool _enregistrement = false;

  @override
  void initState() {
    super.initState();
    _chargerProfil();
  }

  Future<void> _chargerProfil() async {
    final profil = await _authRepository.chargerProfilUtilisateur();
    if (!mounted) return;
    setState(() {
      _nomController.text = (profil?['nom'] as String?) ?? DemoData.monNomClient;
      _telephoneController.text =
          (profil?['telephone'] as String?) ?? DemoData.monTelephoneClient;
      _emailController.text = (profil?['email'] as String?) ?? DemoData.monEmailClient;
      _chargement = false;
    });
  }

  @override
  void dispose() {
    _nomController.dispose();
    _telephoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _enregistrement = true);
    try {
      await _authRepository.mettreAJourProfil(
        nom: _nomController.text.trim(),
        telephone: _telephoneController.text.trim(),
      );
      if (!mounted) return;
      PremiumDialog.afficher(
        context,
        icon: Icons.check_circle_outline_rounded,
        titre: 'Informations mises à jour',
        message: 'Vos informations personnelles ont bien été enregistrées.',
        succes: true,
      );
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Informations personnelles')),
      body: SafeArea(
        child: _chargement
            ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AppColors.orange, AppColors.orangeDark],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _nomController.text.isNotEmpty
                                ? _nomController.text[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      AppTextField(
                        label: 'Nom complet *',
                        controller: _nomController,
                        prefixIcon: Icons.person_outline,
                        onChanged: (_) => setState(() {}),
                        validator: (valeur) =>
                            (valeur == null || valeur.trim().length < 2)
                                ? 'Nom trop court'
                                : null,
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        label: 'Email',
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: Icons.mail_outline,
                        readOnly: true,
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 6, left: 4),
                        child: Text(
                          'La modification de l\'email n\'est pas encore disponible ici.',
                          style: TextStyle(fontSize: 11.5, color: AppColors.grey),
                        ),
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        label: 'Téléphone',
                        controller: _telephoneController,
                        keyboardType: TextInputType.phone,
                        prefixIcon: Icons.phone_outlined,
                      ),
                      const SizedBox(height: 28),
                      PrimaryButton(
                        label: 'Enregistrer les modifications',
                        isLoading: _enregistrement,
                        onPressed: _enregistrer,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
