import 'package:flutter/material.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/auth_scaffold.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/data/auth_repository.dart';
import '../data/fiche_chauffeur.dart';

/// Enregistrement du profil manquant (voir
/// [AuthRepository.completerProfilConducteur]) ; remplaçable dans les tests.
typedef EnregistrerProfilChauffeur = Future<void> Function({
  required String nom,
  required String telephone,
  required String vehiculeId,
  required String prenom,
  required String nomDeFamille,
  required Map<String, String> moto,
});

/// « Terminez votre inscription » : le chauffeur est connecté, mais son profil
/// `users/{uid}` n'a jamais été enregistré (inscription interrompue juste
/// après la création du compte). Avant, il arrivait sur « Complétez votre
/// dossier » et l'envoi de ses pièces était refusé (« firestore/permission-denied »).
/// Mêmes champs et mêmes contrôles que l'inscription chauffeur ; l'adresse
/// e-mail est celle du compte connecté.
class ConducteurProfilIncompletPage extends StatefulWidget {
  const ConducteurProfilIncompletPage({
    super.key,
    required this.onTermine,
    required this.onDeconnexion,
    this.enregistrer,
  });

  /// Profil enregistré : l'espace chauffeur relit le profil et continue
  /// (« Complétez votre dossier »).
  final VoidCallback onTermine;
  final VoidCallback onDeconnexion;
  final EnregistrerProfilChauffeur? enregistrer;

  @override
  State<ConducteurProfilIncompletPage> createState() => _ConducteurProfilIncompletPageState();
}

class _ConducteurProfilIncompletPageState extends State<ConducteurProfilIncompletPage> {
  final _formKey = GlobalKey<FormState>();
  final _prenom = TextEditingController();
  final _nom = TextEditingController();
  final _telephone = TextEditingController();
  final _marque = TextEditingController();
  final _modele = TextEditingController();
  final _couleur = TextEditingController();
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    for (final c in [_prenom, _nom, _telephone, _marque, _modele, _couleur]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _enregistrer() async {
    if (_enCours || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final prenom = capitaliserNom(_prenom.text);
      final nomDeFamille = capitaliserNom(_nom.text);
      final moto = MotoChauffeur(
        marque: _marque.text.trim(),
        modele: _modele.text.trim(),
        couleur: _couleur.text.trim(),
      );
      await (widget.enregistrer ?? AuthRepository().completerProfilConducteur)(
        nom: nomCompletDe(prenom, nomDeFamille),
        telephone: _telephone.text.trim(),
        vehiculeId: moto.description,
        prenom: prenom,
        nomDeFamille: nomDeFamille,
        moto: moto.versFirestore(),
      );
      if (mounted) widget.onTermine();
    } on ApiException catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _erreur = "L'enregistrement n'a pas abouti (code : ${e.runtimeType}). Réessayez.");
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      enCours: _enCours,
      showBackButton: false,
      icon: Icons.person_add_alt_1_outlined,
      title: 'Terminez votre inscription',
      subtitle: "Votre compte est créé, mais votre profil chauffeur n'a pas été enregistré. "
          'Complétez ces informations pour envoyer ensuite vos documents.',
      form: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'Prénom',
                    controller: _prenom,
                    prefixIcon: Icons.person_outline,
                    validator: (v) => validerNomPropre(v, champ: 'Prénom'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    label: 'Nom',
                    controller: _nom,
                    prefixIcon: Icons.person_outline,
                    validator: (v) => validerNomPropre(v, champ: 'Nom'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Téléphone',
              controller: _telephone,
              keyboardType: TextInputType.phone,
              prefixIcon: Icons.phone_outlined,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Numéro requis' : null,
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'Marque',
                    hint: 'Ex : Bajaj',
                    controller: _marque,
                    prefixIcon: Icons.two_wheeler_rounded,
                    validator: (v) => validerChampMoto(v, champ: 'Marque'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    label: 'Modèle',
                    hint: 'Ex : Boxer 125',
                    controller: _modele,
                    prefixIcon: Icons.two_wheeler_rounded,
                    validator: (v) => validerChampMoto(v, champ: 'Modèle'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Couleur',
              hint: 'Ex : Noir',
              controller: _couleur,
              prefixIcon: Icons.palette_outlined,
              validator: (v) => validerChampMoto(v, champ: 'Couleur'),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 12),
              Text(_erreur!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
            const SizedBox(height: 18),
            PrimaryButton(
              label: 'Enregistrer et continuer',
              isLoading: _enCours,
              onPressed: _enregistrer,
            ),
          ],
        ),
      ),
      footer: Center(
        child: TextButton(
          onPressed: _enCours ? null : widget.onDeconnexion,
          child: const Text('Se déconnecter', style: TextStyle(color: AppColors.texteDiscret, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
