import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/premium_dialog.dart';
import '../../../core/widgets/primary_button.dart';

class _Appareil {
  _Appareil({
    required this.nom,
    required this.localisation,
    required this.date,
    this.actuel = false,
  });

  final String nom;
  final String localisation;
  final String date;
  final bool actuel;
}

/// Écran Sécurité : changement de mot de passe, authentification à deux
/// facteurs (démo) et gestion des appareils connectés.
class SecuritePage extends StatefulWidget {
  const SecuritePage({super.key});

  @override
  State<SecuritePage> createState() => _SecuritePageState();
}

class _SecuritePageState extends State<SecuritePage> {
  final _formKey = GlobalKey<FormState>();
  final _actuelController = TextEditingController();
  final _nouveauController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _motDePasseVisible = false;
  bool _authDeuxFacteurs = false;

  final List<_Appareil> _appareils = [
    _Appareil(
      nom: 'Ce navigateur',
      localisation: 'Dakar, Sénégal',
      date: 'Session active',
      actuel: true,
    ),
    _Appareil(
      nom: 'iPhone 13',
      localisation: 'Dakar, Sénégal',
      date: 'Connecté il y a 3 jours',
    ),
    _Appareil(
      nom: 'Chrome · Windows',
      localisation: 'Thiès, Sénégal',
      date: 'Connecté il y a 2 semaines',
    ),
  ];

  @override
  void dispose() {
    _actuelController.dispose();
    _nouveauController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  void _mettreAJourMotDePasse() {
    if (!_formKey.currentState!.validate()) return;
    _actuelController.clear();
    _nouveauController.clear();
    _confirmationController.clear();
    PremiumDialog.afficher(
      context,
      icon: Icons.lock_outline_rounded,
      titre: 'Mot de passe mis à jour',
      message: 'Votre mot de passe a été modifié avec succès.',
      succes: true,
    );
  }

  void _deconnecterAppareil(_Appareil appareil) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Déconnecter cet appareil ?'),
        content: Text('${appareil.nom} ne pourra plus accéder à votre compte.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() => _appareils.remove(appareil));
            },
            child: const Text('Déconnecter'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sécurité')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Changer le mot de passe',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextField(
                    label: 'Mot de passe actuel',
                    controller: _actuelController,
                    obscureText: !_motDePasseVisible,
                    prefixIcon: Icons.lock_outline,
                    validator: (v) => (v == null || v.length < 8)
                        ? '8 caractères minimum'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'Nouveau mot de passe',
                    controller: _nouveauController,
                    obscureText: !_motDePasseVisible,
                    prefixIcon: Icons.lock_reset_rounded,
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
                    validator: (v) =>
                        (v == null || v.length < 8) ? '8 caractères minimum' : null,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'Confirmer le nouveau mot de passe',
                    controller: _confirmationController,
                    obscureText: !_motDePasseVisible,
                    prefixIcon: Icons.lock_reset_rounded,
                    validator: (v) => v != _nouveauController.text
                        ? 'Les mots de passe ne correspondent pas'
                        : null,
                  ),
                  const SizedBox(height: 18),
                  PrimaryButton(
                    label: 'Mettre à jour le mot de passe',
                    onPressed: _mettreAJourMotDePasse,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            AppCard(
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.orangeLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: AppColors.orange,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Authentification à deux facteurs',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        Text(
                          'Sécurité renforcée par code SMS',
                          style: TextStyle(fontSize: 11.5, color: AppColors.grey),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _authDeuxFacteurs,
                    activeThumbColor: AppColors.orange,
                    onChanged: (v) => setState(() => _authDeuxFacteurs = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Appareils connectés',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            ..._appareils.map(
              (appareil) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  child: Row(
                    children: [
                      Icon(
                        appareil.nom.contains('iPhone')
                            ? Icons.phone_iphone_rounded
                            : Icons.devices_other_rounded,
                        color: AppColors.grey,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              appareil.nom,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              '${appareil.localisation} · ${appareil.date}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!appareil.actuel)
                        TextButton(
                          onPressed: () => _deconnecterAppareil(appareil),
                          child: const Text('Déconnecter'),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.check_circle, color: Colors.green, size: 18),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
