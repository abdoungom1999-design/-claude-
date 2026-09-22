import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/secondary_button.dart';
import '../../../core/widgets/status_badge.dart';

/// Maquette de l'écran affiché au conducteur lors de la réception d'une
/// nouvelle demande de course, avec compte à rebours pour accepter/refuser.
/// Données d'exemple uniquement : aucune connexion API à ce stade.
class CourseAlertPage extends StatefulWidget {
  const CourseAlertPage({super.key});

  @override
  State<CourseAlertPage> createState() => _CourseAlertPageState();
}

class _CourseAlertPageState extends State<CourseAlertPage> {
  static const int _dureeTotaleSecondes = 15;
  int _secondesRestantes = _dureeTotaleSecondes;
  Timer? _minuteur;

  @override
  void initState() {
    super.initState();
    _minuteur = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondesRestantes <= 1) {
        _minuteur?.cancel();
        if (mounted) Navigator.of(context).maybePop();
        return;
      }
      setState(() => _secondesRestantes--);
    });
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 8),
              const Text(
                'Nouvelle course !',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
              _CompteARebours(
                secondesRestantes: _secondesRestantes,
                dureeTotale: _dureeTotaleSecondes,
              ),
              const SizedBox(height: 32),
              const AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        StatusBadge(label: 'Passager', tone: StatusTone.actif),
                        Text(
                          '~ 1 200 FCFA',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    _LigneAdresse(
                      icone: Icons.my_location,
                      texte: 'Plateau, Dakar',
                    ),
                    SizedBox(height: 10),
                    _LigneAdresse(
                      icone: Icons.location_on_outlined,
                      texte: 'Almadies, Dakar',
                    ),
                    SizedBox(height: 10),
                    _LigneAdresse(
                      icone: Icons.social_distance_outlined,
                      texte: '~ 6,4 km · 18 min',
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: 'Refuser',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrimaryButton(
                      label: 'Accepter',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompteARebours extends StatelessWidget {
  const _CompteARebours({
    required this.secondesRestantes,
    required this.dureeTotale,
  });

  final int secondesRestantes;
  final int dureeTotale;

  @override
  Widget build(BuildContext context) {
    final progression = secondesRestantes / dureeTotale;

    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: CircularProgressIndicator(
              value: progression,
              strokeWidth: 8,
              backgroundColor: AppColors.greyLight,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.orange,
              ),
            ),
          ),
          Text(
            '$secondesRestantes',
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _LigneAdresse extends StatelessWidget {
  const _LigneAdresse({required this.icone, required this.texte});

  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icone, size: 18, color: AppColors.grey),
        const SizedBox(width: 10),
        Expanded(
          child: Text(texte, style: const TextStyle(fontSize: 14)),
        ),
      ],
    );
  }
}
