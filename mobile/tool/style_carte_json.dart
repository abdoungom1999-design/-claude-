// Écrit le style « Sprint clair » en JSON dans le fichier donné, pour que
// la CI le fasse valider par Google (Map Tiles API) exactement tel que
// l'app l'envoie. Usage : dart run tool/style_carte_json.dart style.json
import 'dart:convert';
import 'dart:io';

// ignore: avoid_relative_lib_imports
import '../lib/core/maps/style_sprint_clair.dart';

void main(List<String> arguments) => File(arguments.single).writeAsStringSync(jsonEncode(styleSprintClair));
