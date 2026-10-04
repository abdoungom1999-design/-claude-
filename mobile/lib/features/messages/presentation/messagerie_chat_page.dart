import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/onyx_light.dart';
import '../data/chat_service.dart';
import '../data/messages_non_lus.dart';

/// Chat instantané, temps réel, entre le client et un chauffeur —
/// branché sur Firestore (voir [ChatService]) : plus de réponse
/// automatique simulée, chaque message envoyé ou reçu vient
/// directement du flux [ChatService.streamMessages]. Un bouton
/// "Appeler" dans la barre d'app lance l'appel natif vers le vrai
/// numéro de téléphone de l'interlocuteur (récupéré depuis Firestore).
///
/// On n'écrit (et on n'appelle) que pendant la course en cours : une fois
/// la course terminée ou annulée, les règles Firestore refusent l'envoi
/// et la lecture du numéro ; la page le dit clairement.
class MessagerieChatPage extends StatefulWidget {
  const MessagerieChatPage({
    super.key,
    required this.interlocuteurUid,
    required this.interlocuteurNom,
    required this.interlocuteurSousTitre,
    this.chatService,
    this.monUid,
    this.messagesNonLus,
  });

  final String interlocuteurUid;
  final String interlocuteurNom;
  final String interlocuteurSousTitre;

  /// Injectables pour les tests.
  final ChatService? chatService;
  final String? monUid;
  final MessagesNonLus? messagesNonLus;

  @override
  State<MessagerieChatPage> createState() => _MessagerieChatPageState();
}

class _MessagerieChatPageState extends State<MessagerieChatPage> {
  late final ChatService _chatService = widget.chatService ?? ChatService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late final String _moiUid =
      widget.monUid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
  late final String _chatId =
      _chatService.chatIdEntre(_moiUid, widget.interlocuteurUid);

  /// Créé une fois : un nouveau flux à chaque reconstruction relancerait
  /// l'écoute Firestore (et l'indicateur de chargement) à chaque frappe.
  late final Stream<List<ChatMessageFirestore>> _messages =
      _chatService.streamMessages(_chatId);

  String? _telephoneInterlocuteur;
  bool _telephoneCharge = false;

  late final MessagesNonLus _nonLus =
      widget.messagesNonLus ?? MessagesNonLus.instance;

  @override
  void initState() {
    super.initState();
    // Conversation à l'écran : messages lus, ni son ni pastille pendant
    // qu'on la regarde.
    _nonLus.ouvrirConversation(widget.interlocuteurUid);
    _chargerTelephone();
  }

  @override
  void dispose() {
    _nonLus.fermerConversation(widget.interlocuteurUid);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _chargerTelephone() async {
    String? telephone;
    try {
      final profil = await _chatService.chargerProfil(widget.interlocuteurUid);
      telephone = profil?['telephone'] as String?;
    } catch (_) {
      // Course terminée (accès retiré) ou réseau coupé : pas de numéro.
    }
    if (!mounted) return;
    setState(() {
      _telephoneInterlocuteur = telephone;
      _telephoneCharge = true;
    });
  }

  Future<void> _appeler() async {
    final telephone = _telephoneInterlocuteur?.trim();
    if (telephone == null || telephone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Numéro de téléphone indisponible.')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: telephone);
    final lance = await launchUrl(uri);
    if (!lance && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible de lancer l'appel.")),
      );
    }
  }

  Future<void> _envoyer() async {
    final texte = _controller.text.trim();
    if (texte.isEmpty) return;
    _controller.clear();
    try {
      await _chatService.envoyerMessage(
        chatId: _chatId,
        participants: [_moiUid, widget.interlocuteurUid],
        texte: texte,
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      // Le texte tapé n'est pas perdu.
      _controller.text = texte;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'permission-denied'
                ? 'Message non envoyé : on ne peut écrire qu\'à l\'autre partie d\'une course en cours.'
                : 'Message non envoyé. Vérifiez votre connexion.',
          ),
        ),
      );
      return;
    }
    _defilerVersLeBas();
  }

  void _defilerVersLeBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ThemeOnyxLight(
      child: Scaffold(
        backgroundColor: AppColors.fondClair,
        appBar: AppBar(
          backgroundColor: AppColors.fondClairHaut,
          surfaceTintColor: Colors.transparent,
          foregroundColor: AppColors.onyx,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.interlocuteurNom,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: AppColors.onyx),
              ),
              Text(
                widget.interlocuteurSousTitre,
                style: const TextStyle(
                    fontSize: 11.5, color: AppColors.texteDiscret),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.call_rounded, color: AppColors.bleu),
              tooltip: 'Appeler',
              onPressed: _telephoneCharge ? _appeler : null,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: FondOnyxLight(
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: StreamBuilder<List<ChatMessageFirestore>>(
                    stream: _messages,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'Impossible de charger la conversation. Vérifiez votre connexion.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.grey),
                            ),
                          ),
                        );
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.bleu),
                        );
                      }
                      final messages = snapshot.data ?? [];
                      if (messages.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 44,
                                  color: AppColors.texteDiscret,
                                ),
                                SizedBox(height: 14),
                                Text(
                                  'Aucun message',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      color: AppColors.onyx),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Écrivez le premier message.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.texteDiscret),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      _defilerVersLeBas();
                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) => _Bulle(
                            message: messages[index],
                            moi: messages[index].senderId == _moiUid),
                      );
                    },
                  ),
                ),
                _BarreSaisie(controller: _controller, onEnvoyer: _envoyer),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bulle extends StatelessWidget {
  const _Bulle({required this.message, required this.moi});

  final ChatMessageFirestore message;
  final bool moi;

  @override
  Widget build(BuildContext context) {
    // Mes messages : Onyx ; ceux du chauffeur : blanc bordé, ombre très douce.
    return Align(
      alignment: moi ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: moi ? AppColors.onyx : Colors.white,
          border: moi ? null : Border.all(color: AppColors.bordVerre),
          boxShadow: moi
              ? null
              : const [
                  BoxShadow(
                      color: Color(0x0F000000),
                      blurRadius: 10,
                      offset: Offset(0, 3))
                ],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(moi ? 20 : 6),
            bottomRight: Radius.circular(moi ? 6 : 20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.text,
              style: TextStyle(
                  color: moi ? Colors.white : AppColors.onyx,
                  fontSize: 13.5,
                  height: 1.3),
            ),
            const SizedBox(height: 3),
            Text(
              '${message.timestamp.hour.toString().padLeft(2, '0')}:'
              '${message.timestamp.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 10,
                color: moi
                    ? Colors.white.withValues(alpha: 0.65)
                    : AppColors.texteDiscret,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarreSaisie extends StatelessWidget {
  const _BarreSaisie({required this.controller, required this.onEnvoyer});

  final TextEditingController controller;
  final VoidCallback onEnvoyer;

  @override
  Widget build(BuildContext context) {
    return Container(
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
                border: Border.all(color: AppColors.bordVerre),
                borderRadius: BorderRadius.circular(26),
              ),
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onEnvoyer(),
                decoration: const InputDecoration(
                  hintText: 'Écrire un message...',
                  hintStyle:
                      TextStyle(color: AppColors.texteDiscret, fontSize: 13.5),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: const BoxDecoration(
                color: AppColors.orange, shape: BoxShape.circle),
            child: IconButton(
              onPressed: onEnvoyer,
              icon:
                  const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
