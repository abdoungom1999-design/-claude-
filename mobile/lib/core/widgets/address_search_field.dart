import 'dart:async';

import 'package:flutter/material.dart';
import '../maps/geocoding_service.dart';
import '../theme/app_colors.dart';
import 'app_text_field.dart';

/// Champ d'adresse avec autocomplétion géocodée (Nominatim/OSM). La
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
    this.prefixIcon,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<AdresseSuggestion> onSelected;
  final IconData? prefixIcon;

  @override
  State<AddressSearchField> createState() => _AddressSearchFieldState();
}

class _AddressSearchFieldState extends State<AddressSearchField> {
  final _geocodingService = GeocodingService();
  Timer? _debounce;
  List<AdresseSuggestion> _suggestions = [];
  bool _recherche = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _surChangement(String texte) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 500),
      () => _rechercher(texte),
    );
  }

  Future<void> _rechercher(String texte) async {
    if (texte.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    setState(() => _recherche = true);
    final resultats = await _geocodingService.rechercher(texte);
    if (!mounted) return;
    setState(() {
      _suggestions = resultats;
      _recherche = false;
    });
  }

  void _selectionner(AdresseSuggestion suggestion) {
    widget.controller.text = suggestion.libelle;
    setState(() => _suggestions = []);
    widget.onSelected(suggestion);
    FocusScope.of(context).unfocus();
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
          validator: (valeur) => (valeur == null || valeur.trim().isEmpty)
              ? 'Adresse requise'
              : null,
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
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.greyBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _suggestions.map((suggestion) {
                return ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.location_on_outlined,
                    color: AppColors.grey,
                    size: 20,
                  ),
                  title: Text(
                    suggestion.libelle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  onTap: () => _selectionner(suggestion),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
