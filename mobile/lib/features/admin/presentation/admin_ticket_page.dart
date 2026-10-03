import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/models/statut_compte.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/onyx_light.dart';
import '../../../core/utils/flux_partage.dart';
import '../../../core/utils/format_fcfa.dart';
import '../../courses/data/course_service.dart';
import '../../finances/data/comptabilite.dart';
import '../../messages/data/chat_service.dart';
import '../../support/data/support_service.dart';
import '../../support/presentation/widgets/conversation_ticket.dart';
import '../data/admin_kyc_service.dart';
import 'widgets/dialogue_sanction.dart';

/// Profil public (nom, téléphone) d'un utilisateur, pour la fiche.
typedef ChargeurProfil = Future<Map<String, dynamic>?> Function(String uid);

/// Traitement d'un ticket par l'Admin : fiche de la course (trajet, prix,
/// paiement, client, chauffeur), actions (rembourser, suspendre le
/// chauffeur, clore / rouvrir) et conversation avec le client.
class AdminTicketPage extends StatefulWidget {
  const AdminTicketPage({
    super.key,
    required this.courseId,
    this.adminId,
    this.supportService,
    this.courseService,
    this.kycService,
    this.chargerProfil,
  });

  final String courseId;

  /// Injectables pour les tests.
  final String? adminId;
  final SupportService? supportService;
  final CourseService? courseService;
  final AdminKycService? kycService;
  final ChargeurProfil? chargerProfil;

  @override
  State<AdminTicketPage> createState() => _AdminTicketPageState();
}

class _AdminTicketPageState extends State<AdminTicketPage> {
  late final SupportService _support = widget.supportService ?? SupportService();
  late final CourseService _courses = widget.courseService ?? CourseService();
  late final AdminKycService _kyc = widget.kycService ?? AdminKycService();
  late final ChargeurProfil _profil = widget.chargerProfil ?? ChatService().chargerProfil;
  late final String _adminId = widget.adminId ?? FirebaseAuth.instance.currentUser?.uid ?? '';

  // Flux Firestore partagés : plusieurs zones de la page les affichent.
  late final FluxPartage<TicketSupport?> _ticket = FluxPartage(_support.streamTicket(widget.courseId));
  bool get _estAide => widget.courseId.startsWith('aide_');
  late final FluxPartage<CourseFirestore?>? _course =
      _estAide ? null : FluxPartage(_courses.streamCourse(widget.courseId));
  late final Stream<List<MessageTicket>> _messages = _support.streamMessages(widget.courseId);
  FluxPartage<CommandePaiement?>? _commande;
  String? _commandeId;
  FluxPartage<ConducteurKycAdmin?>? _chauffeur;
  String? _chauffeurId;
  bool _action = false;
  bool _luMarque = false;

  void _suivreCommande(String? commandeId) {
    if (commandeId == _commandeId) return;
    _commandeId = commandeId;
    _commande?.fermer();
    _commande = commandeId == null ? null : FluxPartage(_courses.streamCommande(commandeId));
  }

  void _suivreChauffeur(String? chauffeurId) {
    if (chauffeurId == _chauffeurId) return;
    _chauffeurId = chauffeurId;
    _chauffeur?.fermer();
    _chauffeur = chauffeurId == null ? null : FluxPartage(_kyc.streamConducteur(chauffeurId));
  }

  @override
  void dispose() {
    _ticket.fermer();
    _course?.fermer();
    _commande?.fermer();
    _chauffeur?.fermer();
    super.dispose();
  }

  void _marquerLu(TicketSupport ticket) {
    if (_luMarque || !ticket.nonLuAdmin) return;
    _luMarque = true;
    _support.marquerLuParAdmin(ticket.courseId).catchError((_) {});
  }

  Future<void> _executer(Future<String?> Function() action) async {
    setState(() => _action = true);
    try {
      final message = await action();
      if (message != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("L'opération a échoué. Réessayez.")),
        );
      }
    } finally {
      if (mounted) setState(() => _action = false);
    }
  }

  Future<void> _rembourser(CourseFirestore course) async {
    final motif = await showDialog<String>(
      context: context,
      builder: (_) => _DialogueRemboursement(
        montantFcfa: course.prixFcfa,
        partChauffeurFcfa: LigneCourse.partChauffeurDe(course),
      ),
    );
    if (motif == null) return;
    await _executer(() async {
      final r = await _support.rembourser(course.id, motif);
      if (!r.rembourse) return 'Le fournisseur de paiement a refusé le remboursement : réessayez plus tard.';
      final part = r.partChauffeurRetireeFcfa > 0
          ? ' Part du chauffeur retirée : ${formaterFcfa(r.partChauffeurRetireeFcfa)}.'
          : '';
      return 'Course remboursée : ${formaterFcfa(r.montantFcfa)}. Le client est prévenu dans le ticket.$part';
    });
  }

  Future<void> _suspendre(ConducteurKycAdmin chauffeur) async {
    final motif = await demanderMotifSanction(context, nom: chauffeur.nom, statut: StatutCompte.suspendu);
    if (motif == null) return;
    await _executer(() async {
      final s = await _kyc.definirStatutCompte(chauffeur.id, StatutCompte.suspendu, motif: motif);
      return '${chauffeur.nom} est suspendu.'
          '${s.coursesAnnulees > 0 ? ' ${s.coursesAnnulees} course(s) en cours annulée(s) et remboursée(s).' : ''}';
    });
  }

  Future<void> _reactiver(ConducteurKycAdmin chauffeur) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Réactiver ${chauffeur.nom} ?'),
        content: const Text(
          'Le chauffeur retrouve l\'accès à son compte : il repart sans se reconnecter et peut de nouveau '
          'prendre des courses. L\'action est tracée dans le journal.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
            child: const Text('Réactiver'),
          ),
        ],
      ),
    );
    if (confirme != true) return;
    await _executer(() async {
      await _kyc.definirStatutCompte(chauffeur.id, StatutCompte.actif);
      return '${chauffeur.nom} est réactivé.';
    });
  }

  Future<void> _changerStatut(TicketSupport ticket) async {
    final statut = ticket.estResolu ? StatutTicket.ouvert : StatutTicket.resolu;
    await _executer(() async {
      await _support.definirStatut(ticket.courseId, statut);
      return statut == StatutTicket.resolu ? 'Ticket marqué résolu.' : 'Ticket rouvert.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TicketSupport?>(
      stream: _ticket.flux,
      builder: (context, instantaneTicket) {
        final ticket = instantaneTicket.data;
        if (ticket != null) _marquerLu(ticket);
        return EcranOnyxLight(
          flou: false,
          child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: AppColors.fondClairHaut,
            surfaceTintColor: Colors.transparent,
            foregroundColor: AppColors.onyx,
            title: Text(
              ticket == null
                  ? 'Ticket'
                  : ticket.estDemandeAide
                      ? "Demande d'aide · ${CategorieTicket.libelle(ticket.categorie)}"
                      : CategorieTicket.libelle(ticket.categorie),
              style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.onyx),
            ),
            actions: [
              if (ticket != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: TextButton.icon(
                    onPressed: _action ? null : () => _changerStatut(ticket),
                    icon: Icon(ticket.estResolu ? Icons.replay_rounded : Icons.check_circle_outline_rounded),
                    label: Text(ticket.estResolu ? 'Rouvrir' : 'Marquer résolu'),
                  ),
                ),
            ],
          ),
          body: ticket == null
              ? Center(
                  child: instantaneTicket.connectionState == ConnectionState.waiting
                      ? const CircularProgressIndicator(color: AppColors.orange)
                      : const Text('Ticket introuvable.', style: TextStyle(color: AppColors.grey)),
                )
              : _corps(ticket),
          ),
        );
      },
    );
  }

  /// Grand écran : fiche à gauche, conversation à droite. Téléphone :
  /// fiche au-dessus, conversation en dessous.
  Widget _corps(TicketSupport ticket) {
    final taille = MediaQuery.sizeOf(context);
    final fiche = _fiche(ticket);
    final conversation = ConversationTicket(
      messages: _messages,
      moiRole: AuteurMessage.admin,
      onEnvoyer: (texte) => _support.envoyerMessageAdmin(ticket.courseId, _adminId, texte),
    );
    if (taille.width >= 900) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 400, child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: fiche)),
          const VerticalDivider(width: 1, color: AppColors.greyBorder),
          Expanded(child: conversation),
        ],
      );
    }
    return Column(
      children: [
        Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: fiche)),
        const Divider(height: 1, color: AppColors.greyBorder),
        SizedBox(height: taille.height * 0.5, child: conversation),
      ],
    );
  }

  /// Demande d'aide hors course : qui écrit, et l'état de son compte pour un
  /// chauffeur (avec la réactivation d'une suspension).
  Widget _ficheDemandeur(TicketSupport ticket) {
    final chauffeur = ticket.demandeur == 'conducteur';
    if (chauffeur) _suivreChauffeur(ticket.clientId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Titre("Demande d'aide"),
        _Info('Demandeur', chauffeur ? 'Chauffeur' : 'Client'),
        _Personne(uid: ticket.clientId, chargerProfil: _profil),
        if (chauffeur && _chauffeur != null) ...[
          const SizedBox(height: 8),
          StreamBuilder<ConducteurKycAdmin?>(
            stream: _chauffeur!.flux,
            builder: (context, c) {
              final compte = c.data;
              if (compte == null) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Info(
                    'Compte',
                    switch (compte.statutCompte) {
                      StatutCompte.suspendu => 'Suspendu',
                      StatutCompte.banni => 'Désactivé définitivement',
                      _ => 'Actif',
                    },
                  ),
                  if (compte.statutCompte == StatutCompte.suspendu) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _action ? null : () => _reactiver(compte),
                      icon: const Icon(Icons.play_circle_outline_rounded),
                      label: const Text('Réactiver le compte'),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.onyx),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'Le demandeur voit votre réponse dans son application, y compris un chauffeur suspendu.',
          style: TextStyle(fontSize: 12.5, color: AppColors.texteDiscret, height: 1.4),
        ),
      ],
    );
  }

  Widget _fiche(TicketSupport ticket) {
    if (ticket.estDemandeAide) return _ficheDemandeur(ticket);
    return StreamBuilder<CourseFirestore?>(
      stream: _course!.flux,
      builder: (context, instantane) {
        final course = instantane.data;
        if (course == null) {
          return instantane.connectionState == ConnectionState.waiting
              ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
              : const Text('Course introuvable.', style: TextStyle(color: AppColors.grey));
        }
        _suivreCommande(course.commandeId);
        _suivreChauffeur(course.chauffeurId);
        final d = course.timestamp;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Titre('Course'),
            _Info('Date', '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
                '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'),
            _Info('Type', course.type == 'COLIS' ? 'Colis' : 'Passager (moto)'),
            _Info('Départ', course.adresseDepart),
            _Info('Arrivée', course.adresseArrivee),
            _Info('Statut', course.libelleStatut +
                (course.annuleePar != null ? ' (par ${course.annuleePar})' : '')),
            _Info('Prix', '${formaterFcfa(course.prixFcfa)} · ${course.libellePaiement}'),
            if (_commande case final commande?)
              StreamBuilder<CommandePaiement?>(
                stream: commande.flux,
                builder: (context, c) => _Info('Paiement', _libelleCommande(c.data?.statut)),
              ),
            const SizedBox(height: 16),
            const _Titre('Client'),
            _Personne(uid: course.clientId, chargerProfil: _profil),
            const SizedBox(height: 16),
            const _Titre('Chauffeur'),
            if (_chauffeur == null)
              const Text('Aucun chauffeur attribué.', style: TextStyle(fontSize: 13, color: AppColors.grey))
            else
              StreamBuilder<ConducteurKycAdmin?>(
                stream: _chauffeur!.flux,
                builder: (context, c) {
                  final chauffeur = c.data;
                  if (chauffeur == null) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Info('Nom', chauffeur.nom),
                      _Info('Téléphone', chauffeur.telephone),
                      _Info('Compte', chauffeur.estBloque ? 'Bloqué (${chauffeur.statutCompte})' : 'Actif'),
                      const SizedBox(height: 8),
                      if (!chauffeur.estBloque)
                        OutlinedButton.icon(
                          onPressed: _action ? null : () => _suspendre(chauffeur),
                          icon: const Icon(Icons.block_rounded, color: Colors.redAccent),
                          label: const Text('Suspendre le chauffeur'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                          ),
                        ),
                    ],
                  );
                },
              ),
            const SizedBox(height: 20),
            const _Titre('Remboursement'),
            _boutonRemboursement(course),
          ],
        );
      },
    );
  }

  Widget _boutonRemboursement(CourseFirestore course) {
    if (course.rembourseeLe != null) {
      return const Text('Course déjà remboursée.', style: TextStyle(fontSize: 13, color: AppColors.onyx));
    }
    if (course.commandeId == null) {
      return const Text(
        'Course payée avant le paiement par le serveur : remboursement à faire à la main.',
        style: TextStyle(fontSize: 12.5, color: AppColors.grey),
      );
    }
    if (course.estActive) {
      return const Text(
        'Course en cours : remboursable une fois terminée ou annulée.',
        style: TextStyle(fontSize: 12.5, color: AppColors.grey),
      );
    }
    return StreamBuilder<CommandePaiement?>(
      stream: _commande?.flux,
      builder: (context, c) {
        if (c.data?.statut == 'remboursee') {
          return const Text('Client déjà remboursé (annulation).', style: TextStyle(fontSize: 13, color: AppColors.onyx));
        }
        return FilledButton.icon(
          onPressed: _action ? null : () => _rembourser(course),
          icon: const Icon(Icons.undo_rounded),
          label: Text('Rembourser ${formaterFcfa(course.prixFcfa)}'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
        );
      },
    );
  }
}

String _libelleCommande(String? statut) => switch (statut) {
      'payee' => 'Payée',
      'remboursee' => 'Remboursée',
      'remboursement_echoue' => 'Remboursement échoué (à relancer)',
      'anomalie' => 'Anomalie de paiement',
      null => '…',
      _ => statut,
    };

class _Titre extends StatelessWidget {
  const _Titre(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(texte, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      );
}

class _Info extends StatelessWidget {
  const _Info(this.libelle, this.valeur);

  final String libelle;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(libelle, style: const TextStyle(fontSize: 12.5, color: AppColors.grey))),
          Expanded(child: Text(valeur, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

class _Personne extends StatefulWidget {
  const _Personne({required this.uid, required this.chargerProfil});

  final String uid;
  final ChargeurProfil chargerProfil;

  @override
  State<_Personne> createState() => _PersonneState();
}

class _PersonneState extends State<_Personne> {
  late final Future<Map<String, dynamic>?> _profil = widget.chargerProfil(widget.uid).catchError((_) => null);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _profil,
      builder: (context, p) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Info('Nom', (p.data?['nom'] as String?) ?? '…'),
          _Info('Téléphone', (p.data?['telephone'] as String?) ?? '…'),
        ],
      ),
    );
  }
}

class _DialogueRemboursement extends StatefulWidget {
  const _DialogueRemboursement({required this.montantFcfa, required this.partChauffeurFcfa});

  final int montantFcfa;

  /// Part (85 %) que le chauffeur ne touchera pas (0 : course annulée).
  final int partChauffeurFcfa;

  @override
  State<_DialogueRemboursement> createState() => _DialogueRemboursementState();
}

class _DialogueRemboursementState extends State<_DialogueRemboursement> {
  final _motif = TextEditingController();
  bool _manquant = false;

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Rembourser ${formaterFcfa(widget.montantFcfa)} ?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Remboursement intégral sur le compte mobile money du client, par le fournisseur de paiement. '
              'Le client est prévenu dans le ticket.',
            ),
            if (widget.partChauffeurFcfa > 0) ...[
              const SizedBox(height: 10),
              Text(
                'Le chauffeur n\'est pas payé pour cette course : sa part (${formaterFcfa(widget.partChauffeurFcfa)}) '
                'est retirée de ce que Sprint lui doit, ou déduite de ses prochains gains si elle lui a déjà été versée.',
                style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _motif,
              maxLength: 300,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Motif (gardé dans le journal)',
                errorText: _manquant ? 'Indiquez le motif.' : null,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            final motif = _motif.text.trim();
            if (motif.isEmpty) {
              setState(() => _manquant = true);
              return;
            }
            Navigator.of(context).pop(motif);
          },
          style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
          child: const Text('Rembourser'),
        ),
      ],
    );
  }
}
