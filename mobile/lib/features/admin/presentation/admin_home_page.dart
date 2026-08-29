import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/secondary_button.dart';
import '../../../core/widgets/status_badge.dart';

class _ConducteurDemo {
  _ConducteurDemo({
    required this.nom,
    required this.telephone,
    required this.vehiculeId,
    required this.estValide,
  });

  final String nom;
  final String telephone;
  final String vehiculeId;
  bool estValide;
}

/// Interface Admin de gestion des conducteurs. Données d'exemple
/// uniquement : les actions Valider/Rejeter modifient seulement l'état
/// local de la liste, sans appel API (Phase 3 = design seul).
class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  final List<_ConducteurDemo> _conducteurs = [
    _ConducteurDemo(
      nom: 'Moussa Diop',
      telephone: '+221 77 123 45 67',
      vehiculeId: 'Bajaj Boxer',
      estValide: false,
    ),
    _ConducteurDemo(
      nom: 'Fatou Ndiaye',
      telephone: '+221 78 234 56 78',
      vehiculeId: 'Bajaj Boxer',
      estValide: true,
    ),
    _ConducteurDemo(
      nom: 'Ibrahima Sarr',
      telephone: '+221 76 345 67 89',
      vehiculeId: 'TVS King',
      estValide: false,
    ),
  ];

  void _valider(_ConducteurDemo conducteur) {
    setState(() => conducteur.estValide = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${conducteur.nom} a été validé(e)')),
    );
  }

  void _rejeter(_ConducteurDemo conducteur) {
    setState(() => _conducteurs.remove(conducteur));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${conducteur.nom} a été rejeté(e)')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conducteurs')),
      body: SafeArea(
        child: _conducteurs.isEmpty
            ? Center(
                child: Text(
                  'Aucun conducteur à afficher',
                  style: TextStyle(color: AppColors.grey),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: _conducteurs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final conducteur = _conducteurs[index];
                  return _ConducteurCard(
                    conducteur: conducteur,
                    onValider: () => _valider(conducteur),
                    onRejeter: () => _rejeter(conducteur),
                  );
                },
              ),
      ),
    );
  }
}

class _ConducteurCard extends StatelessWidget {
  const _ConducteurCard({
    required this.conducteur,
    required this.onValider,
    required this.onRejeter,
  });

  final _ConducteurDemo conducteur;
  final VoidCallback onValider;
  final VoidCallback onRejeter;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.greyLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_outline, color: AppColors.grey),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conducteur.nom,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${conducteur.telephone} · ${conducteur.vehiculeId}',
                      style: TextStyle(fontSize: 12, color: AppColors.grey),
                    ),
                  ],
                ),
              ),
              StatusBadge(
                label: conducteur.estValide ? 'Validé' : 'En attente',
                tone: conducteur.estValide
                    ? StatusTone.actif
                    : StatusTone.attention,
              ),
            ],
          ),
          if (!conducteur.estValide) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(label: 'Rejeter', onPressed: onRejeter),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PrimaryButton(label: 'Valider', onPressed: onValider),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
