import 'package:flutter/material.dart';
import 'package:automotiq_app/services/model_service.dart';
import 'package:automotiq_app/utils/logger.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

class ModelProvider extends ChangeNotifier {
  final ModelService _modelService;
  InferenceChat? _globalAgent;

  // Model download states
  double _downloadProgress = 0.0;
  bool _modelDownloading = false;
  bool _modelDownloaded = false;

  // Model initialization states
  bool _modelInitializing = false;
  bool _modelInitialized = false;

  // Chat initialization states
  bool _chatInitializing = false;
  bool _chatInitialized = false;

  // Inference state
  bool _isResponding = false;
  bool get isResponding => _isResponding;

  String? _downloadError;
  String? _initializeError;

  double get modelDownloadProgress => _downloadProgress;
  bool get isModelDownloading => _modelDownloading;
  bool get isModelDownloaded => _modelDownloaded;

  bool get isModelInitializing => _modelInitializing;
  bool get isModelInitialized => _modelInitialized;

  bool get isChatInitializing => _chatInitializing;
  bool get isChatInitialized => _chatInitialized;

  String? get downloadError => _downloadError;
  String? get initializeError => _initializeError;

  InferenceModel? get inferenceModel => _modelService.inferenceModel;
  InferenceChat? get globalAgent => _globalAgent;

  ModelProvider({required String variant}) : _modelService = ModelService(variant: variant) {
    startModelDownload();
  }

  Future<void> startModelDownload() async {
    if (_modelDownloading || _modelDownloaded) {
      AppLogger.logInfo('Model already downloading or downloaded');
      return;
    }
    try {
      _modelDownloading = true;
      _downloadError = null;
      notifyListeners();

      if (await _modelService.checkModelExistence()) {
        AppLogger.logInfo('Model already exists');
      } else {
        AppLogger.logInfo('Starting model download');
        await _modelService.downloadModel(
          onProgress: (progress) {
            _downloadProgress = progress;
            notifyListeners();
          },
        );
      }
      _modelDownloaded = true;
      AppLogger.logInfo('Model download completed');
    } catch (e) {
      AppLogger.logError(e);
      _downloadError = 'Failed to download model: $e';
      notifyListeners();
      rethrow;
    } finally {
      _modelDownloading = false;
      notifyListeners();
    }
  }

  Future<void> initializeModel() async {
    if (_modelInitializing || _modelInitialized) {
      AppLogger.logInfo('Model already initializing or initialized');
      return;
    }
    try {
      _modelInitializing = true;
      _initializeError = null;
      notifyListeners();

      await _modelService.initializeModel();

      _modelInitialized = true;
      AppLogger.logInfo('Model initialized successfully');
    } catch (e) {
      AppLogger.logError(e);
      _initializeError = 'Failed to initialize model: $e';
      rethrow;
    } finally {
      _modelInitializing = false;
      notifyListeners();
    }
  }

  Future<void> initializeGlobalChat() async {
    if (_chatInitializing || _chatInitialized) {
      AppLogger.logInfo('Global chat already initializing or initialized');
      return;
    }
    try {
      _chatInitializing = true;
      _initializeError = null;
      notifyListeners();

      _globalAgent = await _modelService.createChat(
        temperature: _modelService.modelConfig.temperature,
        topK: _modelService.modelConfig.topK,
        supportImage: true,
        supportsFunctionCalls: _modelService.modelConfig.supportsFunctionCalls,
      );

      _chatInitialized = true;
      AppLogger.logInfo('Global chat initialized successfully');
    } catch (e) {
      AppLogger.logError(e);
      _initializeError = 'Failed to initialize global chat: $e';
      rethrow;
    } finally {
      _chatInitializing = false;
      notifyListeners();
    }
  }

  Future<void> handleUserMessage(
    Message message,
    List<Map<String, dynamic>> messages,
    Function(String) onToken,
  ) async {
    if (_globalAgent == null) return;

    _isResponding = true;
    notifyListeners();

    final chat = _globalAgent!;
    await chat.addQueryChunk(message);
    final responseStream = chat.generateChatResponseAsync();

    String fullResponse = '';

    try {
      await for (final response in responseStream) {
        if (response is TextResponse) {
          fullResponse += response.token;
          onToken(fullResponse);
        } else if (response is FunctionCallResponse) {
          final finalResponse = await chat.generateChatResponse();
          fullResponse = finalResponse.toString();
          onToken(fullResponse);
        }
      }
    } catch (e) {
      AppLogger.logError(e);
      onToken('Error: $e');
    } finally {
      _isResponding = false;
      notifyListeners();
    }
  }

  Future<InferenceChat> createChat({
    double? temperature,
    int? randomSeed,
    int? topK,
    bool? supportImage,
    List<Tool>? tools,
    bool? supportsFunctionCalls,
  }) async {
    return _modelService.createChat(
      temperature: temperature,
      randomSeed: randomSeed,
      topK: topK,
      supportImage: supportImage,
      tools: tools,
      supportsFunctionCalls: supportsFunctionCalls,
    );
  }

  Future<void> resetChat() async {
    await _globalAgent?.clearHistory();
  }

  Future<void> closeModel() async {
    try {
      if (_globalAgent != null) {
        _globalAgent = null;
        _chatInitialized = false;
        AppLogger.logInfo('Global chat closed');
      }
      await _modelService.closeModel();
      _modelInitialized = false;
      notifyListeners();
    } catch (e) {
      AppLogger.logError(e);
      rethrow;
    }
  }

  @override
  void dispose() {
    closeModel();
    super.dispose();
  }
}
