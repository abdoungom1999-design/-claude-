import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Fournisseur d'adresse du routeur qui n'écrit PAS dans l'historique du
/// navigateur.
///
/// Par défaut, go_router ajoute une entrée d'historique du navigateur à
/// chaque page et repasse l'historique en mode « entrées multiples » à
/// chaque navigation. Le geste « retour » du téléphone (ou le bouton du
/// navigateur) remonte alors cet historique, jusqu'aux écrans de connexion,
/// et ne sait pas fermer une sous-page ouverte à la main.
///
/// Ici, l'adresse en cours est simplement lue (démarrage, lien de
/// notification, page rechargée) mais jamais réécrite : avec le mode
/// « entrée unique » choisi par [configurerHistoriqueNavigateur], le geste
/// « retour » devient un simple « retour » dans l'app (fermer la page en
/// cours), traité par le routeur comme sur Android.
class RouteSansHistorique extends RouteInformationProvider {
  RouteSansHistorique(this._interne);

  /// Fournisseur d'origine, celui du routeur (`GoRouter.routeInformationProvider`).
  final RouteInformationProvider _interne;

  @override
  RouteInformation get value => _interne.value;

  @override
  void addListener(VoidCallback listener) => _interne.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _interne.removeListener(listener);

  /// Rien n'est écrit dans l'historique du navigateur.
  @override
  void routerReportsNewRouteInformation(RouteInformation routeInformation,
      {RouteInformationReportingType type = RouteInformationReportingType.none}) {}
}

/// `MaterialApp.router` branché sur [routeur] sans écriture dans l'historique
/// du navigateur : à passer en paramètres à la place de `routerConfig`.
extension ConfigSansHistorique on GoRouter {
  RouterConfig<Object> get configSansHistorique => RouterConfig<Object>(
        routeInformationProvider: RouteSansHistorique(routeInformationProvider),
        routeInformationParser: routeInformationParser,
        routerDelegate: routerDelegate,
        backButtonDispatcher: backButtonDispatcher,
      );
}
