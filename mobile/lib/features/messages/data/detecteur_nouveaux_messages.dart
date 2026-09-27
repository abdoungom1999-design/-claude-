import 'chat_service.dart';

/// Repère, dans le flux du dernier message d'une conversation
/// ([ChatService.streamDernierMessage]), ceux de l'interlocuteur que
/// l'utilisateur n'a pas encore lus — pour afficher un badge et une
/// alerte au chauffeur qui n'a pas le chat ouvert.
class DetecteurNouveauxMessages {
  DetecteurNouveauxMessages({required this.interlocuteurUid});

  final String interlocuteurUid;
  String? _dernierId;
  bool _premiereReception = true;
  bool _nonLu = false;

  /// Un message de l'interlocuteur attend d'être lu.
  bool get nonLu => _nonLu;

  /// À appeler à chaque émission du flux. Retourne `true` s'il faut
  /// alerter : message de l'interlocuteur arrivé pendant l'écoute. Un
  /// message déjà là à l'ouverture compte comme non lu, sans alerte ;
  /// ses propres messages et les réémissions du même message sont
  /// ignorés.
  bool recevoir(ChatMessageFirestore? message) {
    final premiere = _premiereReception;
    _premiereReception = false;
    if (message == null || message.id == _dernierId) return false;
    _dernierId = message.id;
    if (message.senderId != interlocuteurUid) return false;
    _nonLu = true;
    return !premiere;
  }

  void marquerLu() => _nonLu = false;
}
