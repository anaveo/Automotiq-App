import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:automotiq_app/providers/model_provider.dart';
import 'package:automotiq_app/providers/auth_provider.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Consumer<ModelProvider>(
              builder: (context, modelProvider, _) {
                if (modelProvider.downloadError != null) {
                  return Text(
                    'Error: ${modelProvider.downloadError}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.red),
                    textAlign: TextAlign.center,
                  );
                }
                return Column(
                  children: [
                    Image(
                      image: AssetImage('assets/images/Automotiq_Full_Logo_V1.png'),
                      width: 300,
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(80, 0, 80, 0),
                      child: LinearProgressIndicator(
                        value: modelProvider.isDownloading ? modelProvider.downloadProgress : null,
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      modelProvider.isDownloading
                          ? 'Downloading model: ${(modelProvider.downloadProgress * 100).toStringAsFixed(1)}%'
                          : 'Model downloaded',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              },
            ),
            Consumer<AppAuthProvider>(
              builder: (context, authProvider, _) {
                if (authProvider.authError != null) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      'Error: ${authProvider.authError}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                if (authProvider.isLoading) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      'Initializing authentication...',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }
}