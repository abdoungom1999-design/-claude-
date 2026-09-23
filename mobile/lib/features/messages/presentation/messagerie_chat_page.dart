import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../data/chat_service.dart';

/// Chat instantané, temps réel, entre le client et un chauffeur —
/// branché sur Firestore (voir [ChatService]) : plus de réponse
/// automatique simulée, chaque message envoyé ou reçu vient
/// directement du flux [ChatService.streamMessages]. Un bouton
/// "Appeler" dans la barre d'app lance l'appel natif vers le vrai
/// numéro de téléphone de l'interlocuteur (récupéré depuis Firestore).
class MessagerieChatPage extends StatefulWidget {
  const MessagerieChatPage({
    super.key,
    required this.interlocuteurUid,
    required this.interlocuteurNom,
    required this.interlocuteurSousTitre,
  });

  final String interlocuteurUid;
  final String interlocuteurNom;
  final String interlocuteurSousTitre;

  @override
  State<MessagerieChatPage> createState() => _MessagerieChatPageState();
}

class _MessagerieChatPageState extends State<MessagerieChatPage> {
  final _chatService = ChatService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late final String _moiUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late final String _chatId = _chatService.chatIdEntre(_moiUid, widget.interlocuteurUid);

  String? _telephoneInterlocuteur;
  bool _telephoneCharge = false;

  @override
  void initState() {
    super.initState();
    _chargerTelephone();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _chargerTelephone() async {
    final profil = await _chatService.chargerProfil(widget.interlocuteurUid);
    if (!mounted) return;
    setState(() {
      _telephoneInterlocuteur = profil?['telephone'] as String?;
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
    await _chatService.envoyerMessage(
      chatId: _chatId,
      participants: [_moiUid, widget.interlocuteurUid],
      texte: texte,
    );
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.interlocuteurNom, style: const TextStyle(fontSize: 16)),
            Text(
              widget.interlocuteurSousTitre,
              style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_rounded, color: AppColors.orange),
            tooltip: 'Appeler',
            onPressed: _telephoneCharge ? _appeler : null,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<ChatMessageFirestore>>(
                stream: _chatService.streamMessages(_chatId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppColors.orange),
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
                              color: AppColors.greyBorder,
                            ),
                            SizedBox(height: 14),
                            Text(
                              'Aucun message',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Écrivez le premier message.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12.5, color: AppColors.grey),
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
                    itemBuilder: (context, index) =>
                        _Bulle(message: messages[index], moi: messages[index].senderId == _moiUid),
                  );
                },
              ),
            ),
            _BarreSaisie(controller: _controller, onEnvoyer: _envoyer),
          ],
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
    return Align(
      alignment: moi ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          gradient: moi
              ? const LinearGradient(
                  colors: [AppColors.orange, AppColors.orangeDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: moi ? null : AppColors.greyLight,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(moi ? 16 : 4),
            bottomRight: Radius.circular(moi ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.text,
              style: TextStyle(color: moi ? Colors.white : AppColors.text, fontSize: 13.5),
            ),
            const SizedBox(height: 3),
            Text(
              '${message.timestamp.hour.toString().padLeft(2, '0')}:'
              '${message.timestamp.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 10,
                color: moi ? Colors.white.withValues(alpha: 0.75) : AppColors.grey,
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
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.greyBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.greyLight,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onEnvoyer(),
                decoration: const InputDecoration(
                  hintText: 'Écrire un message...',
                  hintStyle: TextStyle(color: AppColors.grey, fontSize: 13.5),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: const BoxDecoration(color: AppColors.orange, shape: BoxShape.circle),
            child: IconButton(
              onPressed: onEnvoyer,
              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
