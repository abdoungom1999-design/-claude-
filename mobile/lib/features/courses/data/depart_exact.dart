import 'dart:async';

import 'course_service.dart';

/// Complète un flux de courses avec la position exacte de leur départ.
///
/// Le document d'une course n'en porte qu'une version arrondie à ~150 m
/// ([CourseFirestore.departArrondi]) : tant qu'elle attend un chauffeur, tous
/// les chauffeurs la lisent. La position exacte du client est à part
/// ([CourseService.streamDepartExact]), lisible seulement par lui, par son
/// chauffeur une fois la course acceptée, et par l'Admin.
///
/// Pour une course active dont le départ est arrondi, le flux émet d'abord la
/// course telle quelle (jamais d'attente : l'écran s'ouvre avec la zone), puis
/// la même course avec la position exacte dès qu'elle arrive, et à chaque
/// nouvelle version de la course ensuite. Le départ exact n'est écouté que
/// pour la course en cours de suivi : il est abandonné dès qu'elle change,
/// disparaît ou se termine. Une lecture qui échoue ne dérange pas le flux : la
/// course reste utilisable avec son départ arrondi, et la lecture est retentée
/// toute seule ([CourseService.streamDepartExact]).
Stream<CourseFirestore?> completerDepartExact(
  Stream<CourseFirestore?> courses,
  Stream<DepartExact?> Function(String courseId) ouvrirDepartExact,
) {
  late final StreamController<CourseFirestore?> sortie;
  StreamSubscription<CourseFirestore?>? abonnementCourses;
  StreamSubscription<DepartExact?>? abonnementExact;
  CourseFirestore? course;
  String? idSuivi;
  DepartExact? exact;

  void emettre() {
    if (sortie.isClosed) return;
    final actuelle = course;
    final position = exact;
    sortie.add(actuelle != null && actuelle.departArrondi && position != null
        ? actuelle.avecDepartExact(position)
        : actuelle);
  }

  void suivre(String? id) {
    if (id == idSuivi) return;
    final ancien = abonnementExact;
    abonnementExact = null;
    idSuivi = id;
    exact = null;
    ancien?.cancel();
    if (id == null) return;
    abonnementExact = ouvrirDepartExact(id).listen(
      (position) {
        exact = position;
        emettre();
      },
      onError: (Object _) {},
    );
  }

  sortie = StreamController<CourseFirestore?>(
    sync: true,
    onListen: () {
      abonnementCourses = courses.listen(
        (recue) {
          course = recue;
          suivre(recue != null && recue.departArrondi && recue.estActive ? recue.id : null);
          emettre();
        },
        onError: (Object erreur, StackTrace pile) {
          if (!sortie.isClosed) sortie.addError(erreur, pile);
        },
        onDone: () {
          abonnementExact?.cancel();
          abonnementExact = null;
          sortie.close();
        },
      );
    },
    onPause: () => abonnementCourses?.pause(),
    onResume: () => abonnementCourses?.resume(),
    onCancel: () async {
      await abonnementExact?.cancel();
      abonnementExact = null;
      await abonnementCourses?.cancel();
    },
  );
  return sortie.stream;
}
