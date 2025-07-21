import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../utils/logger.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

// TODO: migrate the email linking away from the login screen
// TODO: Refactor to use central theme and styles
class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _errorMessage;
  bool _showEmailForm = true; // Always show email form by default
  bool _isLinkingAccount = false;

  Future<void> _signInWithEmail() async {
    if (!_formKey.currentState!.validate()) return;
    final authProvider = Provider.of<AppAuthProvider>(context, listen: false);
    try {
      setState(() => _errorMessage = null);
      await authProvider.signInWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
      );
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'LoginScreen.signInWithEmail');
      setState(() {
        _errorMessage = 'Failed to sign in: $e';
      });
    }
  }

  Future<void> _linkWithEmail() async {
    if (!_formKey.currentState!.validate()) return;
    final authProvider = Provider.of<AppAuthProvider>(context, listen: false);
    try {
      setState(() => _errorMessage = null);
      await authProvider.linkAnonymousToEmail(
        _emailController.text.trim(),
        _passwordController.text,
      );
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'LoginScreen.linkWithEmail');
      setState(() {
        _errorMessage = 'Failed to create account: $e';
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AppAuthProvider>(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: authProvider.isLoading
              ? const CircularProgressIndicator(color: Colors.deepPurple)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // App Title
                      const Text(
                        'Autonomiq',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Error Message
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      // Email/Password Form
                      if (_showEmailForm)
                        Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _emailController,
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  labelStyle: TextStyle(color: Colors.white70),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.white54),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.redAccent),
                                  ),
                                ),
                                style: const TextStyle(color: Colors.white),
                                keyboardType: TextInputType.emailAddress,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter an email';
                                  }
                                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                                    return 'Please enter a valid email';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _passwordController,
                                decoration: const InputDecoration(
                                  labelText: 'Password',
                                  labelStyle: TextStyle(color: Colors.white70),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.white54),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.redAccent),
                                  ),
                                ),
                                style: const TextStyle(color: Colors.white),
                                obscureText: true,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter a password';
                                  }
                                  if (value.length < 6) {
                                    return 'Password must be at least 6 characters';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: _isLinkingAccount ? _linkWithEmail : _signInWithEmail,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                ),
                                child: Text(
                                  _isLinkingAccount ? 'Create Account' : 'Sign In',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: () => setState(() {
                                  _showEmailForm = false;
                                  _errorMessage = null;
                                  _isLinkingAccount = !_isLinkingAccount;
                                }),
                                child: Text(
                                  _isLinkingAccount ? 'Sign In' : 'Create Account',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}