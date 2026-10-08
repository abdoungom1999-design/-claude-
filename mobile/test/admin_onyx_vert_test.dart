import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/theme/app_colors.dart';
import 'package:sprint/core/widgets/app_card.dart';
import 'package:sprint/core/widgets/onyx_vert.dart';
import 'package:sprint/features/admin/presentation/widgets/admin_sidebar.dart';
import 'package:sprint/features/admin/presentation/widgets/admin_topbar.dart';

void main() {
  testWidgets('Admin : menu latéral Onyx, onglet actif en pastille verte avec icône et texte verts', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Row(children: [AdminSidebar(indexSelectionne: 2, onSelection: (_) {}, onDeconnexion: () {})])),
    ));
    // La police de test (Ahem) élargit les textes : débordement sans objet en vrai.
    tester.takeException();
    final fond = tester.widget<Container>(find.descendant(of: find.byType(AdminSidebar), matching: find.byType(Container)).first);
    expect((fond.decoration! as BoxDecoration).color, AppColors.fondBarre);

    Color? texte(String libelle) => tester.widget<Text>(find.text(libelle)).style?.color;
    expect(texte('Chauffeurs'), AppColors.vert);
    expect(texte('Clients'), AppColors.texte);
    expect(tester.widget<Icon>(find.byIcon(Icons.two_wheeler_outlined)).color, AppColors.vert);
    expect(tester.widget<Icon>(find.byIcon(Icons.people_outline_rounded)).color, AppColors.texteDiscret);
  });

  testWidgets('Admin : le nom du compte est centré avec son avatar (et non collé en haut)', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Column(children: [AdminTopbar(titreSection: 'Dashboard')])),
    ));
    final avatar = tester.getRect(find.text('GS')).center.dy;
    final nom = tester.getRect(find.text('Admin Santine')).center.dy;
    final role = tester.getRect(find.text('Super administrateur')).center.dy;
    expect(((nom + role) / 2 - avatar).abs(), lessThan(8));
  });

  testWidgets('Cartes verre : flou par défaut, sans flou sur les écrans denses (Admin)', (tester) async {
    Future<void> afficher({required bool flou}) => tester.pumpWidget(MaterialApp(
          home: ThemeOnyxVert(flou: flou, child: const AppCard(child: Text('x'))),
        ));

    await afficher(flou: true);
    expect(find.byWidgetPredicate((w) => w is BackdropFilter && w.filter == ImageFilter.blur(sigmaX: 24, sigmaY: 24)), findsOneWidget);
    expect(find.byType(CarteVerre), findsOneWidget);

    await afficher(flou: false);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(CarteVerre), findsOneWidget);
  });
}
