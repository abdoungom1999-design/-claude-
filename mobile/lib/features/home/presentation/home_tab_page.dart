import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/location/localiser.dart';
import '../../../core/maps/distance_utils.dart';
import '../../../core/maps/fond_carte.dart';
import '../../../core/maps/motos_proches_controller.dart';
import '../../../core/maps/proximite_service.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/bouton_rond_verre.dart';
import '../../../core/widgets/moto_vue_dessus.dart';
import '../../../core/widgets/onyx_vert.dart';
import '../../../firebase_options.dart';
import '../../auth/data/auth_repository.dart';
import '../../compte/presentation/mes_notifications_page.dart';
import 'bandeau_promo.dart';
import 'entete_accueil.dart';

/// Onglet Accueil (charte Onyx & Vert) : carte sombre en plein écran
/// avec les motos disponibles alentour (anonymes, positions arrondies à
/// 150 m par le serveur), et un panneau « verre » sombre flottant « Où
/// allez-vous ? » : recherche, bandeau promo, services Course moto / Colis.
/// En haut : la marque et son slogan, la cloche et l'avatar du client
/// ([EnteteAccueil]).
class HomeTabPage extends StatefulWidget {
  const HomeTabPage({
    super.key,
    this.proximite,
    this.localiser,
    this.fond,
    this.coucheFond,
    this.profil,
    this.bannieres = banniereParDefaut,
  });

  /// Injectables pour les tests ; par défaut selon Firebase (démo sinon).
  final ProximiteService? proximite;
  final Localiser? localiser;
  final FondCarte? fond;

  /// Fond de carte ; par défaut les images Google « Sprint sombre » (ou
  /// OpenStreetMap). Les tests le remplacent (pas de réseau).
  final Widget? coucheFond;

  /// Flux du profil du client pour l'avatar de l'en-tête ; par défaut son
  /// profil Firebase (aucun nom en démo : voir [DemoData.monNomClient]).
  final Stream<Map<String, dynamic>?>? profil;

  /// Bannières du carrousel promo (par défaut [banniereParDefaut]).
  final List<BanniereProm> bannieres;

  static const centreDakar = LatLng(14.6928, -17.4467);

  /// Fréquence de mise à jour des motos tant que l'accueil est affiché.
  static const rafraichissement = Duration(seconds: 20);

  @override
  State<HomeTabPage> createState() => _HomeTabPageState();
}

class _HomeTabPageState extends State<HomeTabPage> {
  final _carte = MapController();
  late final Localiser _localiser = widget.localiser ?? localiserAppareil;

  /// Onglet masqué (autre onglet ouvert) : pas d'appel inutile.
  late final MotosProchesController _motos = MotosProchesController(
    service: widget.proximite,
    rafraichissement: HomeTabPage.rafraichissement,
    actif: () => mounted && TickerMode.valuesOf(context).enabled,
  );

  /// Profil du client, écouté une seule fois pour toute la durée de l'onglet.
  late final Stream<Map<String, dynamic>?> _profil = widget.profil ?? _profilConnecte();

  LatLng? _moi;
  Timer? _attenteDeplacement;

  @override
  void initState() {
    super.initState();
    _motos.chercherAutour(HomeTabPage.centreDakar);
    // Localisation silencieuse : seulement si l'autorisation existe déjà.
    _localiserPuisCentrer(demander: false);
  }

  @override
  void dispose() {
    _attenteDeplacement?.cancel();
    _motos.dispose();
    _carte.dispose();
    super.dispose();
  }

  /// Profil Firebase du client connecté ; rien (l'avatar montre l'icône de
  /// profil) si Firebase n'est pas prêt, par exemple dans un test.
  static Stream<Map<String, dynamic>?> _profilConnecte() {
    try {
      return AuthRepository().profilUtilisateurStream();
    } on Object {
      return Stream.value(null);
    }
  }

  Future<void> _localiserPuisCentrer({required bool demander}) async {
    final position = await _localiser(demander: demander);
    if (!mounted) return;
    if (position == null) {
      if (demander) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Position indisponible : autorisez la localisation dans votre navigateur.')),
        );
      }
      return;
    }
    setState(() => _moi = position);
    _carte.move(position, 15);
    _motos.chercherAutour(position);
  }

  void _surDeplacement(MapCamera camera, bool geste) {
    if (!geste) return;
    _attenteDeplacement?.cancel();
    _attenteDeplacement = Timer(const Duration(milliseconds: 700), () {
      final precedent = _motos.centre;
      // Petits déplacements : les motos déjà affichées suffisent.
      if (precedent != null &&
          DistanceUtils.distanceKm(
                latDepart: precedent.latitude,
                lngDepart: precedent.longitude,
                latArrivee: camera.center.latitude,
                lngArrivee: camera.center.longitude,
              ) <
              0.5) {
        return;
      }
      _motos.chercherAutour(camera.center);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fond,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _carte,
              options: MapOptions(
                initialCenter: HomeTabPage.centreDakar,
                initialZoom: 14.5,
                // Fond sombre pendant le chargement des images (sinon le gris clair par défaut de flutter_map).
                backgroundColor: AppColors.fondHaut,
                minZoom: 11,
                maxZoom: 18,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                onPositionChanged: _surDeplacement,
              ),
              children: [
                widget.coucheFond ?? CoucheFondCarte(fond: widget.fond),
                ListenableBuilder(
                  listenable: _motos,
                  builder: (context, _) => MarkerLayer(
                    markers: [
                      for (final m in _motos.motos)
                        Marker(
                          point: m.position,
                          width: 46,
                          height: 46,
                          child: Center(child: MotoVueDessus(cap: m.cap, taille: 40)),
                        ),
                      if (_moi != null) Marker(point: _moi!, width: 44, height: 44, child: const _PointMoi()),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 400),
                  child: MentionsFondCarte(fond: widget.fond),
                ),
              ],
            ),
          ),
          // Voile en haut : lisibilité de la marque et des boutons sur n'importe quel fond.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 140,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.fondHaut.withValues(alpha: 0.86), AppColors.fondHaut.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: EnteteAccueil(
                profil: _profil,
                // Démo (pas de Firebase) : le client de démonstration ; avec un vrai compte sans nom, l'icône de profil.
                nomRepli: DefaultFirebaseOptions.estConfigure ? null : DemoData.monNomClient,
                onNotifications: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MesNotificationsPage()),
                ),
                onCompte: () => context.go(AppRoutes.compteTab),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            // Grand écran (ordinateur, tablette) : carte à gauche, largeur
            // d'un téléphone, la carte reste visible.
            child: Align(
              alignment: Alignment.bottomLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    BoutonRondVerre(
                      icon: Icons.my_location_rounded,
                      tooltip: 'Me localiser',
                      onTap: () => _localiserPuisCentrer(demander: true),
                    ),
                    const SizedBox(height: 12),
                    ListenableBuilder(
                      listenable: _motos,
                      builder: (context, _) => _CarteDestination(
                        motos: _motos.proximite,
                        chargement: _motos.chargement,
                        onRechercher: () => context.push(AppRoutes.clientPassager),
                        onColis: () => context.push(AppRoutes.clientColis),
                        bannieres: widget.bannieres,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Position du client : point vert cerclé de blanc, avec halo.
class _PointMoi extends StatelessWidget {
  const _PointMoi();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Votre position',
      child: Center(
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: AppColors.vert.withValues(alpha: 0.22), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: AppColors.vert,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4)],
            ),
          ),
        ),
      ),
    );
  }
}

class _CarteDestination extends StatelessWidget {
  const _CarteDestination({
    required this.motos,
    required this.chargement,
    required this.onRechercher,
    required this.onColis,
    required this.bannieres,
  });

  final Proximite motos;
  final bool chargement;
  final VoidCallback onRechercher;
  final VoidCallback onColis;
  final List<BanniereProm> bannieres;

  String get _disponibilite {
    final n = motos.motos.length;
    if (n == 0) return 'Aucune moto disponible ici pour le moment';
    final approche = motos.approcheMinutes == null ? '' : ' · environ ${motos.approcheMinutes} min';
    return '${n == 1 ? '1 moto disponible' : '$n motos disponibles'} à proximité$approche';
  }

  void _surBanniere(ActionBanniere action) {
    switch (action) {
      case ActionBanniere.colis:
        onColis();
      case ActionBanniere.course:
        onRechercher();
      case ActionBanniere.aucune:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CarteVerre(
      sombre: true,
      rayon: 32,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Bandeau promo au-dessus de la recherche, court : un maximum de carte reste visible.
          if (bannieres.isNotEmpty) ...[
            BandeauPromo(bannieres: bannieres, surAction: _surBanniere),
            const SizedBox(height: 14),
          ],
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text(
              'Où allez-vous ?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppColors.texte),
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            button: true,
            label: 'Rechercher une destination',
            child: InkWell(
              onTap: onRechercher,
              borderRadius: BorderRadius.circular(22),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 15, 8, 15),
                decoration: BoxDecoration(
                  color: AppColors.verre,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.bordVerre),
                ),
                child: Row(
                  children: [
                    Container(
                      key: const ValueKey('point-accent'),
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: AppColors.vert,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: AppColors.vert.withValues(alpha: 0.35), blurRadius: 0, spreadRadius: 4)],
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Rechercher une destination',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15.5, color: AppColors.texteDiscret, fontWeight: FontWeight.w500),
                      ),
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(color: AppColors.vert, shape: BoxShape.circle),
                      child: const Icon(Icons.arrow_forward_rounded, color: AppColors.onyx, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Service(
                  icone: Icons.two_wheeler_outlined,
                  titre: 'Course moto',
                  sousTitre: 'Tiak-tiak',
                  onTap: onRechercher,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Service(
                  icone: Icons.inventory_2_outlined,
                  titre: 'Colis',
                  sousTitre: 'Express',
                  onTap: onColis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(width: 4),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: motos.motos.isEmpty ? AppColors.texteDiscret.withValues(alpha: 0.5) : AppColors.vert,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  chargement ? 'Recherche des motos à proximité…' : _disponibilite,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.texteDiscret, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Service (Course moto, Colis) : pictogramme vert dans une pastille verte
/// très sombre, sur verre translucide.
class _Service extends StatelessWidget {
  const _Service({required this.icone, required this.titre, required this.sousTitre, required this.onTap});

  final IconData icone;
  final String titre;
  final String sousTitre;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.verre,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.bordVerre),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: AppColors.vertTeinte, borderRadius: BorderRadius.circular(12)),
              child: Icon(icone, color: AppColors.vert, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.texte),
                  ),
                  Text(
                    sousTitre,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.texteDiscret),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
