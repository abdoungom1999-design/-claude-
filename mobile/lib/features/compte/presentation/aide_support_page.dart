import 'package:flutter/material.dart';
import '../../../core/widgets/section_list_tile.dart';
import 'a_propos_page.dart';
import 'centre_aide_page.dart';
import 'nous_contacter_page.dart';
import '../../../core/widgets/onyx_vert.dart';

/// Menu Aide & Support : Centre d'aide, Nous contacter, À propos de Sprint.
/// (Le faux fil « Mes échanges » a été retiré : il n'envoyait rien à personne ;
/// le vrai canal est « Contacter le support » du Centre d'aide.)
class AideSupportPage extends StatelessWidget {
  const AideSupportPage({super.key});

  void _ouvrir(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return SousPageOnyx(child: Scaffold(
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
              icon: Icons.mail_outline_rounded,
              label: 'Nous contacter',
              onTap: () => _ouvrir(context, const NousContacterPage()),
            ),
            SectionListTile(
              icon: Icons.info_outline_rounded,
              label: 'À propos de Sprint',
              onTap: () => _ouvrir(context, const AProposPage()),
            ),
          ],
        ),
      ),
    ));
  }
}
