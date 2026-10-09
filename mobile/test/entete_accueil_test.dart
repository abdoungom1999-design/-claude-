import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/theme/app_colors.dart';
import 'package:sprint/features/home/presentation/entete_accueil.dart';

/// En-tête de l'accueil client : marque et slogan à gauche, cloche et avatar
/// (initiale du prénom) à droite.
void main() {
  group('initiale du prénom', () {
    test('premier mot du nom complet, en majuscule', () {
      expect(initialeDuPrenom('Bamba Diallo'), 'B');
      expect(initialeDuPrenom('Abdou'), 'A');
      expect(initialeDuPrenom('  mame diarra  ndiaye '), 'M');
      expect(initialeDuPrenom('élodie Martin'), 'É');
      expect(initialeDuPrenom("N'Deye Fall"), 'N');
    });

    test('rien quand le nom est absent, vide ou ne commence pas par une lettre', () {
      expect(initialeDuPrenom(null), isNull);
      expect(initialeDuPrenom(''), isNull);
      expect(initialeDuPrenom('   '), isNull);
      expect(initialeDuPrenom('+221 77 000 00 00'), isNull);
      expect(initialeDuPrenom('1234'), isNull);
      expect(initialeDuPrenom('-- test'), isNull);
    });

    test('une seule lettre, même quand la majuscule en compte deux (« ß » donne « SS » sur le web)', () {
      expect(initialeDuPrenom('ßaïd')!.runes, hasLength(1));
    });
  });

  Future<void> afficher(
    WidgetTester tester, {
    Stream<Map<String, dynamic>?>? profil,
    String? nomRepli,
    VoidCallback? onNotifications,
    VoidCallback? onCompte,
    Size taille = const Size(390, 844),
    double echelleTexte = 1,
  }) async {
    tester.view.physicalSize = taille;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, enfant) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(echelleTexte)),
        child: enfant!,
      ),
      home: Scaffold(
        body: SafeArea(
          child: EnteteAccueil(
            profil: profil ?? Stream.value(null),
            nomRepli: nomRepli,
            onNotifications: onNotifications ?? () {},
            onCompte: onCompte ?? () {},
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  testWidgets('la marque « Sprint » en haut à gauche, le slogan discret juste dessous', (tester) async {
    await afficher(tester);

    final marque = find.text('Sprint');
    final slogan = find.text(EnteteAccueil.slogan);
    expect(marque, findsOneWidget);
    expect(slogan, findsOneWidget);
    // Alignés à gauche, le slogan sous la marque.
    expect(tester.getTopLeft(slogan).dx, tester.getTopLeft(marque).dx);
    expect(tester.getTopLeft(slogan).dy, greaterThanOrEqualTo(tester.getBottomLeft(marque).dy));
    // Slogan en gris clair, plus petit que la marque.
    final styleSlogan = tester.widget<Text>(slogan).style!;
    expect(styleSlogan.color, AppColors.texteDiscret);
    expect(styleSlogan.fontSize!, lessThan(tester.widget<Text>(marque).style!.fontSize!));
    // Dans le quart gauche supérieur de l'écran.
    expect(tester.getTopLeft(marque).dx, lessThan(40));
    expect(tester.getTopLeft(marque).dy, lessThan(80));
  });

  testWidgets('la cloche puis l\'avatar à droite, après la marque', (tester) async {
    await afficher(tester, profil: Stream.value({'nom': 'Bamba Diallo'}));

    final cloche = find.byIcon(Icons.notifications_outlined);
    final avatar = find.byType(AvatarProfil);
    expect(cloche, findsOneWidget);
    expect(avatar, findsOneWidget);
    expect(tester.getCenter(cloche).dx, lessThan(tester.getCenter(avatar).dx));
    expect(tester.getTopRight(find.text(EnteteAccueil.slogan)).dx, lessThan(tester.getCenter(cloche).dx));
    // L'avatar est tout à droite, avec la marge de l'écran.
    expect(tester.getTopRight(avatar).dx, 390 - 16);
    expect(find.byTooltip('Notifications'), findsOneWidget);
    expect(find.byTooltip('Mon compte'), findsOneWidget);
  });

  testWidgets('l\'avatar affiche l\'initiale du prénom en majuscule', (tester) async {
    await afficher(tester, profil: Stream.value({'nom': 'bamba Diallo'}));
    expect(find.text('B'), findsOneWidget);
    expect(find.byIcon(Icons.person_rounded), findsNothing);

    await afficher(tester, profil: Stream.value({'nom': '  Abdou '}));
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('sans nom au profil : l\'icône de profil, jamais une lettre', (tester) async {
    for (final profil in <Map<String, dynamic>?>[null, <String, dynamic>{}, {'nom': ''}, {'nom': '   '}, {'nom': 42}, {'nom': '+221770000000'}]) {
      await afficher(tester, profil: Stream.value(profil));
      expect(find.byIcon(Icons.person_rounded), findsOneWidget, reason: '$profil');
      expect(find.descendant(of: find.byType(AvatarProfil), matching: find.byType(Text)), findsNothing, reason: '$profil');
    }
  });

  testWidgets('démo : le nom de repli donne l\'initiale, mais le vrai nom l\'emporte', (tester) async {
    await afficher(tester, nomRepli: 'Bamba Diallo');
    expect(find.text('B'), findsOneWidget);

    await afficher(tester, profil: Stream.value({'nom': 'Awa Ndiaye'}), nomRepli: 'Bamba Diallo');
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsNothing);
  });

  testWidgets('le nom du profil se met à jour en direct', (tester) async {
    final flux = Stream<Map<String, dynamic>?>.fromIterable([
      null,
      {'nom': 'Cheikh Ba'},
    ]);
    await afficher(tester, profil: flux);
    expect(find.text('C'), findsOneWidget);
  });

  testWidgets('toucher la cloche ou l\'avatar appelle les bonnes actions', (tester) async {
    var cloche = 0;
    var compte = 0;
    await afficher(tester, profil: Stream.value({'nom': 'Bamba Diallo'}), onNotifications: () => cloche++, onCompte: () => compte++);

    await tester.tap(find.byIcon(Icons.notifications_outlined));
    expect((cloche, compte), (1, 0));
    await tester.tap(find.byType(AvatarProfil));
    expect((cloche, compte), (1, 1));
  });

  testWidgets('petit téléphone (320 px) et texte agrandi à 130 % : aucun débordement', (tester) async {
    await afficher(tester, profil: Stream.value({'nom': 'Bamba Diallo'}), taille: const Size(320, 568), echelleTexte: 1.3);
    expect(tester.takeException(), isNull);
    expect(find.text('B'), findsOneWidget);
    // Cloche et avatar restent entiers dans l'écran.
    expect(tester.getTopRight(find.byType(AvatarProfil)).dx, lessThanOrEqualTo(320));
  });
}
