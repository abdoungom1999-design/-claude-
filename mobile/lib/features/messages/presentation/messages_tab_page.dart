import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/coming_soon_view.dart';
import '../../../firebase_options.dart';
import '../data/chat_service.dart';
import 'messagerie_chat_page.dart';

/// Onglet Messages : liste des chauffeurs disponibles pour discuter
/// (dossier validé), chacun ouvrant un vrai chat temps réel Firestore
/// (voir [MessagerieChatPage]) — la simulation de conversations et de
/// réponses automatiques du Mode Démo a été retirée.
class MessagesTabPage extends StatefulWidget {
  const MessagesTabPage({super.key});

  @override
  State<MessagesTabPage> createState() => _MessagesTabPageState();
}

class _MessagesTabPageState extends State<MessagesTabPage> {
  final _chatService = ChatService();

  @override
  Widget build(BuildContext context) {
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
              child: !DefaultFirebaseOptions.estConfigure
                  ? const ComingSoonView(
                      icon: Icons.chat_bubble_outline_rounded,
                      titre: 'Messagerie indisponible',
                      message: 'La messagerie instantanée nécessite le backend Firebase.',
                    )
                  : StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _chatService.streamConducteursDisponibles(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(color: AppColors.orange),
                          );
                        }
                        final conducteurs = snapshot.data ?? [];
                        if (conducteurs.isEmpty) {
                          return const ComingSoonView(
                            icon: Icons.chat_bubble_outline_rounded,
                            titre: 'Aucun message',
                            message:
                                'Vos échanges avec les chauffeurs apparaîtront ici pendant vos courses.',
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                          itemCount: conducteurs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final conducteur = conducteurs[index];
                            final nom = (conducteur['nom'] as String?) ?? 'Chauffeur Sprint';
                            final uid = conducteur['uid'] as String;
                            return AppCard(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => MessagerieChatPage(
                                    interlocuteurUid: uid,
                                    interlocuteurNom: nom,
                                    interlocuteurSousTitre: 'Chauffeur Sprint',
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
                                      nom.isNotEmpty ? nom[0].toUpperCase() : '?',
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
                                          nom,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        const Text(
                                          'Chauffeur Sprint · Disponible',
                                          style: TextStyle(fontSize: 12, color: AppColors.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded, color: AppColors.grey),
                                ],
                              ),
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
