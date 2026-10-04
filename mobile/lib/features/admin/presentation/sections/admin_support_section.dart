import 'package:flutter/material.dart';
import '../../../../core/demo/admin_demo_data.dart';
import '../../../support/data/support_service.dart' as support;
import '../admin_ticket_page.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../firebase_options.dart';

/// Page "Support" : file des signalements clients ("Signaler un
/// problème" depuis l'historique), en temps réel. Chaque ticket ouvre
/// [AdminTicketPage] : fiche de la course, conversation, remboursement,
/// suspension du chauffeur. En mode démo : tickets de la maquette.
class AdminSupportSection extends StatelessWidget {
  const AdminSupportSection({super.key, this.demo, this.service, this.ouvrirTicket});

  /// Force la version démo ou réelle (tests) ; par défaut, selon Firebase.
  final bool? demo;

  /// Injectables pour les tests.
  final support.SupportService? service;
  final void Function(BuildContext context, String courseId)? ouvrirTicket;

  @override
  Widget build(BuildContext context) {
    if (!(demo ?? !DefaultFirebaseOptions.estConfigure)) {
      return _FileTickets(service: service ?? support.SupportService(), ouvrirTicket: ouvrirTicket);
    }
    final tickets = AdminDemoData.tickets();
    final ouverts = tickets.where((t) => t.statut != StatutTicket.resolu).length;

    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Tickets support',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              Text(
                '$ouverts en attente de traitement',
                style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (final ticket in tickets)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.fondClair,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ticket.sujet,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Client : ${ticket.client}',
                            style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
                          ),
                        ],
                      ),
                    ),
                    _BadgeTicket(statut: ticket.statut),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BadgeTicket extends StatelessWidget {
  const _BadgeTicket({required this.statut});

  final StatutTicket statut;

  @override
  Widget build(BuildContext context) {
    final (label, couleur) = switch (statut) {
      StatutTicket.ouvert => ('Ouvert', Colors.redAccent),
      StatutTicket.enCours => ('En cours', AppColors.bleu),
      StatutTicket.resolu => ('Résolu', AppColors.onyx),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: couleur, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

enum _Filtre { aTraiter, resolus, tous }

class _FileTickets extends StatefulWidget {
  const _FileTickets({required this.service, this.ouvrirTicket});

  final support.SupportService service;
  final void Function(BuildContext context, String courseId)? ouvrirTicket;

  @override
  State<_FileTickets> createState() => _FileTicketsState();
}

class _FileTicketsState extends State<_FileTickets> {
  late final Stream<List<support.TicketSupport>> _tickets = widget.service.streamTickets();
  _Filtre _filtre = _Filtre.aTraiter;

  void _ouvrir(String courseId) {
    final ouvrir = widget.ouvrirTicket;
    if (ouvrir != null) {
      ouvrir(context, courseId);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminTicketPage(courseId: courseId)));
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: StreamBuilder<List<support.TicketSupport>>(
        stream: _tickets,
        builder: (context, instantane) {
          if (instantane.hasError) {
            return const Text('Impossible de charger les tickets.', style: TextStyle(color: AppColors.grey));
          }
          if (!instantane.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator(color: AppColors.bleu)),
            );
          }
          final tous = instantane.data!;
          final aTraiter = tous.where((t) => !t.estResolu).length;
          final nonLus = tous.where((t) => t.nonLuAdmin).length;
          final affiches = [
            for (final t in tous)
              if (_filtre == _Filtre.tous ||
                  (_filtre == _Filtre.aTraiter && !t.estResolu) ||
                  (_filtre == _Filtre.resolus && t.estResolu))
                t,
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Tickets support', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(
                    '$aTraiter à traiter${nonLus > 0 ? ' · $nonLus non lu(s)' : ''}',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: [
                  for (final (filtre, libelle) in [
                    (_Filtre.aTraiter, 'À traiter'),
                    (_Filtre.resolus, 'Résolus'),
                    (_Filtre.tous, 'Tous'),
                  ])
                    ChoiceChip(
                      label: Text(libelle),
                      selected: _filtre == filtre,
                      selectedColor: AppColors.bleuClair,
                      onSelected: (_) => setState(() => _filtre = filtre),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (affiches.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('Aucun ticket dans cette liste.', style: TextStyle(fontSize: 13, color: AppColors.grey)),
                  ),
                )
              else
                for (final ticket in affiches)
                  _LigneTicket(ticket: ticket, onTap: () => _ouvrir(ticket.courseId)),
            ],
          );
        },
      ),
    );
  }
}

class _LigneTicket extends StatelessWidget {
  const _LigneTicket({required this.ticket, required this.onTap});

  final support.TicketSupport ticket;
  final VoidCallback onTap;

  String _depuis(DateTime d) {
    final ecart = DateTime.now().difference(d);
    if (ecart.inMinutes < 1) return "à l'instant";
    if (ecart.inHours < 1) return 'il y a ${ecart.inMinutes} min';
    if (ecart.inDays < 1) return 'il y a ${ecart.inHours} h';
    return 'il y a ${ecart.inDays} j';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: ticket.nonLuAdmin ? AppColors.bleuClair.withValues(alpha: 0.5) : AppColors.fondClair,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                  ticket.categorie == support.CategorieTicket.securite ? Icons.warning_amber_rounded : Icons.support_agent_rounded,
                  color: ticket.categorie == support.CategorieTicket.securite ? Colors.redAccent : AppColors.bleu,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              ticket.estDemandeAide
                                  ? "Aide ${ticket.demandeur == 'conducteur' ? 'chauffeur' : 'client'} · "
                                      '${support.CategorieTicket.libelle(ticket.categorie)}'
                                  : support.CategorieTicket.libelle(ticket.categorie),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                            ),
                          ),
                          if (ticket.nonLuAdmin) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.bleu, borderRadius: BorderRadius.circular(8)),
                              child: const Text('Nouveau',
                                  style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        ticket.dernierMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_depuis(ticket.majLe), style: const TextStyle(fontSize: 11.5, color: AppColors.grey)),
                    const SizedBox(height: 4),
                    Text(
                      ticket.estResolu ? 'Résolu' : 'À traiter',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: ticket.estResolu ? AppColors.onyx : AppColors.bleuFonce,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
