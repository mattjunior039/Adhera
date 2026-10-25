import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../repositories/medication_repository.dart';
import '../services/api_service.dart';

class LoginSignupScreen extends ConsumerStatefulWidget {
  const LoginSignupScreen({super.key});
  @override
  ConsumerState<LoginSignupScreen> createState() => _LoginSignupScreenState();
}

class _LoginSignupScreenState extends ConsumerState<LoginSignupScreen> {
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isCreatingAccount = false;

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty) {
      _showError('Enter your account email');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final user = await ref
          .read(medicationRepositoryProvider)
          .loginUser(email: email, password: password);
      ref.read(currentUserProvider.notifier).setUser(user);
      ref.read(userIdProvider.notifier).setUserId(user.id);
      ref.read(userEmailProvider.notifier).setUserEmail(user.email);
      if (!mounted) return;
      context.go('/dashboard');
    } on ApiException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError('Backend connection failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final user = await ref
          .read(medicationRepositoryProvider)
          .createUser(
            email: _emailController.text.trim(),
            fullName: _nameController.text.trim(),
            phone: _phoneController.text.trim().isEmpty
                ? null
                : _phoneController.text.trim(),
            password: _passwordController.text.trim(),
          );
      ref.read(currentUserProvider.notifier).setUser(user);
      ref.read(userIdProvider.notifier).setUserId(user.id);
      ref.read(userEmailProvider.notifier).setUserEmail(user.email);
      if (!mounted) return;
      context.go('/dashboard');
    } on ApiException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError('Backend connection failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'assets/adhera_logo.png',
                    height: 100,
                    fit: BoxFit.contain,
                    semanticLabel: 'Adhera logo',
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _isCreatingAccount ? 'Create your account' : 'Welcome back',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isCreatingAccount
                        ? 'Set up your medication routine and care plan.'
                        : 'Secure medication tracking for your care plan',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 24),
                  SegmentedButton<bool>(
                    selected: {_isCreatingAccount},
                    onSelectionChanged: (s) =>
                        setState(() => _isCreatingAccount = s.first),
                    segments: const [
                      ButtonSegment(value: false, label: Text('Sign in')),
                      ButtonSegment(value: true, label: Text('Create account')),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_isCreatingAccount) ...[
                    TextFormField(
                      controller: _nameController,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Name is required'
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Email is required'
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_isCreatingAccount) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    validator: (v) => (v == null || v.trim().length < 8)
                        ? 'Password must be at least 8 characters'
                        : null,
                    decoration: InputDecoration(
                      labelText: _isCreatingAccount
                          ? 'Password'
                          : 'Password (optional in local dev)',
                      helperText: _isCreatingAccount ? null : 'Blank only when the backend enables passwordless development login',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _isLoading
                        ? null
                        : (_isCreatingAccount ? _createAccount : _signIn),
                    icon: Icon(
                      _isCreatingAccount
                          ? Icons.person_add_alt_1_rounded
                          : Icons.login_rounded,
                    ),
                    label: Text(
                      _isLoading
                          ? (_isCreatingAccount
                                ? 'Creating account...'
                                : 'Signing in...')
                          : (_isCreatingAccount ? 'Create account' : 'Sign in'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
