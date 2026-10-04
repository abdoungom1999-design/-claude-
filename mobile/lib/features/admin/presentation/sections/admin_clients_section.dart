import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../core/demo/admin_demo_data.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format_fcfa.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../firebase_options.dart';
import '../../../finances/data/comptabilite.dart';
import '../../data/pilotage_service.dart';
import '../admin_portefeuille_page.dart';

/// Page "Clients". En Firebase réel : tous les comptes clients inscrits
/// depuis l'application (`users`, `role == 'client'`), en temps réel,
/// avec leurs courses terminées et le montant dépensé ; recherche par
/// nom, téléphone ou email. En mode démo : [AdminDemoData].
class AdminClientsSection extends StatelessWidget {
  const AdminClientsSection({super.key, this.service});

  /// Injectable pour les tests.
  final PilotageService? service;

  @override
  Widget build(BuildContext context) {
    if (!DefaultFirebaseOptions.estConfigure && service == null) return const _ClientsDemo();
    return _ClientsReels(service: service ?? PilotageService());
  }
}

class _ClientsReels extends StatefulWidget {
  const _ClientsReels({required this.service});

  final PilotageService service;

  @override
  State<_ClientsReels> createState() => _ClientsReelsState();
}

class _ClientsReelsState extends State<_ClientsReels> {
  final _abonnements = <StreamSubscription<Object?>>[];
  List<UtilisateurAdmin>? _clients;
  List<LigneCourse> _terminees = const [];
  Object? _erreur;
  String _recherche = '';

  @override
  void initState() {
    super.initState();
    _suivre(widget.service.streamUtilisateurs('client'), (v) => _clients = v);
    _suivre(widget.service.streamCoursesTerminees(), (v) => _terminees = v);
  }

  void _suivre<T>(Stream<T> flux, void Function(T valeur) maj) {
    _abonnements.add(flux.listen(
      (valeur) {
        if (mounted) setState(() => maj(valeur));
      },
      onError: (Object e) {
        if (mounted) setState(() => _erreur = e);
      },
    ));
  }

  @override
  void dispose() {
    for (final a in _abonnements) {
      a.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_erreur != null) {
      return const AppCard(
        child: Text(
          'Lecture impossible. Vérifiez que vous êtes connecté avec le compte Admin '
          'et que les règles Firestore sont publiées.',
          style: TextStyle(color: AppColors.grey),
        ),
      );
    }
    final clients = _clients;
    if (clients == null) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator(color: AppColors.bleu)),
      );
    }

    final courses = <String, int>{};
    final depenses = <String, int>{};
    for (final c in _terminees) {
      courses[c.clientId] = (courses[c.clientId] ?? 0) + 1;
      depenses[c.clientId] = (depenses[c.clientId] ?? 0) + c.prixFcfa;
    }

    final recherche = _recherche.trim().toLowerCase();
    final affiches = [
      for (final c in clients)
        if (recherche.isEmpty ||
            c.nom.toLowerCase().contains(recherche) ||
            c.telephone.contains(recherche) ||
            c.email.toLowerCase().contains(recherche))
          c,
    ]..sort((a, b) {
        // Les plus récents d'abord ; comptes sans date à la fin.
        if (a.creeLe == null) return b.creeLe == null ? a.nom.compareTo(b.nom) : 1;
        if (b.creeLe == null) return -1;
        return b.creeLe!.compareTo(a.creeLe!);
      });

    const entete = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.grey);

    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Tous les clients', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              Text(
                clients.length > 1 ? '${clients.length} inscrits' : '${clients.length} inscrit',
                style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
              ),
              const Spacer(),
              SizedBox(
                width: 300,
                child: TextField(
                  onChanged: (v) => setState(() => _recherche = v),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 19),
                    hintText: 'Nom, téléphone ou email',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Row(
            children: [
              Expanded(flex: 3, child: Text('Client', style: entete)),
              Expanded(flex: 2, child: Text('Téléphone', style: entete)),
              SizedBox(width: 90, child: Text('Courses', style: entete)),
              SizedBox(width: 120, child: Text('Dépensé', style: entete)),
              SizedBox(width: 110, child: Text('Inscrit le', style: entete)),
              SizedBox(width: 48),
            ],
          ),
          const Divider(height: 24, color: AppColors.greyBorder),
          if (affiches.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                clients.isEmpty ? 'Aucun client inscrit pour le moment.' : 'Aucun client ne correspond à la recherche.',
                style: const TextStyle(color: AppColors.grey),
              ),
            ),
          for (final client in affiches)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(client.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (client.email.isNotEmpty)
                          Text(
                            client.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(client.telephone.isEmpty ? '—' : client.telephone, style: const TextStyle(fontSize: 13)),
                  ),
                  SizedBox(width: 90, child: Text('${courses[client.id] ?? 0}', style: const TextStyle(fontSize: 13))),
                  SizedBox(
                    width: 120,
                    child: Text(formaterFcfa(depenses[client.id] ?? 0), style: const TextStyle(fontSize: 13)),
                  ),
                  SizedBox(
                    width: 110,
                    child: Text(
                      client.creeLe == null ? '—' : _date(client.creeLe!),
                      style: const TextStyle(fontSize: 13, color: AppColors.grey),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: IconButton(
                      key: ValueKey('portefeuille-${client.id}'),
                      tooltip: 'Portefeuille',
                      icon: const Icon(Icons.account_balance_wallet_outlined, size: 20),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => AdminPortefeuillePage(clientId: client.id, nomClient: client.nom),
                      )),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _date(DateTime date) {
    final d = date.toUtc();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}

/// Version démo (sans Firebase), inchangée.
class _ClientsDemo extends StatelessWidget {
  const _ClientsDemo();

  @override
  Widget build(BuildContext context) {
    final clients = AdminDemoData.clients();

    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Tous les clients',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              Text(
                '${clients.length} client(s)',
                style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  'Client',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.grey),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'Téléphone',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.grey),
                ),
              ),
              SizedBox(
                width: 110,
                child: Text(
                  'Courses',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.grey),
                ),
              ),
              SizedBox(
                width: 120,
                child: Text(
                  'Inscrit le',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.grey),
                ),
              ),
            ],
          ),
          const Divider(height: 24, color: AppColors.greyBorder),
          for (final client in clients)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(client.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Expanded(flex: 2, child: Text(client.telephone, style: const TextStyle(fontSize: 13))),
                  SizedBox(width: 110, child: Text('${client.coursesTotal}', style: const TextStyle(fontSize: 13))),
                  SizedBox(
                    width: 120,
                    child: Text(
                      client.inscritLe,
                      style: const TextStyle(fontSize: 13, color: AppColors.grey),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
