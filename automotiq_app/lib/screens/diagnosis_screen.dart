import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/flutter_gemma.dart';
import '../models/model.dart';
import 'package:path_provider/path_provider.dart';

class DiagnosisScreen extends StatefulWidget {
  const DiagnosisScreen({super.key, this.model = Model.gemma3Gpu_1B, this.dtcs = const []});

  final Model model;
  final List<String> dtcs;

  @override
  DiagnosisScreenState createState() => DiagnosisScreenState();
}

class DiagnosisScreenState extends State<DiagnosisScreen> {
  final _gemma = FlutterGemmaPlugin.instance;
  InferenceChat? chat;
  bool _isModelInitialized = false;
  bool _isLoading = false;
  String? _error;
  String? _inferenceOutput;

  // Hardcoded prompt for diagnosis
  String _prompt = "";

  setPrompt() {
    _prompt =  "You are an AI mechanic. Your role is to diagnose the health of a vehicle, given its diagnostic trouble codes and recommend further action. The vehicle has the following diagnostic trouble codes: ${widget.dtcs.join(', ')}";
  }

  @override
  void initState() {
    super.initState();
    setPrompt();
    _initializeModelAndRunInference();
  }

  @override
  void dispose() {
    super.dispose();
    _gemma.modelManager.deleteModel();
  }

  Future<void> _initializeModelAndRunInference() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (!await _gemma.modelManager.isModelInstalled) {
        final path = kIsWeb
            ? widget.model.url
            : '${(await getApplicationDocumentsDirectory()).path}/${widget.model.filename}';
        await _gemma.modelManager.setModelPath(path);
      }

      final model = await _gemma.createModel(
        modelType: widget.model.modelType,
        preferredBackend: widget.model.preferredBackend,
        maxTokens: 1024,
        supportImage: widget.model.supportImage,
        maxNumImages: widget.model.maxNumImages,
      );

      chat = await model.createChat(
        temperature: widget.model.temperature,
        randomSeed: 1,
        topK: widget.model.topK,
        topP: widget.model.topP,
        tokenBuffer: 256,
        supportImage: widget.model.supportImage,
        supportsFunctionCalls: widget.model.supportsFunctionCalls,
        tools: [], // No tools needed for this screen
      );

      setState(() {
        _isModelInitialized = true;
      });

      // Run inference for the hardcoded prompt
      await _runInference(_prompt);
    } catch (e) {
      setState(() {
        _error = 'Error initializing model: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _runInference(String prompt) async {
    if (chat == null) return;

    setState(() {
      _isLoading = true;
      _inferenceOutput = null;
      _error = null;
    });

    try {
      // Add the prompt as user message
      final userMessage = Message.text(text: prompt);
      await chat!.addQuery(userMessage);

      // Collect tokens from streaming async response
      String responseText = '';
      await for (final token in chat!.generateChatResponseAsync()) {
        if (token is TextResponse) {
          responseText += token.token;
          setState(() {
            _inferenceOutput = responseText;
          });
        } else if (token is FunctionCallResponse) {
          // You can handle function calls here if needed
        }
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Inference failed: $e';
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
