import 'package:flutter/material.dart';
import '../../../../core/maps/navigation_gps.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../courses/data/course_service.dart';

/// Choix de l'application de guidage (Google Maps ou Waze).
Future<AppNavigation?> choisirAppNavigation(BuildContext context, {required String destination}) {
  return showModalBottomSheet<AppNavigation>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: const BoxDecoration(
        color: AppColors.carte,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Naviguer avec…', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(destination, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.texteDiscret)),
          const SizedBox(height: 16),
          for (final (app, libelle, icone) in const [
            (AppNavigation.googleMaps, 'Google Maps', Icons.map_rounded),
            (AppNavigation.waze, 'Waze', Icons.navigation_rounded),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FilledButton.icon(
                onPressed: () => Navigator.of(sheetContext).pop(app),
                icon: Icon(icone),
                label: Text(libelle, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.vert,
                  foregroundColor: AppColors.onyx,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Confirmation d'annulation par le chauffeur, avec motif obligatoire.
/// Retourne le motif choisi ([MotifAnnulation]) ou `null` s'il renonce.
Future<String?> demanderMotifAnnulation(BuildContext context) {
  return showDialog<String>(context: context, builder: (_) => const _DialogAnnulation());
}

class _DialogAnnulation extends StatefulWidget {
  const _DialogAnnulation();

  @override
  State<_DialogAnnulation> createState() => _DialogAnnulationState();
}

class _DialogAnnulationState extends State<_DialogAnnulation> {
  String? _motif;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Annuler la course ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Le client sera prévenu avec le motif choisi. Vous pourrez ensuite recevoir de nouvelles demandes.',
            style: TextStyle(fontSize: 13, color: AppColors.texteDiscret, height: 1.4),
          ),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _motif,
            onChanged: (motif) => setState(() => _motif = motif),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final motif in MotifAnnulation.tous)
                  RadioListTile<String>(
                    value: motif,
                    title: Text(MotifAnnulation.libelle(motif)),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Continuer la course')),
        FilledButton(
          onPressed: _motif == null ? null : () => Navigator.of(context).pop(_motif),
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          child: const Text('Annuler la course'),
        ),
      ],
    );
  }
}
