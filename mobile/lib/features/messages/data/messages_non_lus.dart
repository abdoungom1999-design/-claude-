import 'dart:async';

import 'package:flutter/foundation.dart';
import '../../../core/alertes/alerte_sonore.dart';
import 'chat_service.dart';

/// Messages du chauffeur que le client n'a pas encore lus, pendant sa
/// course en cours.
///
/// Écoute la conversation avec le chauffeur assigné ([suivre], appelé par
/// la coquille du client tant qu'une course est active), donc où que se
/// trouve le client dans l'app (accueil, activité, carte de suivi...) :
/// - [nonLus] alimente les pastilles rouges (onglet Messages, bouton
///   "Discuter", ligne de conversation) ;
/// - chaque nouveau message déclenche [alerte] (son de notification +
///   vibration) et est publié sur [nouveauxMessages] (bandeau
///   "Répondre" de l'écran de suivi) ;
/// - rien de tout cela tant que la conversation est ouverte à l'écran
///   ([conversationOuverte]) : le client voit déjà le message arriver.
///
/// Compte tous les messages du chauffeur reçus depuis la dernière lecture,
/// même si plusieurs arrivent d'un coup (reconnexion) : on compare les
/// identifiants, pas seulement le dernier message. À l'ouverture de l'app,
/// les messages du chauffeur restés sans réponse du client comptent comme
/// non lus, sans son ni vibration (l'app était fermée, le client n'y était
/// pas). Limites : hors de l'app (fermée ou en arrière-plan), il n'y a pas
/// de notification poussée.
class MessagesNonLus extends ChangeNotifier {
  MessagesNonLus({this.alerte = AlerteSonore.nouveauMessage});

  /// Instance de l'application ; les tests créent la leur.
  static final instance = MessagesNonLus();

  /// Son + vibration à la réception (injectable pour les tests).
  final void Function() alerte;

  StreamSubscription<List<ChatMessageFirestore>>? _abonnement;
  final _nouveaux = StreamController<ChatMessageFirestore>.broadcast();
  final _connus = <String>{};
  String? _interlocuteurUid;
  bool _premiere = true;
  bool _ouverte = false;
  bool _detruit = false;
  int _nonLus = 0;
  DateTime? _dernierSon;

  /// Nombre de messages du chauffeur non lus.
  int get nonLus => _nonLus;

  /// Conversation actuellement ouverte à l'écran.
  bool get conversationOuverte => _ouverte;

  /// Chauffeur dont on suit la conversation, `null` hors course.
  String? get interlocuteurUid => _interlocuteurUid;

  /// Chaque message du chauffeur arrivé en direct (pas ceux déjà présents
  /// à l'ouverture), conversation fermée.
  Stream<ChatMessageFirestore> get nouveauxMessages => _nouveaux.stream;

  /// Commence (ou continue, si c'est déjà ce chauffeur) à suivre la
  /// conversation. Appel idempotent.
  void suivre({required ChatService chatService, required String monUid, required String interlocuteurUid}) {
    if (_interlocuteurUid == interlocuteurUid && _abonnement != null) return;
    arreter();
    _interlocuteurUid = interlocuteurUid;
    _premiere = true;
    _abonnement = chatService.streamMessages(chatService.chatIdEntre(monUid, interlocuteurUid)).listen(
          (messages) => _recevoir(messages, monUid, interlocuteurUid),
          onError: (_) {
            // Lecture refusée (course finie) ou réseau : on ne bloque rien,
            // l'écoute reprendra au prochain `suivre`.
          },
        );
  }

  /// Fin de course ou déconnexion : plus de suivi, compteur à zéro.
  void arreter() {
    _abonnement?.cancel();
    _abonnement = null;
    _interlocuteurUid = null;
    _connus.clear();
    final avait = _nonLus != 0;
    _nonLus = 0;
    _ouverte = false;
    // Différé : appelé aussi depuis `dispose` de la coquille.
    if (avait) scheduleMicrotask(_notifier);
  }

  void _notifier() {
    if (!_detruit) notifyListeners();
  }

  /// Le client ouvre la conversation avec [interlocuteurUid] : tout est lu.
  /// Notifie hors de l'arbre de widgets (appelé depuis `initState`).
  void ouvrirConversation(String interlocuteurUid) {
    if (interlocuteurUid != _interlocuteurUid) return;
    _ouverte = true;
    if (_nonLus == 0) return;
    _nonLus = 0;
    scheduleMicrotask(_notifier);
  }

  /// Le client quitte la conversation : ce qu'il a vu est lu. Notifie
  /// hors de l'arbre de widgets (appelé depuis `dispose`).
  void fermerConversation(String interlocuteurUid) {
    if (interlocuteurUid != _interlocuteurUid) return;
    _ouverte = false;
    _nonLus = 0;
    scheduleMicrotask(_notifier);
  }

  void _recevoir(List<ChatMessageFirestore> messages, String monUid, String interlocuteurUid) {
    if (_premiere) {
      _premiere = false;
      _connus.addAll(messages.map((m) => m.id));
      // Restés sans réponse : ceux du chauffeur après le dernier message du client.
      var nonLus = 0;
      for (final m in messages) {
        if (m.senderId == monUid) {
          nonLus = 0;
        } else if (m.senderId == interlocuteurUid) {
          nonLus++;
        }
      }
      _nonLus = _ouverte ? 0 : nonLus;
      notifyListeners();
      return;
    }

    final arrives = [
      for (final m in messages)
        if (_connus.add(m.id) && m.senderId == interlocuteurUid) m,
    ];
    if (arrives.isEmpty) return;
    if (_ouverte) return;
    _nonLus += arrives.length;
    notifyListeners();
    _sonner();
    for (final m in arrives) {
      _nouveaux.add(m);
    }
  }

  /// Un seul signal sonore à la fois, même si plusieurs messages arrivent
  /// ensemble.
  void _sonner() {
    final maintenant = DateTime.now();
    final dernier = _dernierSon;
    if (dernier != null && maintenant.difference(dernier) < const Duration(milliseconds: 1500)) return;
    _dernierSon = maintenant;
    alerte();
  }

  @override
  void dispose() {
    _detruit = true;
    _abonnement?.cancel();
    _nouveaux.close();
    super.dispose();
  }
}

/// "3", "9+" : ce qu'affiche la pastille rouge.
String libelleNonLus(int nombre) => nombre > 9 ? '9+' : '$nombre';
