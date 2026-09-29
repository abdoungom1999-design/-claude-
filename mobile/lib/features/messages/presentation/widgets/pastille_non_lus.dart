import 'package:flutter/material.dart';
import '../../data/messages_non_lus.dart';

/// Pastille rouge avec le nombre de messages non lus, posée sur l'icône
/// [child] (onglet Messages, bouton "Discuter"...). Invisible à zéro.
class PastilleNonLus extends StatelessWidget {
  const PastilleNonLus({super.key, required this.nombre, required this.child});

  final int nombre;
  final Widget child;

  static const rouge = Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    if (nombre <= 0) return child;
    return Semantics(
      label: nombre == 1 ? '1 message non lu' : '$nombre messages non lus',
      child: Badge(
        label: Text(
          libelleNonLus(nombre),
          style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800),
        ),
        backgroundColor: rouge,
        offset: const Offset(6, -6),
        child: child,
      ),
    );
  }
}
