import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/premium_dialog.dart';
import '../../../core/widgets/primary_button.dart';

/// Formulaire de contact direct du support Sprint.
class NousContacterPage extends StatefulWidget {
  const NousContacterPage({super.key});

  @override
  State<NousContacterPage> createState() => _NousContacterPageState();
}

class _NousContacterPageState extends State<NousContacterPage> {
  final _formKey = GlobalKey<FormState>();
  final _sujetController = TextEditingController();
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _sujetController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _envoyer() {
    if (!_formKey.currentState!.validate()) return;
    _sujetController.clear();
    _messageController.clear();
    PremiumDialog.afficher(
      context,
      icon: Icons.mark_email_read_outlined,
      titre: 'Message envoyé',
      message: 'Notre équipe support a bien reçu votre demande et vous '
          'répondra très prochainement.',
      succes: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nous contacter')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            AppCard(
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.orangeLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.phone_outlined, color: AppColors.orange, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('+221 33 800 00 00', style: TextStyle(fontWeight: FontWeight.w700)),
                        Text('support@groupesantine.sn', style: TextStyle(fontSize: 12, color: AppColors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Envoyez-nous un message',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextField(
                    label: 'Sujet',
                    controller: _sujetController,
                    prefixIcon: Icons.subject_rounded,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Sujet requis' : null,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'Votre message',
                    controller: _messageController,
                    prefixIcon: Icons.message_outlined,
                    maxLines: 5,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Message requis' : null,
                  ),
                  const SizedBox(height: 18),
                  PrimaryButton(label: 'Envoyer', onPressed: _envoyer),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
