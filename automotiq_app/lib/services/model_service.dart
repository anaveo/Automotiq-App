import 'dart:io';

import 'package:automotiq_app/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ModelService {
  final String modelUrl;
  final String modelFilename;
  final String apiToken;

  ModelService({
    required this.modelUrl,
    required this.modelFilename,
    required this.apiToken,
  });

  /// Helper method to get the file path.
  Future<String> _getFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$modelFilename';
  }

  /// Checks if the model file exists and matches the remote file size.
  Future<bool> checkModelExistence() async {
    try {
      final filePath = await _getFilePath();
      final file = File(filePath);
      AppLogger.logInfo("Path: ${filePath}");
      final headers = {'Authorization': 'Bearer $apiToken'};
      final headResponse = await http.head(Uri.parse(modelUrl), headers: headers);

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
      if (kDebugMode) {
        print('Error checking model existence: $e');
      }
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

      final request = http.Request('GET', Uri.parse(modelUrl));
      request.headers['Authorization'] = 'Bearer $apiToken';

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
          print('Failed to download model. Status code: ${response.statusCode}');
          print('Headers: ${response.headers}');
          try {
            final errorBody = await response.stream.bytesToString();
            print('Error body: $errorBody');
          } catch (e) {
            print('Could not read error body: $e');
          }
        }
        throw Exception('Failed to download the model.');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error downloading model: $e');
      }
      rethrow;
    } finally {
      if (fileSink != null) await fileSink.close();
    }
  }
}