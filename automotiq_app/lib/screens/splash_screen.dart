import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:automotiq_app/providers/model_provider.dart';

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
                      image: AssetImage('assets/images/Automotiq_Logo_Animated.gif'),
                      width: MediaQuery.of(context).size.width,
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(80, 0, 80, 0),
                      child: LinearProgressIndicator(
                        value: modelProvider.isModelDownloading ? modelProvider.modelDownloadProgress : null,
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      modelProvider.isModelDownloading
                          ? 'Downloading model: ${(modelProvider.modelDownloadProgress * 100).toStringAsFixed(1)}%'
                          : 'Model downloaded',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}