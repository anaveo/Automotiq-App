import 'package:automotiq_app/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:automotiq_app/providers/model_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/user_provider.dart';
import '../providers/vehicle_provider.dart';

class AccountSettingsScreen extends StatelessWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;
    final userProvider = context.watch<UserProvider>();
    final vehicleProvider = context.watch<VehicleProvider>();

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(title: const Text("Settings")),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            /// My Vehicles section
            if (vehicleProvider.vehicles.isNotEmpty)
              _card(
                title: 'My Vehicles',
                child: Column(
                  children: [
                    ...vehicleProvider.vehicles.map((vehicle) {
                      return ListTile(
                        title: Text(vehicle.name),
                        subtitle: Text(
                          vehicle.vin,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete Vehicle?'),
                                content: Text(
                                  '${vehicle.name} and all settings will be deleted.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text(
                                      'Delete',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await vehicleProvider.removeVehicle(vehicle.id);
                            }
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),

            /// Demo mode
            _card(
              title: 'Demo Mode',
              child: Column(
                children: [
                  Text(
                    "Enable demo mode to simulate vehicle data without a physical OBD-II device.",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  SwitchListTile(
                    title: const Text("Enable Demo Mode"),
                    value: userProvider.user?.demoMode ?? false,
                    onChanged: (value) {
                      userProvider.setDemoMode(value);
                      vehicleProvider.updateDemoMode(
                        value,
                      ); // Notify VehicleProvider
                    },
                  ),
                ],
              ),
            ),

            /// Clear Assistant Memory
            _card(
              title: 'Clear Assistant Memory',
              child: Consumer<ModelProvider>(
                builder: (context, modelProvider, child) {
                  final isButtonEnabled =
                      modelProvider.isModelDownloaded &&
                      modelProvider.isModelInitialized &&
                      modelProvider.isChatInitialized;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Reset integrated assistant to default settings.",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: isButtonEnabled
                            ? () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text(
                                      'Clear Assistant Memory?',
                                    ),
                                    content: const Text(
                                      'All assistant chats and vehicle data will be deleted. This action cannot be undone.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text(
                                          'Clear',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  try {
                                    await modelProvider.resetChat();
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    await prefs.remove('chat_messages');

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Assistant memory cleared',
                                        ),
                                      ),
                                    );
                                  } catch (e) {
                                    AppLogger.logError(e);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Failed to clear memory: $e',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              }
                            : null,
                        child: const Text('Clear Assistant Memory'),
                      ),
                    ],
                  );
                },
              ),
            ),

            /// Link anonymous account
            if (user != null && user.isAnonymous)
              _card(title: 'Create Account', child: _AnonymousLinkForm()),

            /// Change email/password
            if (user != null && !user.isAnonymous)
              _card(
                title: 'Update Email / Password',
                child: _EmailPasswordSettings(),
              ),

            /// Logout
            if (user != null)
              ElevatedButton.icon(
                onPressed: () async {
                  late final bool? confirm;
                  if (user.isAnonymous) {
                    confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Exit without creating an account?'),
                        content: const Text(
                          'All vehicles and settings will be lost.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text(
                              'Confirm',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );
                  } else {
                    confirm = true;
                  }
                  if (confirm == true) {
                    await FirebaseAuth.instance.signOut();
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                },
                icon: const Icon(Icons.logout),
                label: const Text("Log Out"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Shared card container
  Widget _card({required String title, required Widget child}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: const Color.fromARGB(255, 20, 20, 20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Widget to link anonymous user to email/password
class _AnonymousLinkForm extends StatefulWidget {
  @override
  State<_AnonymousLinkForm> createState() => _AnonymousLinkFormState();
}

class _AnonymousLinkFormState extends State<_AnonymousLinkForm> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _error;

  Future<void> _linkAccount() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      final credential = EmailAuthProvider.credential(
        email: _emailController.text,
        password: _passwordController.text,
      );
      await FirebaseAuth.instance.currentUser!.linkWithCredential(credential);
      setState(() => _error = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Account linked successfully")),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    }
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: Theme.of(context).textTheme.bodySmall,
      filled: true,
      fillColor: Colors.grey.shade900,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Create an account to save your data and settings.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: TextFormField(
              controller: _emailController,
              decoration: _inputDecoration('Email'),
              autocorrect: false,
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
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: TextFormField(
              controller: _passwordController,
              decoration: _inputDecoration('Password'),
              obscureText: true,
              autocorrect: false,
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
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _linkAccount,
            child: const Text("Create Account"),
          ),
        ],
      ),
    );
  }
}

/// Widget to change email/password for signed-in users
class _EmailPasswordSettings extends StatefulWidget {
  @override
  State<_EmailPasswordSettings> createState() => _EmailPasswordSettingsState();
}

class _EmailPasswordSettingsState extends State<_EmailPasswordSettings> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _status;

  Future<void> _changeEmailPassword() async {
    try {
      final user = FirebaseAuth.instance.currentUser!;
      if (_emailController.text.isNotEmpty) {
        await user.updateEmail(_emailController.text);
      }
      if (_passwordController.text.isNotEmpty) {
        await user.updatePassword(_passwordController.text);
      }
      setState(() => _status = "Updated successfully");
    } on FirebaseAuthException catch (e) {
      setState(() => _status = e.message);
    }
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: Theme.of(context).textTheme.bodySmall,
      filled: true,
      fillColor: Colors.grey.shade900,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: TextField(
            controller: _emailController,
            decoration: _inputDecoration('New Email'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: _inputDecoration('New Password'),
          ),
        ),
        if (_status != null) Text(_status!),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _changeEmailPassword,
          child: const Text("Update"),
        ),
      ],
    );
  }
}
