import 'package:flutter/material.dart';

/// Point d'entrée du flux "Livraison Colis".
/// Formulaire d'envoi de colis à implémenter dans une itération ultérieure.
class ColisPage extends StatelessWidget {
  const ColisPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Envoyer un colis')),
      body: const Center(child: Text('Flux Livraison Colis - à venir')),
    );
  }
}
