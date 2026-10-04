import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_fcfa.dart';
import '../../../core/widgets/app_card.dart';
import '../../client/presentation/suivi_course_page.dart';
import '../../courses/data/course_service.dart';
import '../../support/data/support_service.dart';
import '../../support/presentation/signalement_page.dart';
import '../../../core/widgets/onyx_light.dart';

/// Détail d'une course de l'historique (tient lieu de reçu) : trajet,
/// prix, paiement, remboursement éventuel, et accès au support
/// ("Signaler un problème", ou le signalement déjà ouvert).
class DetailCoursePage extends StatefulWidget {
  const DetailCoursePage({super.key, required this.course, required this.clientId, this.supportService});

  final CourseFirestore course;
  final String clientId;

  /// Injectable pour les tests.
  final SupportService? supportService;

  @override
  State<DetailCoursePage> createState() => _DetailCoursePageState();
}

class _DetailCoursePageState extends State<DetailCoursePage> {
  late final SupportService _support = widget.supportService ?? SupportService();
  late final Stream<TicketSupport?> _ticket = _support.streamTicket(widget.course.id);

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} à '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = widget.course;
    return SousPageOnyx(child: Scaffold(
      appBar: AppBar(title: Text(c.type == 'COLIS' ? 'Livraison de colis' : 'Course moto')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_date(c.timestamp), style: const TextStyle(fontSize: 12.5, color: AppColors.texteDiscret)),
                    _Pastille(texte: c.libelleStatut, active: c.estActive),
                  ],
                ),
                const SizedBox(height: 14),
                _Ligne(icone: Icons.my_location, texte: c.adresseDepart),
                const SizedBox(height: 10),
                _Ligne(icone: Icons.location_on_outlined, texte: c.adresseArrivee),
                const Divider(height: 28, color: AppColors.bordVerre),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(c.libellePaiement, style: const TextStyle(fontSize: 13, color: AppColors.texteDiscret)),
                    Text(formaterFcfa(c.prixFcfa), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ],
                ),
                if (c.rembourseeLe != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Remboursée intégralement le ${_date(c.rembourseeLe!)}.',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.onyx, fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (c.estActive)
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => SuiviCoursePage(courseId: c.id)),
              ),
              icon: const Icon(Icons.navigation_rounded),
              label: const Text('Suivre ma course'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.orange,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          const SizedBox(height: 10),
          StreamBuilder<TicketSupport?>(
            stream: _ticket,
            builder: (context, instantane) {
              final ticket = instantane.data;
              final libelle = ticket == null
                  ? 'Signaler un problème'
                  : ticket.nonLuClient
                      ? 'Nouvelle réponse du support'
                      : 'Voir mon signalement';
              return OutlinedButton.icon(
                onPressed: instantane.connectionState == ConnectionState.waiting && !instantane.hasData
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SignalementPage(
                              course: c,
                              clientId: widget.clientId,
                              service: _support,
                            ),
                          ),
                        ),
                icon: Badge(
                  isLabelVisible: ticket?.nonLuClient ?? false,
                  smallSize: 9,
                  backgroundColor: AppColors.bleu,
                  child: Icon(
                    ticket == null ? Icons.flag_outlined : Icons.support_agent_rounded,
                    color: AppColors.bleu,
                  ),
                ),
                label: Text(libelle),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.onyx,
                  minimumSize: const Size.fromHeight(52),
                  side: const BorderSide(color: AppColors.bordVerre),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              );
            },
          ),
        ],
      ),
    ));
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({required this.icone, required this.texte});

  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 18, color: AppColors.texteDiscret),
        const SizedBox(width: 10),
        Expanded(child: Text(texte, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500))),
      ],
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille({required this.texte, required this.active});

  final String texte;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? AppColors.bleuClair : AppColors.fondClair,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texte,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: active ? AppColors.bleuFonce : AppColors.texteDiscret,
        ),
      ),
    );
  }
}
