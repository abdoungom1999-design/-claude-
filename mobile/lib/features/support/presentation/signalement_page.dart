import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_fcfa.dart';
import '../../../core/widgets/ecran_statut_onyx.dart';
import '../../../core/widgets/onyx_vert.dart';
import '../../courses/data/course_service.dart';
import '../data/support_service.dart';
import 'widgets/conversation_ticket.dart';

/// Échange avec le support Sprint, en temps réel, sur un ticket :
///  - "Signaler un problème" sur une course de l'historique (un seul ticket
///    par course, retrouvé ici ensuite) ;
///  - [SignalementPage.aide] : demande d'aide hors course depuis le Centre
///    d'aide, pour un client ou un chauffeur (un seul fil par compte, qui
///    reste accessible à un chauffeur suspendu).
/// Choix du motif et premier message, puis conversation.
class SignalementPage extends StatefulWidget {
  const SignalementPage({
    super.key,
    required CourseFirestore this.course,
    required this.clientId,
    this.service,
  }) : role = null;

  /// Demande d'aide hors course de [clientId] ; [role] : `'client'` ou
  /// `'conducteur'`.
  const SignalementPage.aide({
    super.key,
    required this.clientId,
    required String this.role,
    this.service,
  }) : course = null;

  /// Course signalée ; `null` pour une demande d'aide.
  final CourseFirestore? course;
  final String clientId;
  final String? role;

  /// Injectable pour les tests.
  final SupportService? service;

  bool get estAide => course == null;

  @override
  State<SignalementPage> createState() => _SignalementPageState();
}

class _SignalementPageState extends State<SignalementPage> {
  late final SupportService _service = widget.service ?? SupportService();
  late final Stream<TicketSupport?> _ticket = _service.streamTicket(
    widget.estAide ? SupportService.idAide(widget.clientId) : widget.course!.id,
  );

  @override
  Widget build(BuildContext context) {
    return SousPageOnyx(
      child: Scaffold(
        appBar: AppBar(title: Text(widget.estAide ? 'Contacter le support' : 'Signaler un problème')),
        body: SafeArea(
          child: StreamBuilder<TicketSupport?>(
            stream: _ticket,
            builder: (context, instantane) {
              if (instantane.hasError) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Impossible de joindre le support. Vérifiez votre connexion.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.texteDiscret),
                    ),
                  ),
                );
              }
              if (instantane.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: AppColors.vert));
              }
              final ticket = instantane.data;
              if (ticket == null) {
                return _NouveauSignalement(
                  course: widget.course,
                  clientId: widget.clientId,
                  role: widget.role,
                  service: _service,
                );
              }
              return _SuiviSignalement(ticket: ticket, clientId: widget.clientId, service: _service);
            },
          ),
        ),
      ),
    );
  }
}

class _RappelCourse extends StatelessWidget {
  const _RappelCourse({required this.course});

  final CourseFirestore course;

  @override
  Widget build(BuildContext context) {
    final d = course.timestamp;
    return CarteVerre(
      rayon: 20,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.vertTeinte, borderRadius: BorderRadius.circular(12)),
            child: Icon(
              course.type == 'COLIS' ? Icons.inventory_2_outlined : Icons.two_wheeler_rounded,
              color: AppColors.vert,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${course.adresseDepartPourLeClient} → ${course.adresseArrivee}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.texte),
                ),
                const SizedBox(height: 2),
                Text(
                  '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} · '
                  '${formaterFcfa(course.prixFcfa)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.texteDiscret),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NouveauSignalement extends StatefulWidget {
  const _NouveauSignalement({
    required this.course,
    required this.clientId,
    required this.role,
    required this.service,
  });

  final CourseFirestore? course;
  final String clientId;
  final String? role;
  final SupportService service;

  @override
  State<_NouveauSignalement> createState() => _NouveauSignalementState();
}

class _NouveauSignalementState extends State<_NouveauSignalement> {
  final _texte = TextEditingController();
  String? _categorie;
  bool _envoi = false;
  String? _erreur;

  bool get _estAide => widget.course == null;

  @override
  void dispose() {
    _texte.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    final texte = _texte.text.trim();
    final categorie = _categorie;
    if (categorie == null) {
      setState(() => _erreur = 'Choisissez le type de problème.');
      return;
    }
    if (texte.length < 5) {
      setState(() => _erreur = 'Décrivez le problème en quelques mots.');
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      if (_estAide) {
        await widget.service.ouvrirDemandeAide(
          uid: widget.clientId,
          role: widget.role!,
          categorie: categorie,
          texte: texte,
        );
      } else {
        await widget.service.ouvrirTicket(
          course: widget.course!,
          clientId: widget.clientId,
          categorie: categorie,
          texte: texte,
        );
      }
      // La page bascule d'elle-même sur la conversation (flux du ticket).
    } catch (_) {
      if (mounted) setState(() => _erreur = "L'envoi a échoué. Vérifiez votre connexion et réessayez.");
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = _estAide ? CategorieTicket.pourAide : CategorieTicket.toutes;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            if (widget.course case final course?) ...[
              _RappelCourse(course: course),
              const SizedBox(height: 24),
            ],
            const Text('Quel est le problème ?', style: styleTitreSection),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in categories)
                  ChoiceChip(
                    label: Text(CategorieTicket.libelle(c)),
                    selected: _categorie == c,
                    showCheckmark: false,
                    selectedColor: AppColors.vert,
                    backgroundColor: AppColors.verre,
                    side: BorderSide(color: _categorie == c ? AppColors.vert : AppColors.bord),
                    shape: const StadiumBorder(),
                    labelStyle: TextStyle(
                      color: _categorie == c ? AppColors.onyx : AppColors.texte,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    onSelected: (_) => setState(() => _categorie = c),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _texte,
              minLines: 4,
              maxLines: 8,
              maxLength: SupportService.longueurMaxMessage,
              style: const TextStyle(color: AppColors.texte, fontSize: 14.5),
              decoration: InputDecoration(
                hintText: "Racontez-nous ce qui s'est passé...",
                hintStyle: const TextStyle(color: AppColors.texteDiscret),
                filled: true,
                fillColor: AppColors.verre,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: AppColors.bord),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: AppColors.vert, width: 1.6),
                ),
              ),
            ),
            if (_erreur case final texte?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(texte, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
              ),
            const SizedBox(height: 8),
            BoutonStatutPrincipal(label: 'Envoyer au support', onPressed: _envoyer, enCours: _envoi),
            const SizedBox(height: 14),
            Text(
              _estAide
                  ? 'Le support Sprint vous répond ici, dans cette conversation.'
                  : 'Le support Sprint vous répond ici. Si un remboursement est accordé, il est versé sur votre '
                      'compte mobile money.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.texteDiscret, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuiviSignalement extends StatefulWidget {
  const _SuiviSignalement({required this.ticket, required this.clientId, required this.service});

  final TicketSupport ticket;
  final String clientId;
  final SupportService service;

  @override
  State<_SuiviSignalement> createState() => _SuiviSignalementState();
}

class _SuiviSignalementState extends State<_SuiviSignalement> {
  late final Stream<List<MessageTicket>> _messages = widget.service.streamMessages(widget.ticket.courseId);

  @override
  void initState() {
    super.initState();
    _marquerLu();
  }

  @override
  void didUpdateWidget(covariant _SuiviSignalement oldWidget) {
    super.didUpdateWidget(oldWidget);
    _marquerLu();
  }

  /// Réponse du support affichée à l'écran : lue.
  void _marquerLu() {
    if (!widget.ticket.nonLuClient) return;
    widget.service.marquerLuParClient(widget.ticket.courseId).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final ticket = widget.ticket;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          color: ticket.estResolu ? AppColors.texte.withValues(alpha: 0.06) : AppColors.vert.withValues(alpha: 0.10),
          child: Row(
            children: [
              Icon(
                ticket.estResolu ? Icons.check_circle_rounded : Icons.support_agent_rounded,
                size: 20,
                color: ticket.estResolu ? AppColors.texte : AppColors.vert,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${CategorieTicket.libelle(ticket.categorie)} · '
                  '${ticket.estResolu ? 'Résolu' : 'En cours de traitement'}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.texte),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ConversationTicket(
            messages: _messages,
            moiRole: AuteurMessage.client,
            indication: ticket.estResolu ? 'Ce signalement est résolu. Écrire un message le rouvrira.' : null,
            onEnvoyer: (texte) => widget.service.envoyerMessageClient(ticket.courseId, widget.clientId, texte),
          ),
        ),
      ],
    );
  }
}
