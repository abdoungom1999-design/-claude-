import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../theme/app_colors.dart';
import 'style_sprint_sombre.dart';

/// Fond de carte de toute l'app : images Google Maps (Map Tiles API) dès
/// qu'une clé web est fournie à la compilation
/// (`--dart-define=GOOGLE_MAPS_WEB_KEY=…`, secret GitHub du même nom),
/// sinon OpenStreetMap (mode démo, développement local).
///
/// La clé web est visible dans le navigateur, comme pour toute carte en
/// ligne : elle est restreinte au site (référents HTTP) et à la seule
/// Map Tiles API dans Google Cloud.
///
/// APK Android : clé distincte (`GOOGLE_MAPS_ANDROID_KEY`), restreinte à
/// l'app Android (package + empreinte SHA-1 du certificat Sprint). Google
/// la vérifie grâce aux en-têtes [entetesAndroid], joints à chaque appel
/// (session et images).
///
/// Style : « Sprint sombre » ([styleSprintSombre]) sur toutes les cartes.
/// Un style refusé par Google (400) fait redemander une session sans
/// style, puis seulement OpenStreetMap en dernier recours.
///
/// Secours : si Google ne répond pas (session refusée, quota, images en
/// erreur), la carte repasse sur OpenStreetMap plutôt que de rester vide.
class FondCarte {
  FondCarte({
    required String cle,
    Dio? dio,
    DateTime Function()? maintenant,
    this.styles = styleSprintSombre,
    this.entetes = const {},
  })  : _cle = cle,
        _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 8))),
        _maintenant = maintenant ?? DateTime.now;

  static const cleWeb = String.fromEnvironment('GOOGLE_MAPS_WEB_KEY');
  static const cleAndroid = String.fromEnvironment('GOOGLE_MAPS_ANDROID_KEY');

  /// Identité de l'APK Sprint pour une clé restreinte à Android : nom du
  /// package et empreinte SHA-1 du certificat de signature (la CI refuse
  /// tout APK qui ne serait pas signé avec ce certificat).
  static const entetesAndroid = {
    'X-Android-Package': 'sn.groupesantine.sprint',
    'X-Android-Cert': '6D6BBAF81DD1B73BDB47102FB00531F5259A4192',
  };

  static bool get _android => !kIsWeb && Platform.isAndroid;

  /// Instance partagée par toutes les cartes (une seule session Google).
  static final instance =
      _android ? FondCarte(cle: cleAndroid, entetes: entetesAndroid) : FondCarte(cle: cleWeb);

  static const urlOpenStreetMap = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const urlGoogle = 'https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}?session={session}&key={key}';

  /// Au-delà, les images Google en erreur font repasser sur OpenStreetMap.
  static const erreursToleres = 6;

  final String _cle;
  final List<Map<String, Object>> styles;

  /// En-têtes joints aux appels Google (identité de l'app Android).
  final Map<String, String> entetes;
  final Dio _dio;
  final DateTime Function() _maintenant;

  bool get googleConfigure => _cle.isNotEmpty;

  SessionTuiles? _session;
  Future<SessionTuiles?>? _enCours;
  int _erreurs = 0;

  /// Passe à `true` quand Google est abandonné pour cette visite.
  final secours = ValueNotifier<bool>(false);

  /// Session Google valide (créée au premier besoin, renouvelée une heure
  /// avant son expiration), ou `null` : il faut alors OpenStreetMap.
  Future<SessionTuiles?> session() {
    if (!googleConfigure || secours.value) return Future.value(null);
    final actuelle = _session;
    if (actuelle != null && actuelle.expire.isAfter(_maintenant().add(const Duration(hours: 1)))) {
      return Future.value(actuelle);
    }
    return _enCours ??= _creerSession().whenComplete(() => _enCours = null);
  }

  Future<SessionTuiles?> _creerSession() async {
    if (styles.isNotEmpty) {
      try {
        return await _demanderSession(avecStyle: true);
      } on DioException catch (e) {
        // Style refusé : la carte reste Google, sans le style.
        if (e.response?.statusCode != 400) return _abandonner(e);
        debugPrint('Style de carte refusé par Google : carte sans style.');
      } catch (e) {
        return _abandonner(e);
      }
    }
    try {
      return await _demanderSession(avecStyle: false);
    } catch (e) {
      return _abandonner(e);
    }
  }

  SessionTuiles? _abandonner(Object e) {
    debugPrint('Fond de carte Google indisponible ($e) : OpenStreetMap.');
    secours.value = true;
    return null;
  }

  Future<SessionTuiles> _demanderSession({required bool avecStyle}) async {
    final reponse = await _dio.post<Map<String, dynamic>>(
      'https://tile.googleapis.com/v1/createSession',
      queryParameters: {'key': _cle},
      options: Options(headers: entetes),
      data: {
        'mapType': 'roadmap',
        'language': 'fr-FR',
        'region': 'SN',
        if (avecStyle) 'styles': styles,
      },
    );
    final donnees = reponse.data ?? const {};
    final jeton = donnees['session'];
    final expiration = int.tryParse('${donnees['expiry']}');
    if (jeton is! String || jeton.isEmpty || expiration == null) {
      throw const FormatException('Session Google invalide');
    }
    return _session = SessionTuiles(
      jeton: jeton,
      expire: DateTime.fromMillisecondsSinceEpoch(expiration * 1000, isUtc: true),
    );
  }

  /// Une image Google en erreur (clé refusée, quota…) : au-delà de
  /// [erreursToleres], on repasse sur OpenStreetMap.
  void signalerErreur() {
    if (++_erreurs >= erreursToleres && !secours.value) {
      debugPrint('Images Google en erreur : OpenStreetMap.');
      secours.value = true;
    }
  }

  Map<String, String> optionsGoogle(SessionTuiles session) => {'session': session.jeton, 'key': _cle};
}

class SessionTuiles {
  const SessionTuiles({required this.jeton, required this.expire});

  final String jeton;
  final DateTime expire;
}

/// Matrice du filtre sombre des images OpenStreetMap : luminance inversée puis
/// ramenée dans les gris très sombres (terre ≈ 14/255, bâti et eau ≈ 40,
/// contours de routes ≈ 80), sans aucune couleur : les trois canaux reçoivent
/// la même valeur, donc plus de vert de parc ni de jaune d'axe.
const matriceSombre = <double>[
  -0.1913, -0.6437, -0.0650, 0, 229, //
  -0.1913, -0.6437, -0.0650, 0, 229, //
  -0.1913, -0.6437, -0.0650, 0, 229, //
  0, 0, 0, 1, 0, //
];

/// Même rendu « Sprint sombre » que le style Google, pour les images
/// OpenStreetMap (qui ne se stylisent pas).
const filtreSombre = ColorFilter.matrix(matriceSombre);

/// Couche de fond à placer en premier dans `FlutterMap(children: …)`.
class CoucheFondCarte extends StatefulWidget {
  const CoucheFondCarte({super.key, this.fond});

  /// Injectable pour les tests ; par défaut [FondCarte.instance].
  final FondCarte? fond;

  @override
  State<CoucheFondCarte> createState() => _CoucheFondCarteState();
}

class _CoucheFondCarteState extends State<CoucheFondCarte> {
  late final FondCarte _fond = widget.fond ?? FondCarte.instance;
  SessionTuiles? _session;
  bool _pret = false;

  @override
  void initState() {
    super.initState();
    _fond.secours.addListener(_actualiser);
    _charger();
  }

  Future<void> _charger() async {
    final session = await _fond.session();
    if (!mounted) return;
    setState(() {
      _session = session;
      _pret = true;
    });
  }

  void _actualiser() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _fond.secours.removeListener(_actualiser);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    // Session Google en cours de création : rien d'affiché (évite de
    // charger puis jeter des images OpenStreetMap).
    if (!_pret && _fond.googleConfigure && !_fond.secours.value) return const SizedBox.shrink();
    if (session == null || _fond.secours.value) {
      return TileLayer(
        urlTemplate: FondCarte.urlOpenStreetMap,
        userAgentPackageName: 'sn.groupesantine.sprint',
        // OpenStreetMap ne se stylise pas : gris très sombres, pour rester
        // proche du style « Sprint sombre ».
        tileBuilder: (context, image, tuile) => ColorFiltered(colorFilter: filtreSombre, child: image),
      );
    }
    return TileLayer(
      key: ValueKey(session.jeton),
      urlTemplate: FondCarte.urlGoogle,
      additionalOptions: _fond.optionsGoogle(session),
      userAgentPackageName: 'sn.groupesantine.sprint',
      // Copie modifiable : flutter_map y ajoute son propre User-Agent.
      tileProvider: _fond.entetes.isEmpty ? null : NetworkTileProvider(headers: {..._fond.entetes}),
      maxNativeZoom: 20,
      errorTileCallback: (tuile, erreur, pile) => _fond.signalerErreur(),
    );
  }
}

/// Mentions obligatoires du fond de carte (Google ou OpenStreetMap), à
/// placer en dernier dans `FlutterMap(children: …)`.
class MentionsFondCarte extends StatelessWidget {
  const MentionsFondCarte({super.key, this.fond});

  final FondCarte? fond;

  @override
  Widget build(BuildContext context) {
    final f = fond ?? FondCarte.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: f.secours,
      builder: (context, secours, _) {
        final google = f.googleConfigure && !secours;
        return Align(
          alignment: Alignment.bottomLeft,
          child: IgnorePointer(
            child: Container(
              margin: const EdgeInsets.all(4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.carte.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text.rich(
                google
                    ? TextSpan(children: [
                        const TextSpan(
                          text: 'Google',
                          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2),
                        ),
                        TextSpan(text: '  Données cartographiques ©${DateTime.now().year} Google'),
                      ])
                    : const TextSpan(text: '© OpenStreetMap contributors'),
                style: const TextStyle(fontSize: 10, color: AppColors.texteDiscret),
              ),
            ),
          ),
        );
      },
    );
  }
}
