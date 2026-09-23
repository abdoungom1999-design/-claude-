import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/coming_soon_view.dart';
import '../../../messages/data/chat_service.dart';
import '../../../messages/presentation/messagerie_chat_page.dart';

/// Onglet Messages du Conducteur : liste des conversations réellement
/// en cours avec des clients (voir [ChatService.streamMesChats]),
/// jusque-là inaccessibles côté chauffeur — seul l'écran Client pouvait
/// discuter. Chaque ligne ouvre le même [MessagerieChatPage] temps réel
/// que côté client (StreamBuilder Firestore, bouton d'appel compris).
class ConducteurMessagesTab extends StatefulWidget {
  const ConducteurMessagesTab({super.key});

  @override
  State<ConducteurMessagesTab> createState() => _ConducteurMessagesTabState();
}

class _ConducteurMessagesTabState extends State<ConducteurMessagesTab> {
  final _chatService = ChatService();

  @override
  Widget build(BuildContext context) {
    final monUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Messages',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Expanded(
              child: monUid == null
                  ? const ComingSoonView(
                      icon: Icons.chat_bubble_outline_rounded,
                      titre: 'Messagerie indisponible',
                      message: 'Reconnectez-vous pour accéder à vos conversations.',
                    )
                  : StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _chatService.streamMesChats(monUid),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(color: AppColors.orange),
                          );
                        }
                        final chats = snapshot.data ?? [];
                        if (chats.isEmpty) {
                          return const ComingSoonView(
                            icon: Icons.chat_bubble_outline_rounded,
                            titre: 'Aucune conversation',
                            message: 'Vos échanges avec les clients apparaîtront ici.',
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                          itemCount: chats.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final chat = chats[index];
                            final participants =
                                (chat['participants'] as List?)?.cast<String>() ?? [];
                            final interlocuteurUid = participants.firstWhere(
                              (uid) => uid != monUid,
                              orElse: () => '',
                            );
                            if (interlocuteurUid.isEmpty) return const SizedBox.shrink();
                            return _LigneConversation(
                              chatService: _chatService,
                              interlocuteurUid: interlocuteurUid,
                              dernierMessage: chat['dernierMessage'] as String? ?? '',
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LigneConversation extends StatefulWidget {
  const _LigneConversation({
    required this.chatService,
    required this.interlocuteurUid,
    required this.dernierMessage,
  });

  final ChatService chatService;
  final String interlocuteurUid;
  final String dernierMessage;

  @override
  State<_LigneConversation> createState() => _LigneConversationState();
}

class _LigneConversationState extends State<_LigneConversation> {
  String? _nom;

  @override
  void initState() {
    super.initState();
    _chargerProfil();
  }

  Future<void> _chargerProfil() async {
    final profil = await widget.chatService.chargerProfil(widget.interlocuteurUid);
    if (mounted) setState(() => _nom = profil?['nom'] as String?);
  }

  @override
  Widget build(BuildContext context) {
    final nomAffiche = _nom ?? 'Client Sprint';

    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MessagerieChatPage(
            interlocuteurUid: widget.interlocuteurUid,
            interlocuteurNom: nomAffiche,
            interlocuteurSousTitre: 'Client Sprint',
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.orange, AppColors.orangeDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              nomAffiche.isNotEmpty ? nomAffiche[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nomAffiche,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.dernierMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.grey),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.grey),
        ],
      ),
    );
  }
}
