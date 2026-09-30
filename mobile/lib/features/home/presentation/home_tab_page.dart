import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/location/localiser.dart';
import '../../../core/maps/distance_utils.dart';
import '../../../core/maps/fond_carte.dart';
import '../../../core/maps/motos_proches_controller.dart';
import '../../../core/maps/proximite_service.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/logo_sprint.dart';
import '../../../core/widgets/moto_vue_dessus.dart';
import '../../compte/presentation/mes_notifications_page.dart';

/// Onglet Accueil : carte « Sprint clair » en plein écran avec les motos
/// disponibles alentour (anonymes, positions arrondies à 150 m par le
/// serveur), et une carte flottante « Où allez-vous ? ».
class HomeTabPage extends StatefulWidget {
  const HomeTabPage({super.key, this.proximite, this.localiser, this.fond, this.coucheFond});

  /// Injectables pour les tests ; par défaut selon Firebase (démo sinon).
  final ProximiteService? proximite;
  final Localiser? localiser;
  final FondCarte? fond;

  /// Fond de carte ; par défaut les images Google « Sprint clair » (ou
  /// OpenStreetMap). Les tests le remplacent (pas de réseau).
  final Widget? coucheFond;

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
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _carte,
              options: MapOptions(
                initialCenter: HomeTabPage.centreDakar,
                initialZoom: 14.5,
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
                  padding: const EdgeInsets.only(bottom: 250),
                  child: MentionsFondCarte(fond: widget.fond),
                ),
              ],
            ),
          ),
          // Voile en haut : lisibilité des boutons sur n'importe quel fond.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 120,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.background.withValues(alpha: 0.85), AppColors.background.withValues(alpha: 0)],
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    const _Logo(),
                    const Spacer(),
                    _BoutonRond(
                      icon: Icons.notifications_outlined,
                      tooltip: 'Notifications',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const MesNotificationsPage()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _BoutonRond(
                      icon: Icons.person_outline_rounded,
                      tooltip: 'Mon compte',
                      onTap: () => context.go(AppRoutes.compteTab),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
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
                    _BoutonRond(
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

const _ombreDouce = [
  BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, 8)),
  BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 1)),
];

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: _ombreDouce,
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LogoSprint(taille: 30),
          SizedBox(width: 8),
          Text('Sprint', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
        ],
      ),
    );
  }
}

class _BoutonRond extends StatelessWidget {
  const _BoutonRond({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: _ombreDouce),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 20, color: AppColors.text)),
          ),
        ),
      ),
    );
  }
}

/// Position du client : point bleu cerclé de blanc, avec halo.
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
          decoration: BoxDecoration(color: const Color(0xFF1A73E8).withValues(alpha: 0.15), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: const Color(0xFF1A73E8),
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
  });

  final Proximite motos;
  final bool chargement;
  final VoidCallback onRechercher;
  final VoidCallback onColis;

  String get _disponibilite {
    final n = motos.motos.length;
    if (n == 0) return 'Aucune moto disponible ici pour le moment';
    final approche = motos.approcheMinutes == null ? '' : ' · environ ${motos.approcheMinutes} min';
    return '${n == 1 ? '1 moto disponible' : '$n motos disponibles'} à proximité$approche';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: _ombreDouce,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text(
              'Où allez-vous ?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3),
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            button: true,
            label: 'Rechercher une destination',
            child: InkWell(
              onTap: onRechercher,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(color: AppColors.greyLight, borderRadius: BorderRadius.circular(14)),
                child: const Row(
                  children: [
                    Icon(Icons.search_rounded, color: AppColors.text, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Rechercher une destination',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, color: AppColors.grey, fontWeight: FontWeight.w500),
                      ),
                    ),
                    Icon(Icons.arrow_forward_rounded, color: AppColors.grey, size: 18),
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
                  icone: Icons.two_wheeler_rounded,
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
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: motos.motos.isEmpty ? AppColors.grey : AppColors.vert,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  chargement ? 'Recherche des motos à proximité…' : _disponibilite,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.grey, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.greyBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: AppColors.orangeLight, borderRadius: BorderRadius.circular(10)),
              child: Icon(icone, color: AppColors.orange, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titre, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  Text(
                    sousTitre,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
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
