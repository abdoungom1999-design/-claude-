import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/coming_soon_view.dart';
import '../../../firebase_options.dart';
import '../../courses/data/course_service.dart';
import '../data/chat_service.dart';
import 'widgets/ligne_conversation_course.dart';

/// Onglet Messages du client : la conversation avec le chauffeur de sa
/// course en cours, et rien d'autre. Un client ne voit ni ne contacte
/// aucun autre chauffeur : il n'existe aucune liste de chauffeurs (les
/// règles Firestore l'interdisent aussi, voir `firestore.rules`). Dès que
/// la course se termine ou est annulée, la conversation disparaît de
/// l'onglet et on ne peut plus y écrire.
class MessagesTabPage extends StatefulWidget {
  const MessagesTabPage({super.key, this.courseService, this.chatService, this.monUid});

  /// Injectables pour les tests.
  final CourseService? courseService;
  final ChatService? chatService;
  final String? monUid;

  @override
  State<MessagesTabPage> createState() => _MessagesTabPageState();
}

class _MessagesTabPageState extends State<MessagesTabPage> {
  late final ChatService _chatService = widget.chatService ?? ChatService();
  late final String? _monUid = widget.monUid ?? _uidConnecte();
  late final Stream<List<CourseFirestore>>? _courses = _monUid == null
      ? null
      : (widget.courseService ?? CourseService()).streamCoursesClient(_monUid);

  static String? _uidConnecte() {
    try {
      return DefaultFirebaseOptions.estConfigure ? FirebaseAuth.instance.currentUser?.uid : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final monUid = _monUid;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Messages', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ),
            ),
            Expanded(
              child: monUid == null
                  ? const ComingSoonView(
                      icon: Icons.chat_bubble_outline_rounded,
                      titre: 'Messagerie indisponible',
                      message: 'La messagerie instantanée nécessite le backend Firebase.',
                    )
                  : StreamBuilder<List<CourseFirestore>>(
                      stream: _courses,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const ComingSoonView(
                            icon: Icons.cloud_off_rounded,
                            titre: 'Messages indisponibles',
                            message: 'Impossible de charger vos courses. Vérifiez votre connexion.',
                          );
                        }
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: AppColors.orange));
                        }
                        // Seules les courses en cours avec un chauffeur attribué.
                        final actives = [
                          for (final c in snapshot.data ?? const <CourseFirestore>[])
                            if (c.estActive && (c.chauffeurId?.isNotEmpty ?? false)) c,
                        ];
                        if (actives.isEmpty) {
                          return const ComingSoonView(
                            icon: Icons.chat_bubble_outline_rounded,
                            titre: 'Aucune conversation en cours',
                            message: 'Vous pourrez écrire à votre chauffeur dès qu\'il aura accepté votre course, '
                                'jusqu\'à la fin du trajet.',
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                          itemCount: actives.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final course = actives[index];
                            return LigneConversationCourse(
                              key: ValueKey(course.id),
                              chatService: _chatService,
                              monUid: monUid,
                              interlocuteurUid: course.chauffeurId!,
                              nomParDefaut: 'Votre chauffeur',
                              sousTitre: 'Chauffeur Sprint',
                              detailCourse: 'Course en cours · ${course.adresseArrivee}',
                            );
                          },
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
