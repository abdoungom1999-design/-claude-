import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../../data/chat_service.dart';
import '../../data/messages_non_lus.dart';
import '../messagerie_chat_page.dart';
import 'pastille_non_lus.dart';

/// Ligne de l'onglet Messages : la conversation avec l'autre partie de la
/// course en cours (le chauffeur pour un client, le client pour un
/// chauffeur), avec son nom et le dernier message. Ouvre le chat.
///
/// Le nom vient du profil public, lisible seulement pendant la course
/// (voir `firestore.rules`) : sinon [nomParDefaut] s'affiche.
class LigneConversationCourse extends StatefulWidget {
  const LigneConversationCourse({
    super.key,
    required this.chatService,
    required this.monUid,
    required this.interlocuteurUid,
    required this.nomParDefaut,
    required this.sousTitre,
    required this.detailCourse,
    this.messagesNonLus,
  });

  final ChatService chatService;
  final String monUid;
  final String interlocuteurUid;

  /// "Votre chauffeur" ou "Votre client".
  final String nomParDefaut;

  /// "Chauffeur Sprint" ou "Client Sprint".
  final String sousTitre;

  /// Ce que l'on sait de la course, ex. "Course en cours · Almadies".
  final String detailCourse;

  /// Messages non lus du chauffeur (côté client) : pastille rouge avec
  /// leur nombre. `null` pour le chauffeur.
  final MessagesNonLus? messagesNonLus;

  @override
  State<LigneConversationCourse> createState() => _LigneConversationCourseState();
}

class _LigneConversationCourseState extends State<LigneConversationCourse> {
  String? _nom;
  late final Stream<ChatMessageFirestore?> _dernierMessage =
      widget.chatService.streamDernierMessage(widget.chatService.chatIdEntre(widget.monUid, widget.interlocuteurUid));

  @override
  void initState() {
    super.initState();
    _chargerNom();
  }

  Future<void> _chargerNom() async {
    try {
      final profil = await widget.chatService.chargerProfil(widget.interlocuteurUid);
      final nom = (profil?['nom'] as String?)?.trim();
      if (mounted && nom != null && nom.isNotEmpty) setState(() => _nom = nom);
    } catch (_) {
      // Course terminée entre-temps, ou réseau : le nom par défaut suffit.
    }
  }

  @override
  Widget build(BuildContext context) {
    final nom = _nom ?? widget.nomParDefaut;
    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MessagerieChatPage(
            interlocuteurUid: widget.interlocuteurUid,
            interlocuteurNom: nom,
            interlocuteurSousTitre: widget.sousTitre,
            chatService: widget.chatService,
            monUid: widget.monUid,
            messagesNonLus: widget.messagesNonLus,
          ),
        ),
      ),
      child: Row(
        children: [
          // Avatar Onyx cerclé d'orange (comme sur l'écran Compte).
          Container(
            width: 48,
            height: 48,
            padding: const EdgeInsets.all(2.5),
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.bleu),
            child: Container(
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.onyx),
              alignment: Alignment.center,
              child: Text(
                nom.isNotEmpty ? nom[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nom, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.onyx)),
                const SizedBox(height: 2),
                Text(widget.detailCourse, style: const TextStyle(fontSize: 11.5, color: AppColors.texteDiscret)),
                const SizedBox(height: 4),
                StreamBuilder<ChatMessageFirestore?>(
                  stream: _dernierMessage,
                  builder: (context, snapshot) {
                    final texte = snapshot.data?.text;
                    return Text(
                      texte ?? 'Aucun message pour le moment',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: texte == null ? AppColors.texteDiscret : AppColors.onyx,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          if (widget.messagesNonLus case final nonLus?)
            ListenableBuilder(
              listenable: nonLus,
              builder: (context, _) => nonLus.interlocuteurUid == widget.interlocuteurUid && nonLus.nonLus > 0
                  ? Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: PastilleNonLus(
                        nombre: nonLus.nonLus,
                        child: const Icon(Icons.mark_chat_unread_rounded, color: AppColors.bleu, size: 22),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.texteDiscret),
        ],
      ),
    );
  }
}
