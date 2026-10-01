import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/coming_soon_view.dart';
import '../../../../core/widgets/onyx_light.dart';
import '../../../courses/data/course_service.dart';
import '../../../messages/data/chat_service.dart';
import '../../../messages/presentation/widgets/ligne_conversation_course.dart';

/// Onglet Messages du Conducteur : la conversation avec le client de sa
/// course en cours, et rien d'autre (voir `firestore.rules` : on n'écrit
/// et on ne lit le profil que de l'autre partie d'une course en cours).
/// Le chat est le même [MessagerieChatPage] temps réel que côté client
/// (bouton d'appel compris).
class ConducteurMessagesTab extends StatefulWidget {
  const ConducteurMessagesTab({super.key, this.chatService, this.courseService, this.monUid});

  /// Injectables pour les tests.
  final ChatService? chatService;
  final CourseService? courseService;
  final String? monUid;

  @override
  State<ConducteurMessagesTab> createState() => _ConducteurMessagesTabState();
}

class _ConducteurMessagesTabState extends State<ConducteurMessagesTab> {
  late final ChatService _chatService = widget.chatService ?? ChatService();
  late final String? _monUid = widget.monUid ?? FirebaseAuth.instance.currentUser?.uid;
  late final Stream<CourseFirestore?>? _course = _monUid == null
      ? null
      : (widget.courseService ?? CourseService()).streamCourseActiveChauffeur(_monUid);

  @override
  Widget build(BuildContext context) {
    final monUid = _monUid;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Messages', style: styleTitreEcran),
              ),
            ),
            Expanded(
              child: monUid == null
                  ? const ComingSoonView(
                      icon: Icons.chat_bubble_outline_rounded,
                      titre: 'Messagerie indisponible',
                      message: 'Reconnectez-vous pour accéder à vos conversations.',
                    )
                  : StreamBuilder<CourseFirestore?>(
                      stream: _course,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const ComingSoonView(
                            icon: Icons.cloud_off_rounded,
                            titre: 'Conversations indisponibles',
                            message: 'Impossible de charger vos messages. Vérifiez votre connexion.',
                          );
                        }
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: AppColors.orange));
                        }
                        final course = snapshot.data;
                        if (course == null || course.clientId.isEmpty) {
                          return const ComingSoonView(
                            icon: Icons.chat_bubble_outline_rounded,
                            titre: 'Aucune conversation en cours',
                            message: 'Vous pourrez écrire à votre client dès que vous aurez accepté sa course, '
                                'jusqu\'à la fin du trajet.',
                          );
                        }
                        return ListView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                          children: [
                            LigneConversationCourse(
                              key: ValueKey(course.id),
                              chatService: _chatService,
                              monUid: monUid,
                              interlocuteurUid: course.clientId,
                              nomParDefaut: 'Votre client',
                              sousTitre: 'Client Sprint',
                              detailCourse: 'Course en cours · ${course.adresseDepart}',
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
