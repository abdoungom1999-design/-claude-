import 'package:flutter/material.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/premium_dialog.dart';
import '../../../core/widgets/primary_button.dart';

/// Formulaire modifiable des informations personnelles du client. Les
/// modifications sont conservées en mémoire (voir [DemoData]) : elles se
/// reflètent immédiatement sur l'écran Compte, mais ne survivent pas à un
/// rechargement complet de la page (aucun backend public pour les
/// persister à ce stade).
class InformationsPersonnellesPage extends StatefulWidget {
  const InformationsPersonnellesPage({super.key});

  @override
  State<InformationsPersonnellesPage> createState() =>
      _InformationsPersonnellesPageState();
}

class _InformationsPersonnellesPageState
    extends State<InformationsPersonnellesPage> {
  final _formKey = GlobalKey<FormState>();
  late final _nomController = TextEditingController(text: DemoData.monNomClient);
  late final _telephoneController =
      TextEditingController(text: DemoData.monTelephoneClient);
  late final _emailController = TextEditingController(text: DemoData.monEmailClient);

  @override
  void dispose() {
    _nomController.dispose();
    _telephoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _enregistrer() {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      DemoData.mettreAJourProfilClient(
        nom: _nomController.text.trim(),
        telephone: _telephoneController.text.trim(),
        email: _emailController.text.trim(),
      );
    });

    PremiumDialog.afficher(
      context,
      icon: Icons.check_circle_outline_rounded,
      titre: 'Informations mises à jour',
      message: 'Vos informations personnelles ont bien été enregistrées.',
      succes: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Informations personnelles')),
      body: SafeArea(
        child: SingleChildScrollView(
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
                  label: 'Nom complet',
                  controller: _nomController,
                  prefixIcon: Icons.person_outline,
                  validator: (valeur) =>
                      (valeur == null || valeur.trim().length < 2)
                          ? 'Nom trop court'
                          : null,
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label: 'Téléphone',
                  controller: _telephoneController,
                  keyboardType: TextInputType.phone,
                  prefixIcon: Icons.phone_outlined,
                  validator: (valeur) =>
                      (valeur == null || valeur.trim().isEmpty)
                          ? 'Numéro requis'
                          : null,
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label: 'Email',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: Icons.mail_outline,
                  validator: (valeur) => (valeur == null || !valeur.contains('@'))
                      ? 'Email invalide'
                      : null,
                ),
                const SizedBox(height: 28),
                PrimaryButton(
                  label: 'Enregistrer les modifications',
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
