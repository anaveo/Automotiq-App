import 'dart:io';

import 'package:automotiq_app/models/gemma_model.dart';
import 'package:automotiq_app/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ModelService {
  final GemmaModel model;

  ModelService({
    required String variant,
  }) : model = GemmaModel.values.firstWhere(
         (e) => e.name == variant,
         orElse: () => throw Exception('Model variant $variant not found in Model enum'),
       );

  /// Helper method to get the file path.
  Future<String> _getFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/${model.filename}';
  }

  /// Checks if the model file exists and matches the remote file size.
  Future<bool> checkModelExistence() async {
    try {
      final filePath = await _getFilePath();
      final file = File(filePath);
      AppLogger.logInfo("Path: ${filePath}");
      final headers = {'Authorization': 'Bearer ${dotenv.env['HUGGINGFACE_API_KEY']}'};
      final headResponse = await http.head(Uri.parse(model.url), headers: headers);

      if (headResponse.statusCode == 200) {
        final contentLengthHeader = headResponse.headers['content-length'];
        if (contentLengthHeader != null) {
          final remoteFileSize = int.parse(contentLengthHeader);
          if (file.existsSync() && await file.length() == remoteFileSize) {
            return true;
          }
        }
      }
    } catch (e) {
        AppLogger.logError('Error checking model existence: $e', null, 'ModelService.checkModelExistence');
    }
    return false;
  }

  /// Downloads the model file and tracks progress.
  Future<void> downloadModel({
    required Function(double) onProgress,
  }) async {
    http.StreamedResponse? response;
    IOSink? fileSink;

    try {
      final filePath = await _getFilePath();
      final file = File(filePath);

      int downloadedBytes = 0;
      if (file.existsSync()) {
        downloadedBytes = await file.length();
      }

      final request = http.Request('GET', Uri.parse(model.url));
      request.headers['Authorization'] = 'Bearer ${dotenv.env['HUGGINGFACE_API_KEY']}';

      if (downloadedBytes > 0) {
        request.headers['Range'] = 'bytes=$downloadedBytes-';
      }

      response = await request.send();
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
        if (kDebugMode) {
          AppLogger.logError('Failed to download model. Status code: ${response.statusCode}', null, 'ModelService.downloadModel');
          try {
            final errorBody = await response.stream.bytesToString();
            AppLogger.logInfo('Error body: $errorBody');
          } catch (e) {
            AppLogger.logError('Could not read error body: $e', null, 'ModelService.downloadModel');
          }
        }
        throw HttpException('Status code ${response.statusCode}');
      }
    } catch (e) {
        AppLogger.logError('Error downloading model: $e', null, 'ModelService.checkModelExistence');
      rethrow;
    } finally {
      if (fileSink != null) await fileSink.close();
    }
  }
}