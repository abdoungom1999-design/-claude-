import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../data/auth_repository.dart';
import 'widgets/indicateur_etapes.dart';

/// Parcours d'inscription Chauffeur en 2 étapes : informations
/// personnelles puis véhicule. Crée le compte (Firebase réel ou mode
/// démo, voir [AuthRepository.inscrireConducteur]) puis redirige vers
/// [ConducteurShellPage], qui enchaîne vérification email puis
/// [ConducteurKYCPage] pour les vraies pièces justificatives.
///
/// Ne comporte plus d'étape "Documents" ici : cette page contenait
/// auparavant un upload simulé (aucun vrai fichier lu, juste une barre
/// de progression suivie d'un check vert), redondant et trompeur
/// maintenant que [ConducteurKYCPage] collecte les vrais documents
/// (image_picker + Firestore) juste après la création du compte.
class ConducteurOnboardingPage extends StatefulWidget {
  const ConducteurOnboardingPage({super.key});

  @override
  State<ConducteurOnboardingPage> createState() => _ConducteurOnboardingPageState();
}

class _ConducteurOnboardingPageState extends State<ConducteurOnboardingPage> {
  static const _labelsEtapes = ['Informations', 'Véhicule'];

  int _etape = 0;
  bool _enCours = false;

  final _formKeyInfos = GlobalKey<FormState>();
  final _formKeyVehicule = GlobalKey<FormState>();

  final _prenomController = TextEditingController();
  final _nomController = TextEditingController();
  final _emailController = TextEditingController();
  final _telephoneController = TextEditingController();
  final _motDePasseController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _motDePasseVisible = false;

  final _marqueController = TextEditingController();
  final _modeleController = TextEditingController();
  final _anneeController = TextEditingController();
  final _plaqueController = TextEditingController();

  @override
  void dispose() {
    _prenomController.dispose();
    _nomController.dispose();
    _emailController.dispose();
    _telephoneController.dispose();
    _motDePasseController.dispose();
    _confirmationController.dispose();
    _marqueController.dispose();
    _modeleController.dispose();
    _anneeController.dispose();
    _plaqueController.dispose();
    super.dispose();
  }

  void _etapeSuivante() {
    if (_etape == 0 && !_formKeyInfos.currentState!.validate()) return;
    setState(() => _etape++);
  }

  void _etapePrecedente() {
    if (_etape == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _etape--);
  }

  void _validerEtCreerCompte() {
    if (!_formKeyVehicule.currentState!.validate()) return;
    _soumettreDossier();
  }

  Future<void> _soumettreDossier() async {
    setState(() => _enCours = true);
    try {
      await AuthRepository().inscrireConducteur(
        nom: '${_prenomController.text.trim()} ${_nomController.text.trim()}',
        email: _emailController.text.trim(),
        telephone: _telephoneController.text.trim(),
        motDePasse: _motDePasseController.text,
        vehiculeId: '${_marqueController.text.trim()} ${_modeleController.text.trim()} '
            '(${_anneeController.text.trim()})',
        plaqueImmatriculation: _plaqueController.text.trim().toUpperCase(),
      );
      if (!mounted) return;
      AppSnackbar.succes(
        context,
        'Compte créé ! Vérifiez votre email, puis envoyez vos documents.',
        icon: Icons.folder_shared_outlined,
      );
      context.go(AppRoutes.conducteur);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.text),
          onPressed: _etapePrecedente,
        ),
        title: const Text(
          'Devenir chauffeur Sprint',
          style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: IndicateurEtapes(etapeActuelle: _etape, labels: _labelsEtapes),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: KeyedSubtree(
                    key: ValueKey(_etape),
                    child: switch (_etape) {
                      0 => _EtapeInfosPersonnelles(
                          formKey: _formKeyInfos,
                          prenomController: _prenomController,
                          nomController: _nomController,
                          emailController: _emailController,
                          telephoneController: _telephoneController,
                          motDePasseController: _motDePasseController,
                          confirmationController: _confirmationController,
                          motDePasseVisible: _motDePasseVisible,
                          onToggleMotDePasseVisible: () =>
                              setState(() => _motDePasseVisible = !_motDePasseVisible),
                        ),
                      _ => _EtapeVehicule(
                          formKey: _formKeyVehicule,
                          marqueController: _marqueController,
                          modeleController: _modeleController,
                          anneeController: _anneeController,
                          plaqueController: _plaqueController,
                        ),
                    },
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                children: [
                  if (_etape > 0) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _etapePrecedente,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          side: const BorderSide(color: AppColors.greyBorder),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Précédent',
                          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: 2,
                    child: PrimaryButton(
                      label: _etape == 1 ? 'Créer mon compte' : 'Suivant',
                      isLoading: _enCours,
                      onPressed: _etape == 1 ? _validerEtCreerCompte : _etapeSuivante,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EtapeInfosPersonnelles extends StatelessWidget {
  const _EtapeInfosPersonnelles({
    required this.formKey,
    required this.prenomController,
    required this.nomController,
    required this.emailController,
    required this.telephoneController,
    required this.motDePasseController,
    required this.confirmationController,
    required this.motDePasseVisible,
    required this.onToggleMotDePasseVisible,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController prenomController;
  final TextEditingController nomController;
  final TextEditingController emailController;
  final TextEditingController telephoneController;
  final TextEditingController motDePasseController;
  final TextEditingController confirmationController;
  final bool motDePasseVisible;
  final VoidCallback onToggleMotDePasseVisible;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _EnTeteEtape(
            titre: 'Vos informations',
            sousTitre: 'Ces informations serviront à créer votre profil chauffeur.',
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Prénom',
                  controller: prenomController,
                  prefixIcon: Icons.person_outline,
                  validator: (v) => (v == null || v.trim().length < 2) ? 'Requis' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  label: 'Nom',
                  controller: nomController,
                  prefixIcon: Icons.person_outline,
                  validator: (v) => (v == null || v.trim().length < 2) ? 'Requis' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: 'Email',
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icons.mail_outline,
            validator: (v) => (v == null || !v.contains('@')) ? 'Email invalide' : null,
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: 'Téléphone',
            controller: telephoneController,
            keyboardType: TextInputType.phone,
            prefixIcon: Icons.phone_outlined,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Numéro requis' : null,
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: 'Mot de passe',
            controller: motDePasseController,
            obscureText: !motDePasseVisible,
            prefixIcon: Icons.lock_outline,
            suffixIcon: IconButton(
              icon: Icon(
                motDePasseVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: AppColors.grey,
                size: 20,
              ),
              onPressed: onToggleMotDePasseVisible,
            ),
            validator: (v) => (v == null || v.length < 8) ? '8 caractères minimum' : null,
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: 'Confirmation du mot de passe',
            controller: confirmationController,
            obscureText: !motDePasseVisible,
            prefixIcon: Icons.lock_outline,
            validator: (v) =>
                v != motDePasseController.text ? 'Les mots de passe ne correspondent pas' : null,
          ),
        ],
      ),
    );
  }
}

class _EtapeVehicule extends StatelessWidget {
  const _EtapeVehicule({
    required this.formKey,
    required this.marqueController,
    required this.modeleController,
    required this.anneeController,
    required this.plaqueController,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController marqueController;
  final TextEditingController modeleController;
  final TextEditingController anneeController;
  final TextEditingController plaqueController;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _EnTeteEtape(
            titre: 'Votre véhicule',
            sousTitre: 'Renseignez le véhicule que vous utiliserez pour vos courses.',
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Marque',
                  hint: 'Ex : Peugeot',
                  controller: marqueController,
                  prefixIcon: Icons.directions_car_outlined,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  label: 'Modèle',
                  hint: 'Ex : 308',
                  controller: modeleController,
                  prefixIcon: Icons.directions_car_outlined,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: 'Année',
            hint: 'Ex : 2019',
            controller: anneeController,
            keyboardType: TextInputType.number,
            prefixIcon: Icons.calendar_today_outlined,
            validator: (v) => (v == null || v.trim().length != 4) ? 'Année invalide' : null,
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: "Plaque d'immatriculation",
            hint: 'Ex : DK-1234-AB',
            controller: plaqueController,
            prefixIcon: Icons.pin_outlined,
            validator: (v) => (v == null || v.trim().length < 4) ? 'Plaque invalide' : null,
          ),
        ],
      ),
    );
  }
}

class _EnTeteEtape extends StatelessWidget {
  const _EnTeteEtape({required this.titre, required this.sousTitre});

  final String titre;
  final String sousTitre;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titre, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(
          sousTitre,
          style: const TextStyle(fontSize: 13, color: AppColors.grey, height: 1.4),
        ),
      ],
    );
  }
}
