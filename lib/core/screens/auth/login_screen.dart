import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../widgets/backend_status_indicator.dart';
import '../../widgets/copyable_error.dart';
import '../../services/app_config_service.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _backendUrlController = TextEditingController();
  bool _obscurePassword = true;
  bool _showAdvancedSettings = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentBackendUrl();
  }

  Future<void> _loadCurrentBackendUrl() async {
    final currentUrl = await AppConfigService.instance.getBackendUrl();
    _backendUrlController.text = currentUrl;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _backendUrlController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      // Save the backend URL configuration first
      if (_backendUrlController.text.isNotEmpty) {
        await AppConfigService.instance.setBackendUrl(_backendUrlController.text.trim());
      }
      
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      await authProvider.login(
        _emailController.text.trim(),
        _passwordController.text,
      );

      // Error handling is now done through the Consumer widget in the UI
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Backend status at the top
                const Align(
                  alignment: Alignment.topRight,
                  child: BackendStatusIndicator(compact: true),
                ),
                const SizedBox(height: 16),
                // Logo and title
                Icon(
                  Icons.music_note,
                  size: 64,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(height: 16),
                Text(
                  'Musestruct',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Structure your music library',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 48),
                
                // Email field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // Password field
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // Advanced settings toggle
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _showAdvancedSettings = !_showAdvancedSettings;
                    });
                  },
                  icon: Icon(
                    _showAdvancedSettings ? Icons.expand_less : Icons.expand_more,
                  ),
                  label: Text('Advanced Settings'),
                ),
                
                // Backend URL field (collapsible)
                if (_showAdvancedSettings) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _backendUrlController,
                    decoration: InputDecoration(
                      labelText: 'Backend URL',
                      hintText: 'http://127.0.0.1:8080',
                      prefixIcon: const Icon(Icons.cloud),
                      border: const OutlineInputBorder(),
                      helperText: 'Configure the Musestruct backend server URL',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () {
                          _backendUrlController.text = AppConfigService.defaultBackendUrl;
                        },
                        tooltip: 'Reset to default',
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a backend URL';
                      }
                      if (!AppConfigService.isValidBackendUrl(value)) {
                        return 'Please enter a valid URL (e.g., http://127.0.0.1:8080)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                
                // Error message
                Consumer<AuthProvider>(
                  builder: (context, authProvider, child) {
                    if (authProvider.error != null) {
                      return Column(
                        children: [
                          CopyableErrorWidget(
                            errorMessage: authProvider.error!,
                            title: 'Login Failed',
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                
                // Login button
                Consumer<AuthProvider>(
                  builder: (context, authProvider, child) {
                    return ElevatedButton(
                      onPressed: authProvider.isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: authProvider.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Login'),
                    );
                  },
                ),
                const SizedBox(height: 16),
                
                // Register link
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const RegisterScreen(),
                      ),
                    );
                  },
                  child: const Text("Don't have an account? Register"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
