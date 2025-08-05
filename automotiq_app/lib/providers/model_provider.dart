import 'package:flutter/material.dart';
import 'package:automotiq_app/services/model_service.dart';
import 'package:automotiq_app/utils/logger.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

/// Manages the state of machine learning model download, initialization, and chat functionality.
class ModelProvider extends ChangeNotifier {
  final ModelService _modelService;
  InferenceChat? _globalAgent;

  /// Tracks download progress (0.0 to 1.0).
  double _downloadProgress = 0.0;

  /// Indicates if the model is currently downloading.
  bool _modelDownloading = false;

  /// Indicates if the model has been downloaded.
  bool _modelDownloaded = false;

  /// Indicates if the model is currently initializing.
  bool _modelInitializing = false;

  /// Indicates if the model has been initialized.
  bool _modelInitialized = false;

  /// Indicates if the chat is currently initializing.
  bool _chatInitializing = false;

  /// Indicates if the chat has been initialized.
  bool _chatInitialized = false;

  /// Indicates if the model is generating a response.
  bool _isResponding = false;

  /// Current inference model, if initialized.
  InferenceModel? get inferenceModel => _modelService.inferenceModel;

  /// Global chat instance for user interactions.
  InferenceChat? get globalAgent => _globalAgent;

  /// Progress of model download (0.0 to 1.0).
  double get modelDownloadProgress => _downloadProgress;

  /// Indicates if the model is downloading.
  bool get isModelDownloading => _modelDownloading;

  /// Indicates if the model has been downloaded.
  bool get isModelDownloaded => _modelDownloaded;

  /// Indicates if the model is initializing.
  bool get isModelInitializing => _modelInitializing;

  /// Indicates if the model has been initialized.
  bool get isModelInitialized => _modelInitialized;

  /// Indicates if the chat is initializing.
  bool get isChatInitializing => _chatInitializing;

  /// Indicates if the chat has been initialized.
  bool get isChatInitialized => _chatInitialized;

  /// Indicates if the model is generating a response.
  bool get isResponding => _isResponding;

  /// Error message from download failure, if any.
  String? _downloadError;

  /// Error message from initialization failure, if any.
  String? _initializeError;

  /// Gets the download error, if any.
  String? get downloadError => _downloadError;

  /// Gets the initialization error, if any.
  String? get initializeError => _initializeError;

  /// Constructor for ModelProvider.
  ///
  /// [variant] specifies the model variant to use.
  ModelProvider({required String variant})
    : _modelService = ModelService(variant: variant) {
    startModelDownload();
  }

  /// Initiates the model download process.
  ///
  /// Skips if already downloading or downloaded.
  /// Updates progress and notifies listeners.
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

  /// Initializes the machine learning model.
  ///
  /// Skips if already initializing or initialized.
  /// Notifies listeners on state changes.
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

  /// Initializes the global chat instance for user interactions.
  ///
  /// Skips if already initializing or initialized.
  /// Configures chat with model settings.
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

  /// Handles user messages and generates responses using the global chat.
  ///
  /// [message] is the user's input.
  /// [messages] is the conversation history.
  /// [onToken] is called with response tokens as they are generated.
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

  /// Creates a new chat instance with custom settings.
  ///
  /// Allows configuration of [temperature], [randomSeed], [topK], [supportImage], [tools], and [supportsFunctionCalls].
  /// Returns a new [InferenceChat] instance.
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

  /// Clears the global chat's conversation history.
  Future<void> resetChat() async {
    await _globalAgent?.clearHistory();
  }

  /// Closes the model and resets chat state.
  ///
  /// Clears [_globalAgent] and resets initialization flags.
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

  /// Disposes of resources and closes the model.
  @override
  void dispose() {
    closeModel();
    super.dispose();
  }
}
