import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

// Custom FileOutput to write logs to a file
class CustomFileOutput extends LogOutput {
  File? _file;

  Future<void> init() async {
    final directory = await getApplicationDocumentsDirectory();
    _file = File('${directory.path}/app.log');
  }

  @override
  void output(OutputEvent event) {
    if (_file == null) return;
    final message = event.lines.join('\n');
    try {
      _file!.writeAsStringSync('$message\n', mode: FileMode.append);
    } catch (e) {
      debugPrint('Failed to write to log file: $e');
    }
  }
}

// Singleton Logger instance
class AppLogger {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 1, // Show calling function
      errorMethodCount: 5, // More stack trace for errors
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTime,
    ),
    output: MultiOutput([
      ConsoleOutput(),
      // TODO: Uncomment when ready to use file logging
      // CustomFileOutput()..init(),
    ]),
    filter: ProductionFilter(), // Log all levels in debug, filter in production
  );

  static void logInfo(String message, [String? context]) {
    _logger.i(
      '${context != null ? '[$context] ' : ''}Info: $message',
    );
  }
  
  static void logError(dynamic error, StackTrace stackTrace, [String? context]) {
    _logger.e(
      '${context != null ? '[$context] ' : ''}Error: $error',
      error: error,
      stackTrace: stackTrace,
    );
  }
}