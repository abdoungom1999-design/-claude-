import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/ecran_statut_onyx.dart';
import '../../portefeuille/data/retraits.dart' show formaterNumero, numeroSenegal;
import '../data/validation_telephone.dart';

/// Écran « Validez votre numéro » : un SMS contenant un code à 6 chiffres est
/// envoyé au numéro du compte ; la saisie du code le valide (voir
/// [ValidationTelephone]). Affiché par `PorteInscription` aux NOUVEAUX comptes,
/// une fois l'e-mail vérifié, quand la validation du numéro est ouverte.
///
/// Le numéro est celui de l'inscription : une faute de frappe se corrige ici
/// (« Modifier »), le profil est alors mis à jour avant l'envoi. Le renvoi du
/// code est limité (un délai de [delaiRenvoi], [renvoisMax] fois) : chaque SMS
/// est facturé.
class ValidationTelephonePage extends StatefulWidget {
  const ValidationTelephonePage({
    super.key,
    required this.numeroInitial,
    required this.service,
    required this.surValide,
    required this.surDeconnexion,
    required this.enregistrerNumero,
    this.surPlusTard,
    this.delaiRenvoi = const Duration(seconds: 60),
    this.renvoisMax = 3,
  });

  /// Numéro du profil, tel que saisi à l'inscription.
  final String numeroInitial;
  final ValidationTelephone service;

  /// Le serveur a marqué le numéro validé.
  final VoidCallback surValide;
  final VoidCallback surDeconnexion;

  /// Met à jour le numéro du profil (avant l'envoi, s'il a été corrigé).
  final Future<void> Function(String numero) enregistrerNumero;

  /// « Plus tard » : seulement quand la validation est facultative.
  final VoidCallback? surPlusTard;

  final Duration delaiRenvoi;
  final int renvoisMax;

  @override
  State<ValidationTelephonePage> createState() => _ValidationTelephonePageState();
}

enum _Etape { numero, code }

class _ValidationTelephonePageState extends State<ValidationTelephonePage> {
  final _numero = TextEditingController();
  final _code = TextEditingController();

  _Etape _etape = _Etape.numero;
  bool _modification = false;
  bool _enCours = false;
  bool _termine = false;
  String? _erreur;

  /// Numéro affiché (celui du dernier envoi) et numéro actuellement enregistré dans le profil.
  String _saisie = '';
  String _numeroEnregistre = '';
  EnvoiSms? _envoi;
  int _renvois = 0;
  int _secondesRestantes = 0;
  Timer? _minuteur;

  @override
  void initState() {
    super.initState();
    _saisie = widget.numeroInitial;
    _numeroEnregistre = widget.numeroInitial;
    // Numéro de l'inscription illisible : la personne le saisit d'emblée.
    _modification = numeroSenegal(widget.numeroInitial) == null;
    _numero.text = _modification ? widget.numeroInitial : '';
  }

  /// Numéro à proposer dans le champ quand la personne le corrige : celui en cours, lisible.
  String get _numeroAEditer {
    final n = numeroSenegal(_saisie);
    return n == null ? '' : formaterNumero(n);
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    _numero.dispose();
    _code.dispose();
    // Session « téléphone » laissée ouverte si la page est quittée avant la fin.
    if (!_termine) unawaited(widget.service.abandonner());
    super.dispose();
  }

  String get _numeroAffiche {
    final n = numeroSenegal(_saisie);
    return n == null ? _saisie.trim() : '+221 ${formaterNumero(n)}';
  }

  void _demarrerDelai() {
    _minuteur?.cancel();
    _secondesRestantes = widget.delaiRenvoi.inSeconds;
    if (_secondesRestantes <= 0) return;
    _minuteur = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _secondesRestantes = _secondesRestantes > 0 ? _secondesRestantes - 1 : 0);
      if (_secondesRestantes == 0) t.cancel();
    });
  }

  /// Vérification instantanée ou SMS lu automatiquement (Android) : le jeton est prêt.
  Future<void> _verificationAutomatique(String jeton) async {
    if (!mounted || _termine || _enCours) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await widget.service.validerAupresDuServeur(jeton);
      _reussir();
    } on ApiException catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  void _reussir() {
    if (!mounted || _termine) return;
    _termine = true;
    _minuteur?.cancel();
    widget.surValide();
  }

  Future<void> _envoyer({bool renvoi = false}) async {
    if (_enCours) return;
    final saisie = _modification ? _numero.text.trim() : _saisie;
    if (numeroSenegal(saisie) == null) {
      setState(() => _erreur = 'Entrez un numéro mobile du Sénégal (exemple : 77 123 45 67).');
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      // Numéro corrigé : le profil prend le numéro qui va être validé.
      if (numeroSenegal(saisie) != numeroSenegal(_numeroEnregistre)) {
        await widget.enregistrerNumero(saisie);
        _numeroEnregistre = saisie;
      }
      final envoi = await widget.service.envoyerCode(
        saisie,
        precedent: renvoi ? _envoi : null,
        surVerificationAutomatique: _verificationAutomatique,
      );
      if (!mounted) return;
      setState(() {
        _saisie = saisie;
        _envoi = envoi;
        _etape = _Etape.code;
        _modification = false;
        if (renvoi) _renvois++;
        _code.clear();
      });
      _demarrerDelai();
    } on ApiException catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } catch (_) {
      if (mounted) setState(() => _erreur = "L'envoi du code est momentanément indisponible. Réessayez plus tard.");
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _valider() async {
    final envoi = _envoi;
    if (_enCours || envoi == null) return;
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      await widget.service.confirmerCode(envoi, _code.text);
      _reussir();
    } on ApiException catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } catch (_) {
      if (mounted) setState(() => _erreur = "Le code n'a pas pu être contrôlé. Réessayez.");
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  void _changerDeNumero() {
    _minuteur?.cancel();
    setState(() {
      _etape = _Etape.numero;
      _modification = true;
      _numero.text = _numeroAEditer;
      _erreur = null;
      _envoi = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _etape == _Etape.numero ? _construireNumero() : _construireCode();
  }

  Widget _construireNumero() {
    return EcranStatutOnyx(
      icone: Icons.sms_outlined,
      titre: 'Validez votre numéro',
      texte: 'Pour sécuriser votre compte, nous vous envoyons un code à 6 chiffres par SMS.',
      contenu: [
        if (_modification)
          AppTextField(
            key: const ValueKey('tel-numero'),
            label: 'Numéro de téléphone',
            hint: '77 123 45 67',
            controller: _numero,
            keyboardType: TextInputType.phone,
            prefixIcon: Icons.phone_outlined,
            onChanged: (_) {
              if (_erreur != null) setState(() => _erreur = null);
            },
          )
        else
          _NumeroAffiche(
            numero: _numeroAffiche,
            surModifier: () => setState(() {
              _modification = true;
              _numero.text = _numeroAEditer;
              _erreur = null;
            }),
          ),
        if (_erreur != null) _MessageErreur(message: _erreur!),
      ],
      actions: [
        BoutonStatutPrincipal(
          key: const ValueKey('tel-envoyer'),
          label: 'Envoyer le code',
          icone: Icons.send_rounded,
          enCours: _enCours,
          onPressed: _envoyer,
        ),
        if (widget.surPlusTard != null)
          BoutonStatutSecondaire(key: const ValueKey('tel-plus-tard'), label: 'Plus tard', onPressed: widget.surPlusTard),
        LienStatut(label: 'Se déconnecter', onPressed: widget.surDeconnexion),
      ],
    );
  }

  Widget _construireCode() {
    final peutRenvoyer = _secondesRestantes == 0 && _renvois < widget.renvoisMax && !_enCours;
    final libelleRenvoi = _renvois >= widget.renvoisMax
        ? 'Trop de renvois : réessayez plus tard'
        : _secondesRestantes > 0
            ? 'Renvoyer le code ($_secondesRestantes s)'
            : 'Renvoyer le code';
    return EcranStatutOnyx(
      icone: Icons.mark_chat_read_outlined,
      titre: 'Entrez le code reçu',
      texte: 'Nous avons envoyé un code à 6 chiffres au $_numeroAffiche. Il arrive en quelques secondes.',
      contenu: [
        _ChampCode(
          key: const ValueKey('tel-code'),
          controller: _code,
          surChange: (valeur) {
            if (_erreur != null) setState(() => _erreur = null);
            setState(() {});
            if (valeur.length == 6) unawaited(_valider());
          },
        ),
        if (_erreur != null) _MessageErreur(message: _erreur!),
      ],
      actions: [
        BoutonStatutPrincipal(
          key: const ValueKey('tel-valider'),
          label: 'Valider',
          enCours: _enCours,
          onPressed: _code.text.length == 6 ? _valider : null,
        ),
        BoutonStatutSecondaire(
          key: const ValueKey('tel-renvoyer'),
          label: libelleRenvoi,
          onPressed: peutRenvoyer ? () => _envoyer(renvoi: true) : null,
        ),
        LienStatut(label: 'Changer de numéro', onPressed: _changerDeNumero),
      ],
    );
  }
}

class _NumeroAffiche extends StatelessWidget {
  const _NumeroAffiche({required this.numero, required this.surModifier});

  final String numero;
  final VoidCallback surModifier;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.verre,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.bordVerre),
      ),
      child: Row(
        children: [
          const Icon(Icons.phone_outlined, size: 20, color: AppColors.vert),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              numero,
              key: const ValueKey('tel-affiche'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.texte),
            ),
          ),
          TextButton(
            key: const ValueKey('tel-modifier'),
            onPressed: surModifier,
            child: const Text('Modifier', style: TextStyle(color: AppColors.vert, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Champ du code à 6 chiffres : chiffres seulement, gros caractères espacés,
/// et le code reçu par SMS peut être proposé par le clavier (iPhone, site).
class _ChampCode extends StatelessWidget {
  const _ChampCode({super.key, required this.controller, required this.surChange});

  final TextEditingController controller;
  final ValueChanged<String> surChange;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder bord(Color couleur, [double epaisseur = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: couleur, width: epaisseur),
        );
    return TextField(
      controller: controller,
      onChanged: surChange,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: 6,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(color: AppColors.texte, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 12),
      cursorColor: AppColors.vert,
      decoration: InputDecoration(
        labelText: 'Code à 6 chiffres',
        counterText: '',
        filled: true,
        fillColor: AppColors.verre,
        floatingLabelAlignment: FloatingLabelAlignment.center,
        labelStyle: const TextStyle(color: AppColors.texteDiscret, fontWeight: FontWeight.w500),
        floatingLabelStyle: const TextStyle(color: AppColors.vert, fontWeight: FontWeight.w600),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: bord(AppColors.bord),
        enabledBorder: bord(AppColors.bord),
        focusedBorder: bord(AppColors.vert, 1.8),
      ),
    );
  }
}

class _MessageErreur extends StatelessWidget {
  const _MessageErreur({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      key: const ValueKey('tel-erreur'),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 13, color: AppColors.danger, fontWeight: FontWeight.w700, height: 1.4),
    );
  }
}
