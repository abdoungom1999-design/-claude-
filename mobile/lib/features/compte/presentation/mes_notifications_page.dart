import 'package:flutter/material.dart';
import '../../../core/widgets/coming_soon_view.dart';

/// Boîte de réception des notifications (cloche de l'onglet Accueil).
/// Toujours vide pour l'instant : aucun backend de notifications
/// poussées n'existe encore côté Firebase.
class MesNotificationsPage extends StatelessWidget {
  const MesNotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: const SafeArea(
        child: ComingSoonView(
          icon: Icons.notifications_none_rounded,
          titre: 'Aucune notification pour le moment',
          message: 'Vous serez alerté ici dès qu\'il y aura du nouveau.',
        ),
      ),
    );
  }
}
