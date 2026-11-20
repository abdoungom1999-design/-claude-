
import 'package:file_selector/file_selector.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/ecran_statut_onyx.dart';
import '../../../core/widgets/onyx_vert.dart';
import '../../auth/data/auth_repository.dart';
import '../data/conducteur_documents_service.dart';

/// Les deux pièces demandées à un nouveau chauffeur. Les anciennes clés
/// (`permis`, `attestationVtc`) ne sont plus demandées mais restent lisibles
/// dans les dossiers déjà envoyés.
const documentsKycRequis = ['carteIdentite', 'carteGrise'];

/// Choix d'une pièce : photo (appareil photo ou galerie, compressée par le
/// téléphone) ou fichier (PDF, ou image prise dans les fichiers). Renvoie les
/// octets, ou `null` si la personne annule.
typedef ChoisirPiece = Future<Uint8List?> Function(BuildContext context);

/// Photo : redimensionnée et compressée par le téléphone AVANT l'envoi (1600 px,
/// qualité 75 : lisible pour une carte d'identité, en général moins de 700 Ko,
/// donc rapide sur 4G). Le sélecteur de photos convertit lui-même les HEIC
/// de l'iPhone en JPEG.
Future<Uint8List?> choisirPieceReelle(BuildContext context) async {
  final source = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.carte,
    builder: (contexte) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('source-camera'),
            leading: const Icon(Icons.photo_camera_outlined, color: AppColors.vert),
            title: const Text('Prendre une photo'),
            onTap: () => Navigator.of(contexte).pop('camera'),
          ),
          ListTile(
            key: const ValueKey('source-galerie'),
            leading: const Icon(Icons.photo_library_outlined, color: AppColors.vert),
            title: const Text('Choisir une photo'),
            onTap: () => Navigator.of(contexte).pop('galerie'),
          ),
          ListTile(
            key: const ValueKey('source-fichier'),
            leading: const Icon(Icons.attach_file_rounded, color: AppColors.vert),
            title: const Text('Choisir un fichier (PDF ou image)'),
            onTap: () => Navigator.of(contexte).pop('fichier'),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  if (source == 'fichier') {
    final fichier = await openFile(acceptedTypeGroups: const [
      XTypeGroup(
        label: 'PDF ou image',
        extensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
        mimeTypes: ['application/pdf', 'image/jpeg', 'image/png', 'image/webp'],
        uniformTypeIdentifiers: ['com.adobe.pdf', 'public.jpeg', 'public.png', 'org.webmproject.webp'],
      ),
    ]);
    return fichier?.readAsBytes();
  }
  final photo = await ImagePicker().pickImage(
    source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 1600,
    imageQuality: 75,
  );
  return photo?.readAsBytes();
}

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
    this.choisirPiece,
    this.service,
    this.uid,
  });

  /// Appelé une fois les 2 documents envoyés et le bouton "Soumettre
  /// mon dossier" pressé : fait passer [ConducteurShellPage] à l'écran
  /// d'attente directement, sans recharger tout le profil.
  final VoidCallback onDossierSoumis;
  final VoidCallback onDeconnexion;

  /// Profil Firestore de l'utilisateur ; `null` : flux réel du compte
  /// connecté. Sert aux tests et aux aperçus, sans projet Firebase.
  final Stream<Map<String, dynamic>?>? fluxProfil;

  /// Injectables pour les tests : choix de la pièce, envoi, identifiant du compte.
  final ChoisirPiece? choisirPiece;
  final ConducteurDocumentsService? service;
  final String? uid;

  @override
  State<ConducteurKYCPage> createState() => _ConducteurKYCPageState();
}

class _ConducteurKYCPageState extends State<ConducteurKYCPage> {
  final _authRepository = AuthRepository();
  late final ConducteurDocumentsService _documentsService = widget.service ?? ConducteurDocumentsService();
  final Set<String> _enCoursTeleversement = {};

  void _annoncer(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Choisit la pièce (photo ou fichier) puis l'envoie sous la clé [cle]
  /// ('carteIdentite' ou 'carteGrise'). Plus d'échec muet : un refus, un format
  /// non pris en charge ou un incident technique est dit clairement, avec le
  /// code précis de la cause quand il est technique.
  Future<void> _choisirEtTeleverser(String cle) async {
    final uid = widget.uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    Uint8List? octets;
    try {
      octets = await (widget.choisirPiece ?? choisirPieceReelle)(context);
    } on Object catch (e) {
      final code = e is PlatformException ? e.code : e.runtimeType.toString();
      _annoncer(messageErreurEnvoi(EchecEnvoiPieceException('selection/$code', cause: e)));
      return;
    }
    if (octets == null || !mounted) return;

    setState(() => _enCoursTeleversement.add(cle));
    try {
      await _documentsService.televerserDocument(uid: uid, cle: cle, octets: octets);
    } on Object catch (e) {
      _annoncer(messageErreurEnvoi(e));
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
              final nbEnvoyes = documentsKycRequis.where((cle) => _envoye(cle, documents)).length;
              final tousEnvoyes = nbEnvoyes == documentsKycRequis.length;

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
                        "ou un PDF de chacun de ces documents. L'équipe du Groupe Santine les "
                        "vérifie avant d'activer votre compte.",
                        style: TextStyle(fontSize: 13.5, color: AppColors.texteDiscret, height: 1.5),
                      ),
                      const SizedBox(height: 22),
                      _ProgressionDossier(envoyes: nbEnvoyes, total: documentsKycRequis.length),
                      const SizedBox(height: 14),
                      AppCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            _LigneDocumentKyc(
                              icon: Icons.badge_outlined,
                              label: "Carte d'identité",
                              envoye: _envoye('carteIdentite', documents),
                              enCours: _enCoursTeleversement.contains('carteIdentite'),
                              onTap: () => _choisirEtTeleverser('carteIdentite'),
                            ),
                            const _SeparateurKyc(),
                            _LigneDocumentKyc(
                              icon: Icons.description_outlined,
                              label: 'Carte grise',
                              envoye: _envoye('carteGrise', documents),
                              enCours: _enCoursTeleversement.contains('carteGrise'),
                              onTap: () => _choisirEtTeleverser('carteGrise'),
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
