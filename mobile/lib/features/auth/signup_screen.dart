import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'auth_repository.dart';

/// Create an account. Only works for an email the society admin has already
/// pre-registered; everyone else is told to contact the admin.
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;
  bool _emailSent = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final invited = await isEmailInvited(ref.read(dioProvider), _email.text);
      if (!invited) {
        if (mounted) {
          showSnack(
            context,
            'This email is not registered by your society admin yet. '
            'Ask the admin to add it first.',
            error: true,
          );
        }
        return;
      }
      await ref.read(authRepositoryProvider).signUp(_email.text, _password.text, fullName: _name.text);
      if (mounted) setState(() => _emailSent = true);
    } catch (error) {
      if (mounted) showSnack(context, errorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: RoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  onPressed: () => context.go('/login'),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: _emailSent ? _CheckEmail(email: _email.text.trim()) : _form(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _form() {
    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Create account',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.greenTint,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Use the email address you gave your society admin. '
              'You can only register with that email.',
              style: TextStyle(color: AppColors.ink, fontSize: 14, height: 1.4),
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _name,
            keyboardType: TextInputType.name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Full name',
              helperText: 'Shown on your bills and invoices',
              counterText: '',
            ),
            validator: (v) =>
                (v?.trim().length ?? 0) >= 2 ? null : 'Please enter your full name',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (v) {
              final value = v?.trim() ?? '';
              return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)
                  ? null
                  : 'Enter a valid email';
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            obscureText: !_showPassword,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Create password',
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'Hide password' : 'Show password',
                icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
            validator: (v) =>
                (v == null || v.length < 8) ? 'Use at least 8 characters' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirm,
            obscureText: !_showPassword,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            decoration: const InputDecoration(labelText: 'Confirm password'),
            validator: (v) => v != _password.text ? 'Passwords do not match' : null,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : const Text('Create account'),
          ),
        ],
        ),
      ),
    );
  }
}

class _CheckEmail extends StatelessWidget {
  const _CheckEmail({required this.email});
  final String email;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: IconBadge(Icons.mark_email_read_outlined, size: 112)),
        const SizedBox(height: 20),
        const Text(
          'Check your email',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        Text(
          'We sent a confirmation link to $email. Tap it, then come back and sign in.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, fontSize: 16, height: 1.4),
        ),
        const SizedBox(height: 28),
        FilledButton(onPressed: () => context.go('/login'), child: const Text('Go to sign in')),
      ],
    );
  }
}
