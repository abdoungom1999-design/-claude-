import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/theme/app_colors.dart';
import 'package:sprint/core/theme/app_theme.dart';

/// Duo de la charte : Bleu de Confiance = accent (icônes, pastilles, menus,
/// états) ; orange vif = EXCLUSIVEMENT les boutons d'action (Commander,
/// Soumettre, Contacter, Payer…).
void main() {
  test('le thème global prend le bleu comme couleur principale, les boutons d\'action restent orange', () {
    final theme = AppTheme.light;
    expect(theme.colorScheme.primary, AppColors.bleu);
    final fond = theme.elevatedButtonTheme.style!.backgroundColor!.resolve(<WidgetState>{});
    expect(fond, AppColors.orange);
  });

  test('garde-fou : l\'orange n\'apparaît que dans les fichiers de boutons d\'action', () {
    // Chaque fichier de cette liste porte au moins un bouton d'action (fond
    // du bouton, dégradé du bouton principal, pastille d'envoi). Ajouter un
    // fichier ici est un choix de design à justifier : un accent, un état
    // ou une icône s'écrivent en bleu (AppColors.bleu).
    const autorises = {
      'lib/core/theme/app_theme.dart',
      'lib/core/widgets/primary_button.dart',
      'lib/core/widgets/ecran_statut_onyx.dart',
      'lib/core/widgets/wallet_card.dart',
      'lib/core/widgets/mot_de_passe_oublie_dialog.dart',
      'lib/core/notifications/carte_notifications.dart',
      'lib/features/onboarding/presentation/welcome_page.dart',
      'lib/features/admin/presentation/sections/admin_finances_section.dart',
      'lib/features/admin/presentation/admin_ticket_page.dart',
      'lib/features/admin/presentation/widgets/dialogue_sanction.dart',
      'lib/features/activite/presentation/detail_course_page.dart',
      'lib/features/portefeuille/presentation/recharge_portefeuille_page.dart',
      'lib/features/client/presentation/payment_processing_page.dart',
      'lib/features/evaluations/presentation/evaluation_course.dart',
      'lib/features/home/presentation/bandeau_promo.dart',
      'lib/features/messages/presentation/chat_page.dart',
      'lib/features/messages/presentation/messagerie_chat_page.dart',
      'lib/features/support/presentation/widgets/conversation_ticket.dart',
      'lib/features/conducteur/presentation/widgets/nouvelle_course_reelle_sheet.dart',
      'lib/features/conducteur/presentation/widgets/nouvelle_course_sheet.dart',
      'lib/features/conducteur/presentation/widgets/course_active_bandeau.dart',
      'lib/features/conducteur/presentation/widgets/bouton_en_ligne_circulaire.dart',
      'lib/core/theme/app_colors.dart',
    };
    final motif = RegExp(r'AppColors\.orange(Dark|Light)?\b');
    final intrus = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final chemin = f.path.replaceAll('\\', '/');
      if (motif.hasMatch(f.readAsStringSync()) && !autorises.contains(chemin)) intrus.add(chemin);
    }
    expect(intrus, isEmpty, reason: 'orange hors bouton d\'action : $intrus');
  });
}
