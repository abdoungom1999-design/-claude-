import 'package:flutter/material.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/widgets/section_list_tile.dart';
import '../../messages/presentation/chat_page.dart';
import 'a_propos_page.dart';
import 'centre_aide_page.dart';
import 'nous_contacter_page.dart';

/// Menu Aide & Support : Centre d'aide, Nous contacter, Mes échanges,
/// À propos de Sprint.
class AideSupportPage extends StatelessWidget {
  const AideSupportPage({super.key});

  void _ouvrir(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aide & Support')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SectionListTile(
              icon: Icons.help_outline_rounded,
              label: 'Centre d\'aide',
              onTap: () => _ouvrir(context, const CentreAidePage()),
            ),
            SectionListTile(
              icon: Icons.call_outlined,
              label: 'Nous contacter',
              onTap: () => _ouvrir(context, const NousContacterPage()),
            ),
            SectionListTile(
              icon: Icons.forum_outlined,
              label: 'Mes échanges',
              onTap: () => _ouvrir(
                context,
                ChatPage(
                  titre: 'Mes échanges',
                  sousTitre: 'Support Sprint',
                  messages: DemoData.messagesSupport,
                  reponseAutomatique:
                      'Merci pour votre message ! Notre équipe support vous '
                      'répond dans les plus brefs délais.',
                  emptyIcon: Icons.forum_outlined,
                  emptyTitre: 'Aucun échange',
                  emptyMessage: 'Écrivez à l\'équipe Sprint, nous vous répondrons ici.',
                ),
              ),
            ),
            SectionListTile(
              icon: Icons.info_outline_rounded,
              label: 'À propos de Sprint',
              onTap: () => _ouvrir(context, const AProposPage()),
            ),
          ],
        ),
      ),
    );
  }
}
