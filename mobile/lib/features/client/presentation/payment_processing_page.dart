import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/payment_method_selector.dart';
import '../../courses/data/course_service.dart';
import '../../paiement/data/paiement_service.dart';
import 'suivi_course_page.dart';

/// Sas de paiement obligatoire (100% mobile money) : s'affiche après le
/// choix de Wave ou Orange Money, bloque le client (aucun retour
/// arrière) pendant la demande de paiement via [PaiementService], et ne
/// crée la course dans Firestore — ce qui réveille le radar des
/// chauffeurs — que si la transaction est confirmée. Le client est
/// alors redirigé vers [SuiviCoursePage].
///
/// En cas d'échec ou d'annulation, aucune course n'est créée : la page
/// se referme en renvoyant le message d'erreur à l'écran de commande,
/// qui l'affiche.
class PaymentProcessingPage extends StatefulWidget {
  PaymentProcessingPage({
    super.key,
    required this.methode,
    required this.clientId,
    required this.type,
    required this.adresseDepart,
    required this.adresseArrivee,
    required this.prixFcfa,
    PaiementService? paiementService,
    CourseService? courseService,
  })  : paiementService = paiementService ?? PaiementService.parDefaut(),
        courseService = courseService ?? CourseService();

  final PaymentMethod methode;
  final String clientId;
  final String type;
  final String adresseDepart;
  final String adresseArrivee;
  final int prixFcfa;
  final PaiementService paiementService;
  final CourseService courseService;

  @override
  State<PaymentProcessingPage> createState() => _PaymentProcessingPageState();
}

enum _EtapePaiement { enAttente, confirme }

class _PaymentProcessingPageState extends State<PaymentProcessingPage> {
  _EtapePaiement _etape = _EtapePaiement.enAttente;

  @override
  void initState() {
    super.initState();
    _traiterPaiement();
  }

  Future<void> _traiterPaiement() async {
    final TransactionResult transaction;
    try {
      transaction = await widget.paiementService.initierPaiement(
        widget.methode,
        widget.prixFcfa.toDouble(),
      );
    } catch (_) {
      _abandonner("Le paiement ${widget.methode.label} n'a pas pu aboutir. Aucune course n'a été créée.");
      return;
    }
    if (!mounted) return;

    if (!transaction.estReussie) {
      _abandonner(
        transaction.message ??
            (transaction.statut == StatutTransaction.annule
                ? 'Paiement annulé. Aucune course n\'a été créée.'
                : 'Paiement ${widget.methode.label} refusé. Aucune course n\'a été créée.'),
      );
      return;
    }

    setState(() => _etape = _EtapePaiement.confirme);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    final String courseId;
    try {
      courseId = await widget.courseService.creerCourse(
        clientId: widget.clientId,
        type: widget.type,
        adresseDepart: widget.adresseDepart,
        adresseArrivee: widget.adresseArrivee,
        prixFcfa: widget.prixFcfa,
        methodePaiement: widget.methode.apiValue,
        transactionId: transaction.id,
      );
    } catch (_) {
      _abandonner("La course n'a pas pu être créée. Veuillez réessayer.");
      return;
    }
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => SuiviCoursePage(courseId: courseId)),
    );
  }

  /// Referme le sas (malgré le [PopScope] qui bloque le retour manuel)
  /// en renvoyant [message] à l'écran de commande.
  void _abandonner(String message) {
    if (mounted) Navigator.of(context).pop(message);
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
