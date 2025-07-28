import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:automotiq_app/providers/model_provider.dart';
import 'package:automotiq_app/utils/logger.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

class DiagnosisScreen extends StatefulWidget {
  const DiagnosisScreen({super.key, this.dtcs = const []});

  final List<String> dtcs;

  @override
  DiagnosisScreenState createState() => DiagnosisScreenState();
}

class DiagnosisScreenState extends State<DiagnosisScreen> {
  bool _isLoading = false;
  String? _error;
  String? _inferenceOutput;
  String _prompt = "";

  @override
  void initState() {
    super.initState();
    _setPrompt();
    _runInference();
  }

  void _setPrompt() {
    _prompt = "You are an AI mechanic. Your role is to diagnose the health of a vehicle, given its diagnostic trouble codes and recommend further action. The vehicle has the following diagnostic trouble codes: ${widget.dtcs.join(', ')}";
  }

  Future<void> _runInference() async {
    final modelProvider = Provider.of<ModelProvider>(context, listen: false);
    if (!modelProvider.isChatInitialized || modelProvider.globalAgent == null) {
      AppLogger.logError('Global chat not initialized', null, 'DiagnosisScreen._runInference');
      setState(() {
        _error = 'Chat not initialized. Please try again.';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _inferenceOutput = null;
    });

    try {
      final chat = modelProvider.globalAgent!;

      // Log token count to check for context overflow
      final tokenCount = await chat.maxTokens; // TODO: Replace with await chat.sizeInTokens(_prompt);
      AppLogger.logInfo('Prompt token count: $tokenCount', 'DiagnosisScreen._runInference');

      // Clear previous context to isolate DTC query
      // Note: Comment out if you want to retain ChatScreen context
      await chat.addQueryChunk(Message.text(text: 'Reset context for new diagnosis', isUser: false));

      await chat.addQueryChunk(Message.text(text: _prompt, isUser: true));
      final responseStream = chat.generateChatResponseAsync();
      String responseText = '';

      await for (final response in responseStream) {
        if (response is TextResponse) {
          setState(() {
            responseText += response.token;
            _inferenceOutput = responseText;
          });
        } else if (response is FunctionCallResponse) {
          final finalResponse = await chat.generateChatResponse();
          setState(() {
            _inferenceOutput = finalResponse.toString();
          });
        }
      }
      AppLogger.logInfo('Response received: $responseText', 'DiagnosisScreen._runInference');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'DiagnosisScreen._runInference');
      setState(() {
        _error = 'Inference failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnosis Screen'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Prompt:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(_prompt, style: const TextStyle(fontSize: 16)),
            const Divider(height: 32),
            const Text(
              'Inference Output:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _inferenceOutput ?? '',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            if (_isLoading)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    CircularProgressIndicator(),
                    SizedBox(width: 16),
                    Text('Generating inference...'),
                  ],
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}