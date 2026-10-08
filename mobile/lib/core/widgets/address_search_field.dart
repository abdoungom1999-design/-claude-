import 'dart:async';

import 'package:flutter/material.dart';
import '../maps/geocoding_service.dart';
import '../theme/app_colors.dart';
import 'app_text_field.dart';

/// Champ d'adresse avec autocomplétion (Google Places en Firebase réel,
/// Nominatim/OSM en démo ou en secours, voir [ServiceAdresses]). La
/// sélection d'une suggestion résout l'adresse en coordonnées GPS
/// nécessaires pour créer une course ; tant qu'aucune suggestion n'est
/// choisie, [onSelected] n'a pas été appelé et l'appelant ne dispose pas
/// de coordonnées valides.
class AddressSearchField extends StatefulWidget {
  const AddressSearchField({
    super.key,
    required this.label,
    required this.controller,
    required this.onSelected,
    this.onEdited,
    this.prefixIcon,
    this.service,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<AdresseSuggestion> onSelected;

  /// Appelé dès que l'utilisateur modifie le texte à la main : l'adresse
  /// précédemment choisie ne correspond plus, l'appelant doit l'oublier.
  final VoidCallback? onEdited;
  final IconData? prefixIcon;

  /// Injectable pour les tests ; par défaut [ServiceAdresses.parDefaut].
  final ServiceAdresses? service;

  @override
  State<AddressSearchField> createState() => _AddressSearchFieldState();
}

class _AddressSearchFieldState extends State<AddressSearchField> {
  late final ServiceAdresses _service = widget.service ?? ServiceAdresses.parDefaut();
  Timer? _debounce;
  List<PropositionAdresse> _suggestions = [];
  bool _recherche = false;
  String? _erreur;

  /// Numéro de la dernière recherche : une réponse plus ancienne, arrivée
  /// en retard, n'écrase pas les suggestions du texte actuel.
  int _demande = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _surChangement(String texte) {
    widget.onEdited?.call();
    if (_erreur != null) setState(() => _erreur = null);
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 500),
      () => _rechercher(texte),
    );
  }

  Future<void> _rechercher(String texte) async {
    final demande = ++_demande;
    if (texte.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    setState(() => _recherche = true);
    final resultats = await _service.rechercher(texte);
    if (!mounted || demande != _demande) return;
    setState(() {
      _suggestions = resultats;
      _recherche = false;
    });
  }

  Future<void> _selectionner(PropositionAdresse proposition) async {
    _demande++;
    _debounce?.cancel();
    widget.controller.text = proposition.libelle;
    FocusScope.of(context).unfocus();
    setState(() {
      _suggestions = [];
      _recherche = true;
    });
    try {
      final adresse = await _service.resoudre(proposition);
      if (!mounted) return;
      setState(() => _recherche = false);
      widget.onSelected(adresse);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recherche = false;
        _erreur = 'Adresse introuvable. Choisissez-en une autre dans la liste.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          label: widget.label,
          controller: widget.controller,
          prefixIcon: widget.prefixIcon,
          onChanged: _surChangement,
          validator: (valeur) => (valeur == null || valeur.trim().isEmpty) ? 'Adresse requise' : null,
          suffixIcon: _recherche
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
        ),
        if (_suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            // Material (et non un simple fond décoré) : l'effet au toucher
            // des suggestions reste visible.
            child: Material(
              color: AppColors.carteHaute,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.bord),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _suggestions.map((suggestion) {
                  return ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.location_on_outlined,
                      color: AppColors.texteDiscret,
                      size: 20,
                    ),
                    title: Text(
                      suggestion.principal,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    subtitle: suggestion.secondaire.isEmpty
                        ? null
                        : Text(
                            suggestion.secondaire,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppColors.texteDiscret),
                          ),
                    onTap: () => _selectionner(suggestion),
                  );
                }).toList(),
              ),
            ),
          ),
        if (_erreur != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(_erreur!, style: const TextStyle(fontSize: 12.5, color: AppColors.danger)),
          ),
      ],
    );
  }
}
