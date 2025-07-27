import 'package:flutter/material.dart';
import 'package:automotiq_app/services/model_service.dart';
import 'package:automotiq_app/utils/logger.dart';

class ModelProvider extends ChangeNotifier {
  final ModelService _modelService;
  double _downloadProgress = 0.0;
  bool _isDownloading = false;
  bool _isModelDownloaded = false;
  String? _downloadError;

  double get downloadProgress => _downloadProgress;
  bool get isDownloading => _isDownloading;
  bool get isModelDownloaded => _isModelDownloaded;
  String? get downloadError => _downloadError;

  ModelProvider({
    required String modelUrl,
    required String modelFilename,
    required String licenseUrl,
    required String apiToken,
  }) : _modelService = ModelService(
          modelUrl: modelUrl,
          modelFilename: modelFilename,
          apiToken: apiToken,
        ) {
    _checkModelExistence();
  }

  Future<void> _checkModelExistence() async {
    try {
      _isModelDownloaded = await _modelService.checkModelExistence();
      notifyListeners();
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'ModelProvider._checkModelExistence');
      _downloadError = e.toString();
      notifyListeners();
    }
  }

  Future<void> initializeModel() async {
    await _checkModelExistence();

    if (_isModelDownloaded) {
      AppLogger.logInfo('Existing model found', 'ModelProvider.initializeModel');
      return;
    }
    if (_isDownloading) {
      AppLogger.logWarning('Method called while model is downloading', 'ModelProvider.initializeModel');
      return;
    }

    try {
      _isDownloading = true;
      _downloadError = null;
      notifyListeners();

      await _modelService.downloadModel(
        onProgress: (progress) {
          _downloadProgress = progress;
          notifyListeners();
        },
      );

      _isModelDownloaded = true;
      AppLogger.logInfo('Model download completed', 'ModelProvider.initializeModel');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'ModelProvider.initializeModel');
      _downloadError = e.toString();
      rethrow;
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }
}