import 'dart:io';
import 'package:automotiq_app/models/model_config_object.dart';
import 'package:automotiq_app/utils/logger.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ModelService {
  final ModelConfigObject _modelConfig;
  InferenceModel? _inferenceModel;
  bool _isModelInitialized = false;
  String? _downloadError;

  ModelService({required String variant})
      : _modelConfig = ModelConfigObject.values.firstWhere(
          (e) => e.name == (variant.isEmpty ? dotenv.env['GEMMA_MODEL_CONFIG'] : variant),
          orElse: () => throw Exception('Model variant $variant not found in GemmaModel enum'),
        );

  String? get downloadError => _downloadError;
  ModelConfigObject get modelConfig => _modelConfig;

  Future<String> _getFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/${modelConfig.filename}';
  }

  Future<bool> checkModelExistence() async {
    try {
      final filePath = await _getFilePath();
      final file = File(filePath);

      AppLogger.logInfo('Checking model at path: $filePath', 'ModelService.checkModelExistence');
      return file.existsSync();
      
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'ModelService.checkModelExistence');
      return false;
    }
  }

  Future<void> downloadModel({required Function(double) onProgress}) async {
    http.StreamedResponse? response;
    IOSink? fileSink;

    try {
      _downloadError = null;
      final filePath = await _getFilePath();
      final file = File(filePath);

      int downloadedBytes = 0;
      if (file.existsSync()) {
        downloadedBytes = await file.length();
      }

      final request = http.Request('GET', Uri.parse(modelConfig.url));
      request.headers['Authorization'] = 'Bearer ${dotenv.env['HUGGINGFACE_API_KEY']}';

      if (downloadedBytes > 0) {
        request.headers['Range'] = 'bytes=$downloadedBytes-';
      }

      response = await request.send().timeout(const Duration(seconds: 30));
      if (response.statusCode == 200 || response.statusCode == 206) {
        final contentLength = response.contentLength ?? 0;
        final totalBytes = downloadedBytes + contentLength;
        fileSink = file.openWrite(mode: FileMode.append);

        int received = downloadedBytes;

        await for (final chunk in response.stream) {
          fileSink.add(chunk);
          received += chunk.length;
          onProgress(totalBytes > 0 ? received / totalBytes : 0.0);
        }
      } else {
        final errorBody = await response.stream.bytesToString();
        _downloadError = 'Status code ${response.statusCode}: $errorBody';
        AppLogger.logError(_downloadError, null, 'ModelService.downloadModel');
        throw HttpException(_downloadError!);
      }
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'ModelService.downloadModel');
      _downloadError = 'Failed to download model: $e';
      rethrow;
    } finally {
      if (fileSink != null) await fileSink.close();
    }
  }

  Future<void> initializeModel() async {
    try {
      if (_isModelInitialized && _inferenceModel != null) {
        AppLogger.logInfo('Model already initialized', 'ModelService.initializeModel');
        return;
      }

      final filePath = await _getFilePath();
      final file = File(filePath);
      if (!file.existsSync()) {
        throw Exception('Model file not found at $filePath');
      }

      final gemma = FlutterGemmaPlugin.instance;
      final modelManager = gemma.modelManager;
      await modelManager.setModelPath(filePath);

      _inferenceModel = await gemma.createModel(
        modelType: modelConfig.modelType,
        preferredBackend: modelConfig.preferredBackend,
        maxTokens: modelConfig.maxTokens,
        supportImage: modelConfig.supportImage,
        maxNumImages: modelConfig.maxNumImages ?? 0,
      );

      _isModelInitialized = true;
      AppLogger.logInfo('Model initialized successfully', 'ModelService.initializeModel');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'ModelService.initializeModel');
      _isModelInitialized = false;
      _inferenceModel = null;
      rethrow;
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
    // Use enum defaults if parameters are not provided
    temperature ??= modelConfig.temperature;
    randomSeed ??= 1;
    topK ??= modelConfig.topK;
    supportImage ??= false; // Default to false
    supportsFunctionCalls ??= modelConfig.supportsFunctionCalls;

    if (!_isModelInitialized || _inferenceModel == null) {
      await initializeModel();
    }
    try {
      final chat = await _inferenceModel!.createChat(
        temperature: temperature,
        randomSeed: randomSeed,
        topK: topK,
        supportImage: supportImage,
        tools: tools ?? [],
        supportsFunctionCalls: supportsFunctionCalls,
      );
      AppLogger.logInfo('Chat instance created', 'ModelService.createChat');
      return chat;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'ModelService.createChat');
      rethrow;
    }
  }

  Future<void> closeModel() async {
    if (_inferenceModel != null) {
      try {
        await _inferenceModel!.close();
        _inferenceModel = null;
        _isModelInitialized = false;
        AppLogger.logInfo('Model closed successfully', 'ModelService.closeModel');
      } catch (e, stackTrace) {
        AppLogger.logError(e, stackTrace, 'ModelService.closeModel');
        rethrow;
      }
    }
  }

  InferenceModel? get inferenceModel => _inferenceModel;
  bool get isModelInitialized => _isModelInitialized;
}