import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/payment_method_selector.dart';
import '../../courses/data/course_service.dart';
import 'suivi_course_page.dart';

/// Sas de paiement obligatoire (100% mobile money) : s'affiche après le
/// choix de Wave ou Orange Money dans la bottom sheet, et bloque le
/// client (aucun retour arrière possible) le temps de simuler la
/// confirmation réseau de l'opérateur. Ce n'est qu'une fois ce délai
/// écoulé, et "Paiement confirmé !" affiché, que la course est
/// réellement créée dans Firestore (voir [CourseService.creerCourse]) —
/// ce qui réveille le radar des chauffeurs. Le client est ensuite
/// redirigé vers [SuiviCoursePage].
///
/// Aucun véritable encaissement n'est déclenché : il n'existe pas
/// encore d'intégration Wave/Orange Money côté Sprint. Ce délai simule
/// l'attente réseau réelle d'une confirmation opérateur, pour habituer
/// l'UX à ce futur branchement sans bloquer le lancement du
/// matchmaking en attendant.
class PaymentProcessingPage extends StatefulWidget {
  const PaymentProcessingPage({
    super.key,
    required this.methode,
    required this.clientId,
    required this.type,
    required this.adresseDepart,
    required this.adresseArrivee,
    required this.prixFcfa,
  });

  final PaymentMethod methode;
  final String clientId;
  final String type;
  final String adresseDepart;
  final String adresseArrivee;
  final int prixFcfa;

  @override
  State<PaymentProcessingPage> createState() => _PaymentProcessingPageState();
}

enum _EtapePaiement { enAttente, confirme }

class _PaymentProcessingPageState extends State<PaymentProcessingPage> {
  final _courseService = CourseService();
  _EtapePaiement _etape = _EtapePaiement.enAttente;

  @override
  void initState() {
    super.initState();
    _traiterPaiement();
  }

  Future<void> _traiterPaiement() async {
    // Simule l'attente de confirmation réseau de l'opérateur (Wave /
    // Orange Money) : entre 3 et 4 secondes.
    await Future.delayed(const Duration(milliseconds: 3500));
    if (!mounted) return;

    setState(() => _etape = _EtapePaiement.confirme);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    final courseId = await _courseService.creerCourse(
      clientId: widget.clientId,
      type: widget.type,
      adresseDepart: widget.adresseDepart,
      adresseArrivee: widget.adresseArrivee,
      prixFcfa: widget.prixFcfa,
      methodePaiement: widget.methode.apiValue,
    );
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => SuiviCoursePage(courseId: courseId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Bloque le client pendant la simulation du paiement : ni retour
      // arrière ni fermeture accidentelle avant confirmation.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _etape == _EtapePaiement.enAttente
                ? _VueEnAttente(methode: widget.methode)
                : const _VueConfirmee(),
          ),
        ),
      ),
    );
  }
}

class _VueEnAttente extends StatelessWidget {
  const _VueEnAttente({required this.methode});

  final PaymentMethod methode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('enAttente'),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.orange),
          ),
          const SizedBox(height: 28),
          Text(
            'En attente de la confirmation de\nvotre paiement ${methode.label}…',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            'Ne fermez pas cette page.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: AppColors.grey),
          ),
        ],
      ),
    );
  }
}

class _VueConfirmee extends StatelessWidget {
  const _VueConfirmee();

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('confirmee'),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(Icons.check_circle_rounded, color: Colors.green.shade600, size: 44),
          ),
          const SizedBox(height: 24),
          const Text(
            'Paiement confirmé !',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
