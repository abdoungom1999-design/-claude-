import 'package:flutter/material.dart';

/// Point d'entrée du flux "Passager" (course moto-taxi).
/// Formulaire de réservation à implémenter dans une itération ultérieure.
class PassagerPage extends StatelessWidget {
  const PassagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Réserver une course')),
      body: const Center(child: Text('Flux Passager - à venir')),
    );
  }
}
