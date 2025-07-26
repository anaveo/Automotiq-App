import 'package:flutter/material.dart';
import 'package:automotiq_app/services/model_download_service.dart';
import 'package:automotiq_app/utils/logger.dart';

class ModelDownloadProvider extends ChangeNotifier {
  final ModelDownloadService _modelService;
  double _downloadProgress = 0.0;
  bool _isDownloading = false;
  bool _isModelDownloaded = false;
  String? _downloadError;

  double get downloadProgress => _downloadProgress;
  bool get isDownloading => _isDownloading;
  bool get isModelDownloaded => _isModelDownloaded;
  String? get downloadError => _downloadError;

  ModelDownloadProvider({
    required String modelUrl,
    required String modelFilename,
    required String licenseUrl,
    required String apiToken,
  }) : _modelService = ModelDownloadService(
          modelUrl: modelUrl,
          modelFilename: modelFilename,
          licenseUrl: licenseUrl,
          apiToken: apiToken,
        ) {
    _checkModelExistence();
  }

  Future<void> _checkModelExistence() async {
    try {
      _isModelDownloaded = await _modelService.checkModelExistence();
      notifyListeners();
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'ModelDownloadProvider._checkModelExistence');
      _downloadError = e.toString();
      notifyListeners();
    }
  }

  Future<void> initializeModel() async {
    await _checkModelExistence();

    if (_isModelDownloaded) {
      AppLogger.logInfo('Existing model found', 'ModelDownloadProvider.initializeModel');
      return;
    }
    if (_isDownloading) {
      AppLogger.logWarning('Method called while model is downloading', 'ModelDownloadProvider.initializeModel');
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
      AppLogger.logInfo('Model download completed', 'ModelDownloadProvider.initializeModel');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'ModelDownloadProvider.initializeModel');
      _downloadError = e.toString();
      rethrow;
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }
}