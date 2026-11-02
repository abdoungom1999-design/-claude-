import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/onyx_vert.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/fiche_chauffeur.dart';

/// Le chauffeur modifie lui-même sa fiche : vrai prénom et nom (comme sur
/// son permis), téléphone, et sa moto (marque, modèle, couleur, plaque).
/// Dossier validé : le téléphone change aussitôt ; identité et moto partent
/// en vérification chez Sprint (pièces à l'appui) avant que ses clients ne
/// voient le changement. Rend le [ResultatFiche] à la page appelante.
class ModifierFicheChauffeurPage extends StatefulWidget {
  const ModifierFicheChauffeurPage({super.key, required this.fiche, required this.service});

  final FicheChauffeur fiche;
  final FicheChauffeurService service;

  @override
  State<ModifierFicheChauffeurPage> createState() => _ModifierFicheChauffeurPageState();
}

class _ModifierFicheChauffeurPageState extends State<ModifierFicheChauffeurPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _prenom;
  late final TextEditingController _nom;
  late final TextEditingController _telephone;
  late final TextEditingController _marque;
  late final TextEditingController _modele;
  late final TextEditingController _couleur;
  late final TextEditingController _plaque;
  bool _enregistrement = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    final f = widget.fiche;
    // Demande en attente : on repart de ce qui a été demandé.
    final d = f.modificationDemandee;
    final (prenom, nom) = f.prenomEtNom;
    _prenom = TextEditingController(text: d?.prenom ?? prenom);
    _nom = TextEditingController(text: d?.nomDeFamille ?? nom);
    _telephone = TextEditingController(text: f.telephone);
    _marque = TextEditingController(text: d?.moto.marque ?? f.moto.marque);
    _modele = TextEditingController(text: d?.moto.modele ?? f.moto.modele);
    _couleur = TextEditingController(text: d?.moto.couleur ?? f.moto.couleur);
    _plaque = TextEditingController(text: d?.plaque ?? f.plaque);
  }

  @override
  void dispose() {
    for (final c in [_prenom, _nom, _telephone, _marque, _modele, _couleur, _plaque]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _enregistrement = true;
      _erreur = null;
    });
    try {
      final resultat = await widget.service.enregistrer(
        avant: widget.fiche,
        prenom: _prenom.text,
        nomDeFamille: _nom.text,
        telephone: _telephone.text,
        moto: MotoChauffeur(marque: _marque.text, modele: _modele.text, couleur: _couleur.text),
        plaque: _plaque.text,
      );
      if (mounted) Navigator.of(context).pop(resultat);
    } on Object {
      if (mounted) {
        setState(() {
          _enregistrement = false;
          _erreur = 'Enregistrement impossible. Vérifiez votre connexion et réessayez.';
        });
      }
    }
  }

  static const _discret = TextStyle(fontSize: 12.5, color: AppColors.texteDiscret, height: 1.4);

  Widget _titre(String texte) => Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 6),
        child: Text(texte, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.texte)),
      );

  @override
  Widget build(BuildContext context) {
    final f = widget.fiche;
    return SousPageOnyx(
      child: Scaffold(
        appBar: AppBar(title: const Text('Mon profil')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (f.estValide)
                    Container(
                      key: const ValueKey('info-verification'),
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.carteHaute,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.bordVerre),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.verified_user_outlined, color: AppColors.vert, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Votre dossier est validé. Un changement de nom, de moto ou de plaque est vérifié '
                              'par Sprint avec vos pièces (permis, carte grise) avant d\'être visible par vos '
                              'clients. Votre téléphone change tout de suite.',
                              style: TextStyle(fontSize: 12.5, color: AppColors.texte, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  _titre('Identité'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppTextField(
                          key: const ValueKey('champ-prenom'),
                          label: 'Prénom',
                          controller: _prenom,
                          prefixIcon: Icons.person_outline,
                          validator: (v) => validerNomPropre(v, champ: 'Prénom'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppTextField(
                          key: const ValueKey('champ-nom'),
                          label: 'Nom',
                          controller: _nom,
                          prefixIcon: Icons.person_outline,
                          validator: (v) => validerNomPropre(v, champ: 'Nom'),
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 6, left: 4),
                    child: Text('Comme sur votre permis de conduire : c\'est ce que voient vos clients.', style: _discret),
                  ),
                  const SizedBox(height: 22),
                  _titre('Contact'),
                  AppTextField(
                    key: const ValueKey('champ-telephone'),
                    label: 'Téléphone',
                    controller: _telephone,
                    keyboardType: TextInputType.phone,
                    prefixIcon: Icons.phone_outlined,
                    validator: (v) => (v == null || v.trim().length < 6) ? 'Numéro requis.' : null,
                  ),
                  if (f.email.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.mail_outline, size: 18, color: AppColors.texteDiscret),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${f.email} (adresse de connexion)', style: _discret)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 22),
                  _titre('Ma moto'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppTextField(
                          key: const ValueKey('champ-marque'),
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
                          key: const ValueKey('champ-modele'),
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
                    key: const ValueKey('champ-couleur'),
                    label: 'Couleur',
                    hint: 'Ex : Noir',
                    controller: _couleur,
                    prefixIcon: Icons.palette_outlined,
                    validator: (v) => validerChampMoto(v, champ: 'Couleur'),
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    key: const ValueKey('champ-plaque'),
                    label: "Plaque d'immatriculation",
                    hint: 'Ex : DK-1234-AB',
                    controller: _plaque,
                    prefixIcon: Icons.pin_outlined,
                    validator: validerPlaque,
                  ),
                  if (_erreur case final erreur?) ...[
                    const SizedBox(height: 14),
                    Text(erreur, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
                  ],
                  const SizedBox(height: 28),
                  PrimaryButton(
                    label: f.estValide ? 'Enregistrer' : 'Enregistrer mes informations',
                    isLoading: _enregistrement,
                    onPressed: _enregistrement ? null : _enregistrer,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
