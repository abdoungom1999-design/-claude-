import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/coming_soon_view.dart';

/// Onglet Messages : pas de messagerie backend réelle à ce stade — état
/// vide honnête plutôt qu'une fausse conversation.
class MessagesTabPage extends StatelessWidget {
  const MessagesTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
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
              child: ComingSoonView(
                icon: Icons.chat_bubble_outline_rounded,
                titre: 'Aucun message',
                message:
                    'Vos échanges avec les chauffeurs apparaîtront ici pendant vos courses.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
