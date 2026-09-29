import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_fcfa.dart';
import '../../../core/widgets/primary_button.dart';
import '../../courses/data/course_service.dart';
import '../data/support_service.dart';
import 'widgets/conversation_ticket.dart';

/// "Signaler un problème" sur une course de l'historique : choix du
/// motif et premier message, puis conversation en temps réel avec le
/// support Sprint (un seul ticket par course, retrouvé ici ensuite).
class SignalementPage extends StatefulWidget {
  const SignalementPage({
    super.key,
    required this.course,
    required this.clientId,
    this.service,
  });

  final CourseFirestore course;
  final String clientId;

  /// Injectable pour les tests.
  final SupportService? service;

  @override
  State<SignalementPage> createState() => _SignalementPageState();
}

class _SignalementPageState extends State<SignalementPage> {
  late final SupportService _service = widget.service ?? SupportService();
  late final Stream<TicketSupport?> _ticket = _service.streamTicket(widget.course.id);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Signaler un problème')),
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
                    style: TextStyle(color: AppColors.grey),
                  ),
                ),
              );
            }
            if (instantane.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: AppColors.orange));
            }
            final ticket = instantane.data;
            if (ticket == null) {
              return _NouveauSignalement(course: widget.course, clientId: widget.clientId, service: _service);
            }
            return _SuiviSignalement(ticket: ticket, clientId: widget.clientId, service: _service);
          },
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.greyLight, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(
            course.type == 'COLIS' ? Icons.inventory_2_outlined : Icons.two_wheeler_rounded,
            color: AppColors.orange,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${course.adresseDepart} → ${course.adresseArrivee}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} · '
                  '${formaterFcfa(course.prixFcfa)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.grey),
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
  const _NouveauSignalement({required this.course, required this.clientId, required this.service});

  final CourseFirestore course;
  final String clientId;
  final SupportService service;

  @override
  State<_NouveauSignalement> createState() => _NouveauSignalementState();
}

class _NouveauSignalementState extends State<_NouveauSignalement> {
  final _texte = TextEditingController();
  String? _categorie;
  bool _envoi = false;
  String? _erreur;

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
      await widget.service.ouvrirTicket(
        course: widget.course,
        clientId: widget.clientId,
        categorie: categorie,
        texte: texte,
      );
      // La page bascule d'elle-même sur la conversation (flux du ticket).
    } catch (_) {
      if (mounted) setState(() => _erreur = "L'envoi a échoué. Vérifiez votre connexion et réessayez.");
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _RappelCourse(course: widget.course),
        const SizedBox(height: 24),
        const Text('Quel est le problème ?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in CategorieTicket.toutes)
              ChoiceChip(
                label: Text(CategorieTicket.libelle(c)),
                selected: _categorie == c,
                selectedColor: AppColors.orangeLight,
                labelStyle: TextStyle(
                  color: _categorie == c ? AppColors.orangeDark : AppColors.text,
                  fontWeight: _categorie == c ? FontWeight.w700 : FontWeight.w500,
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
          decoration: InputDecoration(
            hintText: 'Racontez-nous ce qui s\'est passé...',
            filled: true,
            fillColor: AppColors.greyLight,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        if (_erreur case final texte?)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(texte, style: const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
          ),
        const SizedBox(height: 8),
        PrimaryButton(label: 'Envoyer au support', onPressed: _envoi ? null : _envoyer, isLoading: _envoi),
        const SizedBox(height: 12),
        const Text(
          'Le support Sprint vous répond ici. Si un remboursement est accordé, il est versé sur votre compte '
          'mobile money.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.grey, height: 1.4),
        ),
      ],
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
          color: ticket.estResolu ? Colors.green.shade50 : AppColors.orangeLight,
          child: Row(
            children: [
              Icon(
                ticket.estResolu ? Icons.check_circle_rounded : Icons.support_agent_rounded,
                size: 20,
                color: ticket.estResolu ? Colors.green.shade700 : AppColors.orangeDark,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${CategorieTicket.libelle(ticket.categorie)} · '
                  '${ticket.estResolu ? 'Résolu' : 'En cours de traitement'}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
