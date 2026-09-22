import 'package:flutter/material.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/coming_soon_view.dart';
import 'chat_page.dart';

/// Onglet Messages : liste des conversations avec les chauffeurs, chacune
/// ouvrant une véritable interface de chat (voir [ChatPage]).
class MessagesTabPage extends StatefulWidget {
  const MessagesTabPage({super.key});

  @override
  State<MessagesTabPage> createState() => _MessagesTabPageState();
}

class _MessagesTabPageState extends State<MessagesTabPage> {
  @override
  Widget build(BuildContext context) {
    final conversations = DemoData.conversations();

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
              child: conversations.isEmpty
                  ? const ComingSoonView(
                      icon: Icons.chat_bubble_outline_rounded,
                      titre: 'Aucun message',
                      message:
                          'Vos échanges avec les chauffeurs apparaîtront ici pendant vos courses.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                      itemCount: conversations.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final conversation = conversations[index];
                        final dernier = conversation.messages.isNotEmpty
                            ? conversation.messages.last
                            : null;
                        return AppCard(
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChatPage(
                                  titre: conversation.nom,
                                  sousTitre: conversation.sousTitre,
                                  messages: conversation.messages,
                                  reponseAutomatique:
                                      'D\'accord, merci pour votre message !',
                                ),
                              ),
                            );
                            if (mounted) setState(() {});
                          },
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
                                  conversation.nom.isNotEmpty
                                      ? conversation.nom[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      conversation.nom,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      dernier?.texte ?? conversation.sousTitre,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (dernier != null)
                                Text(
                                  '${dernier.heure.hour.toString().padLeft(2, '0')}:'
                                  '${dernier.heure.minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.grey),
                                ),
                            ],
                          ),
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
