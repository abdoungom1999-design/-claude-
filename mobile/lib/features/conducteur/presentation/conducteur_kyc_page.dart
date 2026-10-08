import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/ecran_statut_onyx.dart';
import '../../../core/widgets/onyx_vert.dart';
import '../../auth/data/auth_repository.dart';
import '../data/conducteur_documents_service.dart';

const _documentsRequis = ['permis', 'carteGrise', 'attestationVtc'];

/// Page obligatoire affichée juste après la création du compte
/// Conducteur, avant tout accès au tableau de bord (voir le "Gardien"
/// dans [ConducteurShellPage], qui l'affiche tant que le document
/// Firestore de l'utilisateur n'a pas encore de champ
/// `statutValidation`, c'est-à-dire tant qu'aucun document n'a jamais
/// été envoyé).
///
/// Corrige une faille logique : cette UI ("Mes documents") vivait
/// auparavant dans l'onglet Compte, donc APRÈS connexion — rien
/// n'empêchait un chauffeur non vérifié d'ignorer cette section et
/// d'utiliser l'app normalement. Elle bloque désormais l'accès dès la
/// racine, avant [ConducteurEnAttentePage] puis le tableau de bord.
class ConducteurKYCPage extends StatefulWidget {
  const ConducteurKYCPage({
    super.key,
    required this.onDossierSoumis,
    required this.onDeconnexion,
    this.fluxProfil,
  });

  /// Appelé une fois les 3 documents envoyés et le bouton "Soumettre
  /// mon dossier" pressé : fait passer [ConducteurShellPage] à l'écran
  /// d'attente directement, sans recharger tout le profil.
  final VoidCallback onDossierSoumis;
  final VoidCallback onDeconnexion;

  /// Profil Firestore de l'utilisateur ; `null` : flux réel du compte
  /// connecté. Sert aux tests et aux aperçus, sans projet Firebase.
  final Stream<Map<String, dynamic>?>? fluxProfil;

  @override
  State<ConducteurKYCPage> createState() => _ConducteurKYCPageState();
}

class _ConducteurKYCPageState extends State<ConducteurKYCPage> {
  final _authRepository = AuthRepository();
  final _documentsService = ConducteurDocumentsService();
  final _imagePicker = ImagePicker();
  final Set<String> _enCoursTeleversement = {};

  /// Ouvre la galerie, compresse l'image (voir la note de
  /// [ConducteurDocumentsService]) et l'envoie sous la clé [cle]
  /// ('permis', 'carteGrise' ou 'attestationVtc').
  Future<void> _choisirEtTeleverser(String cle) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final fichier = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 40,
    );
    if (fichier == null || !mounted) return;

    setState(() => _enCoursTeleversement.add(cle));
    try {
      final octets = await fichier.readAsBytes();
      await _documentsService.televerserDocument(uid: uid, cle: cle, octets: octets);
    } on DocumentTropVolumineuxException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cette photo est trop volumineuse. Choisissez-en une plus légère.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Échec de l'envoi. Réessayez.")),
        );
      }
    } finally {
      if (mounted) setState(() => _enCoursTeleversement.remove(cle));
    }
  }

  bool _envoye(String cle, Map<String, dynamic> documents) =>
      (documents[cle] as String?)?.isNotEmpty ?? false;

  @override
  Widget build(BuildContext context) {
    return EcranOnyxVert(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: StreamBuilder<Map<String, dynamic>?>(
            stream: widget.fluxProfil ?? _authRepository.profilUtilisateurStream(),
            builder: (context, snapshot) {
              final documents = (snapshot.data?['documents'] as Map<String, dynamic>?) ?? {};
              final nbEnvoyes = _documentsRequis.where((cle) => _envoye(cle, documents)).length;
              final tousEnvoyes = nbEnvoyes == _documentsRequis.length;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      const Align(alignment: Alignment.centerLeft, child: TuileLogo(taille: 56)),
                      const SizedBox(height: 24),
                      const Text('Complétez votre dossier', style: styleTitreEcran),
                      const SizedBox(height: 10),
                      const Text(
                        'Avant de prendre votre première course, envoyez une photo lisible '
                        "de chacun de ces documents. L'équipe du Groupe Santine les vérifie "
                        "avant d'activer votre compte.",
                        style: TextStyle(fontSize: 13.5, color: AppColors.texteDiscret, height: 1.5),
                      ),
                      const SizedBox(height: 22),
                      _ProgressionDossier(envoyes: nbEnvoyes, total: _documentsRequis.length),
                      const SizedBox(height: 14),
                      AppCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            _LigneDocumentKyc(
                              icon: Icons.badge_outlined,
                              label: 'Permis de conduire',
                              envoye: _envoye('permis', documents),
                              enCours: _enCoursTeleversement.contains('permis'),
                              onTap: () => _choisirEtTeleverser('permis'),
                            ),
                            const _SeparateurKyc(),
                            _LigneDocumentKyc(
                              icon: Icons.description_outlined,
                              label: 'Carte grise',
                              envoye: _envoye('carteGrise', documents),
                              enCours: _enCoursTeleversement.contains('carteGrise'),
                              onTap: () => _choisirEtTeleverser('carteGrise'),
                            ),
                            const _SeparateurKyc(),
                            _LigneDocumentKyc(
                              icon: Icons.shield_outlined,
                              label: 'Attestation VTC',
                              envoye: _envoye('attestationVtc', documents),
                              enCours: _enCoursTeleversement.contains('attestationVtc'),
                              onTap: () => _choisirEtTeleverser('attestationVtc'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      BoutonStatutPrincipal(
                        label: 'Soumettre mon dossier',
                        onPressed: tousEnvoyes ? widget.onDossierSoumis : null,
                      ),
                      const SizedBox(height: 4),
                      Center(child: LienStatut(label: 'Se déconnecter', onPressed: widget.onDeconnexion)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// « 2 documents sur 3 » avec une barre de progression verte.
class _ProgressionDossier extends StatelessWidget {
  const _ProgressionDossier({required this.envoyes, required this.total});

  final int envoyes;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$envoyes document${envoyes > 1 ? 's' : ''} sur $total envoyé${envoyes > 1 ? 's' : ''}',
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.texte),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : envoyes / total,
            minHeight: 6,
            backgroundColor: AppColors.texte.withValues(alpha: 0.10),
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.vert),
          ),
        ),
      ],
    );
  }
}

class _SeparateurKyc extends StatelessWidget {
  const _SeparateurKyc();

  @override
  Widget build(BuildContext context) => const Divider(height: 1, color: AppColors.bordVerre);
}

class _LigneDocumentKyc extends StatelessWidget {
  const _LigneDocumentKyc({
    required this.icon,
    required this.label,
    required this.envoye,
    required this.enCours,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool envoye;
  final bool enCours;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enCours ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.vertTeinte,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: AppColors.vert),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.texte),
              ),
            ),
            if (enCours)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.vert),
              )
            else
              // Envoyé : pastille verte à coche Onyx. À ajouter : pastille de
              // verre à contour vert.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: envoye ? AppColors.vert : AppColors.vertTeinte,
                  borderRadius: BorderRadius.circular(20),
                  border: envoye ? null : Border.all(color: AppColors.vert.withValues(alpha: 0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      envoye ? Icons.check_circle_rounded : Icons.upload_outlined,
                      size: 13,
                      color: envoye ? AppColors.onyx : AppColors.vert,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      envoye ? 'Envoyé' : 'Ajouter',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: envoye ? AppColors.onyx : AppColors.vert,
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
