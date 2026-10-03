import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/support_service.dart';

/// Conversation d'un ticket support, côté client ou Admin ([moiRole]) :
/// mes messages à droite, ceux de l'autre à gauche (avec son nom), les
/// messages automatiques du serveur au centre. À placer dans un parent
/// de hauteur bornée (Expanded, SizedBox).
class ConversationTicket extends StatefulWidget {
  const ConversationTicket({
    super.key,
    required this.messages,
    required this.moiRole,
    required this.onEnvoyer,
    this.indication,
  });

  final Stream<List<MessageTicket>> messages;

  /// [AuteurMessage.client] ou [AuteurMessage.admin].
  final String moiRole;

  /// Envoie le message ; une erreur est affichée et le texte conservé.
  final Future<void> Function(String texte) onEnvoyer;

  /// Texte d'aide au-dessus de la saisie (ex. ticket résolu).
  final String? indication;

  @override
  State<ConversationTicket> createState() => _ConversationTicketState();
}

class _ConversationTicketState extends State<ConversationTicket> {
  late final Stream<List<MessageTicket>> _messages = widget.messages;
  final _saisie = TextEditingController();
  final _defilement = ScrollController();
  bool _envoi = false;

  @override
  void dispose() {
    _saisie.dispose();
    _defilement.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    final texte = _saisie.text.trim();
    if (texte.isEmpty || _envoi) return;
    if (texte.length > SupportService.longueurMaxMessage) {
      _erreur('Message trop long (${SupportService.longueurMaxMessage} caractères au plus).');
      return;
    }
    setState(() => _envoi = true);
    try {
      await widget.onEnvoyer(texte);
      _saisie.clear();
    } catch (_) {
      _erreur("Le message n'a pas pu être envoyé. Vérifiez votre connexion.");
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  void _erreur(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _allerEnBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_defilement.hasClients) _defilement.jumpTo(_defilement.position.maxScrollExtent);
    });
  }

  String get _nomAutre => widget.moiRole == AuteurMessage.admin ? 'Client' : 'Support Sprint';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<MessageTicket>>(
            stream: _messages,
            builder: (context, instantane) {
              if (instantane.hasError) {
                return const Center(
                  child: Text('Impossible de charger la conversation.', style: TextStyle(color: AppColors.texteDiscret)),
                );
              }
              if (!instantane.hasData) {
                return const Center(child: CircularProgressIndicator(color: AppColors.orange));
              }
              final messages = instantane.data!;
              _allerEnBas();
              return ListView.builder(
                controller: _defilement,
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                itemBuilder: (context, i) {
                  final m = messages[i];
                  if (m.auteurRole == AuteurMessage.systeme) return _MessageSysteme(message: m);
                  return _Bulle(
                    message: m,
                    moi: m.auteurRole == widget.moiRole,
                    nomAutre: _nomAutre,
                  );
                },
              );
            },
          ),
        ),
        if (widget.indication case final texte?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(texte, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.texteDiscret)),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: const BoxDecoration(
            color: AppColors.fondBarre,
            border: Border(top: BorderSide(color: AppColors.bordVerre)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.bordVerre),
                  ),
                  child: TextField(
                    controller: _saisie,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _envoyer(),
                    decoration: const InputDecoration(
                      hintText: 'Écrire un message...',
                      hintStyle: TextStyle(color: AppColors.texteDiscret, fontSize: 13.5),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: const BoxDecoration(color: AppColors.orange, shape: BoxShape.circle),
                child: IconButton(
                  tooltip: 'Envoyer',
                  onPressed: _envoi ? null : _envoyer,
                  icon: _envoi
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _heure(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _Bulle extends StatelessWidget {
  const _Bulle({required this.message, required this.moi, required this.nomAutre});

  final MessageTicket message;
  final bool moi;
  final String nomAutre;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: moi ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: moi ? AppColors.orange : Colors.white,
            border: moi ? null : Border.all(color: AppColors.bordVerre),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(moi ? 16 : 4),
              bottomRight: Radius.circular(moi ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!moi)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    nomAutre,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.orange),
                  ),
                ),
              Text(message.texte, style: TextStyle(color: moi ? Colors.white : AppColors.onyx, fontSize: 13.5)),
              const SizedBox(height: 3),
              Text(
                _heure(message.creeLe),
                style: TextStyle(fontSize: 10, color: moi ? Colors.white.withValues(alpha: 0.8) : AppColors.texteDiscret),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageSysteme extends StatelessWidget {
  const _MessageSysteme({required this.message});

  final MessageTicket message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 440),
        decoration: BoxDecoration(
          color: AppColors.onyx.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.bordVerre),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_rounded, size: 16, color: AppColors.orange),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message.texte,
                style: const TextStyle(fontSize: 12.5, color: AppColors.onyx, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
