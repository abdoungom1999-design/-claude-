import 'package:flutter/material.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/theme/app_colors.dart';

/// Interface de chat (style messagerie) générique : bulles alignées à
/// droite (moi, orange) ou à gauche (interlocuteur, gris), champ de
/// saisie avec bouton d'envoi qui ajoute la bulle immédiatement. Utilisée
/// pour les conversations avec un chauffeur (onglet Messages) et pour le
/// fil support (Mes échanges).
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.titre,
    required this.sousTitre,
    required this.messages,
    this.onEnvoyer,
    this.reponseAutomatique,
    this.emptyIcon = Icons.chat_bubble_outline_rounded,
    this.emptyTitre = 'Aucun message',
    this.emptyMessage = 'Écrivez le premier message.',
  });

  final String titre;
  final String sousTitre;

  /// Liste mutable partagée avec [DemoData] : chaque envoi y ajoute un
  /// [ChatMessage] directement, pour que la conversation persiste tant
  /// que l'app reste ouverte.
  final List<ChatMessage> messages;

  /// Appelé à l'envoi, en plus de l'ajout local à [messages] (utilisé par
  /// le fil support pour écrire dans [DemoData.messagesSupport]).
  final ValueChanged<String>? onEnvoyer;

  /// Réponse simulée de l'interlocuteur, affichée après un court délai
  /// suivant l'envoi d'un message — pour une démo vivante plutôt qu'un
  /// message qui reste sans réponse.
  final String? reponseAutomatique;

  final IconData emptyIcon;
  final String emptyTitre;
  final String emptyMessage;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late final List<ChatMessage> _messages = widget.messages;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _envoyer() {
    final texte = _controller.text.trim();
    if (texte.isEmpty) return;

    setState(() {
      _messages.add(
        ChatMessage(texte: texte, envoyeParMoi: true, heure: DateTime.now()),
      );
    });
    widget.onEnvoyer?.call(texte);
    _controller.clear();
    _defilerVersLeBas();

    final reponse = widget.reponseAutomatique;
    if (reponse != null) {
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        setState(() {
          _messages.add(
            ChatMessage(texte: reponse, envoyeParMoi: false, heure: DateTime.now()),
          );
        });
        _defilerVersLeBas();
      });
    }
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
            Text(widget.titre, style: const TextStyle(fontSize: 16)),
            Text(
              widget.sousTitre,
              style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(widget.emptyIcon, size: 44, color: AppColors.greyBorder),
                            const SizedBox(height: 14),
                            Text(
                              widget.emptyTitre,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.emptyMessage,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) => _Bulle(message: _messages[index]),
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
  const _Bulle({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final moi = message.envoyeParMoi;
    return Align(
      alignment: moi ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
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
              message.texte,
              style: TextStyle(
                color: moi ? Colors.white : AppColors.text,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${message.heure.hour.toString().padLeft(2, '0')}:'
              '${message.heure.minute.toString().padLeft(2, '0')}',
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
            decoration: const BoxDecoration(
              color: AppColors.orange,
              shape: BoxShape.circle,
            ),
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
