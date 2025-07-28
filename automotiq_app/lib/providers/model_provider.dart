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
      AppLogger.logInfo('Model already downloading or downloaded', 'ModelProvider.startModelDownload');
      return;
    }
    try {
      _modelDownloading = true;
      _downloadError = null;
      notifyListeners();

      if (await _modelService.checkModelExistence()) {
        AppLogger.logInfo('Model already exists', 'ModelProvider.startModelDownload');
      } else {
        AppLogger.logInfo('Starting model download', 'ModelProvider.startModelDownload');
        await _modelService.downloadModel(
          onProgress: (progress) {
            _downloadProgress = progress;
            notifyListeners();
          },
        );
      }
      _modelDownloaded = true;
      AppLogger.logInfo('Model download completed', 'ModelProvider.startModelDownload');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'ModelProvider.startModelDownload');
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
      AppLogger.logInfo('Model already initializing or initialized', 'ModelProvider.initializeModel');
      return;
    }
    try {
      _modelInitializing = true;
      _initializeError = null;
      notifyListeners();

      await _modelService.initializeModel();

      _modelInitialized = true;
      AppLogger.logInfo('Model initialized successfully', 'ModelProvider.initializeModel');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'ModelProvider.initializeModel');
      _initializeError = 'Failed to initialize model: $e';
      rethrow;
    } finally {
      _modelInitializing = false;
      notifyListeners();
    }
  }

  Future<void> initializeGlobalChat() async {
    if (_chatInitializing || _chatInitialized) {
      AppLogger.logInfo('Global chat already initializing or initialized', 'ModelProvider.initializeGlobalChat');
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
      AppLogger.logInfo('Global chat initialized successfully', 'ModelProvider.initializeGlobalChat');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'ModelProvider.initializeGlobalChat');
      _initializeError = 'Failed to initialize global chat: $e';
      rethrow;
    } finally {
      _chatInitializing = false;
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

  // TODO: Add selective delete! the function contains a usable replayHistory argument
  Future<void> resetChat() async {
    await globalAgent?.clearHistory();
  }

  Future<void> closeModel() async {
    try {
      if (_globalAgent != null) {
        _globalAgent = null; // Chat closed by inferenceModel.close()
        _chatInitialized = false;
        AppLogger.logInfo('Global chat closed', 'ModelProvider.closeModel');
      }
      await _modelService.closeModel();
      _modelInitialized = false;
      notifyListeners();
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'ModelProvider.closeModel');
      rethrow;
    }
  }

  @override
  void dispose() {
    closeModel();
    super.dispose();
  }
}