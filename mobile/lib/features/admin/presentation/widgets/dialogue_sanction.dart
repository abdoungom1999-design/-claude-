import 'package:flutter/material.dart';
import '../../../../core/models/statut_compte.dart';
import '../../../../core/theme/app_colors.dart';

/// Confirmation d'une suspension ou d'un bannissement, avec son motif
/// (obligatoire, gardé dans le journal Admin). Renvoie le motif, ou
/// `null` si l'Admin renonce.
Future<String?> demanderMotifSanction(BuildContext context, {required String nom, required String statut}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _DialogueSanction(nom: nom, statut: statut),
  );
}

class _DialogueSanction extends StatefulWidget {
  const _DialogueSanction({required this.nom, required this.statut});

  final String nom;
  final String statut;

  @override
  State<_DialogueSanction> createState() => _DialogueSanctionState();
}

class _DialogueSanctionState extends State<_DialogueSanction> {
  final _motif = TextEditingController();
  bool _manquant = false;

  bool get _bannir => widget.statut == StatutCompte.banni;

  String get _explication => _bannir
      ? "Le compte est déconnecté immédiatement et ne pourra plus jamais accéder à l'application. "
          "Cette décision n'est pas réversible depuis le panneau Admin. Une course en cours est annulée "
          'et le client remboursé.'
      : 'Le compte est déconnecté immédiatement et ne peut plus se connecter jusqu\'à sa réactivation. '
          'Une course en cours est annulée et le client remboursé.';

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  void _confirmer() {
    final motif = _motif.text.trim();
    if (motif.isEmpty) {
      setState(() => _manquant = true);
      return;
    }
    Navigator.of(context).pop(motif);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_bannir ? 'Bannir ${widget.nom} ?' : 'Suspendre ${widget.nom} ?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_explication),
            const SizedBox(height: 16),
            TextField(
              controller: _motif,
              maxLength: 300,
              maxLines: 2,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Motif (gardé dans le journal)',
                errorText: _manquant ? 'Indiquez le motif.' : null,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: _confirmer,
          style: FilledButton.styleFrom(backgroundColor: _bannir ? Colors.red.shade700 : AppColors.orange),
          child: Text(_bannir ? 'Bannir définitivement' : 'Suspendre'),
        ),
      ],
    );
  }
}
