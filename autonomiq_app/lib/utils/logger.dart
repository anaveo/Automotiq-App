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
    printer: CallerPrinter(),
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

class CallerPrinter extends LogPrinter {
  @override
  List<String> log(LogEvent event) {
    final trace = StackTrace.current.toString().split('\n');
    final callerLine = trace.length > 4 ? trace[4] : trace[0];
    final callerInfo = _extractCaller(callerLine);

    final level = event.level.name;

    return [
      '[$callerInfo] $level: ${event.message}',
    ];
  }

  String _extractCaller(String line) {
    final match = RegExp(r'#\d+\s+(.+?) \(').firstMatch(line);
    return match != null ? match.group(1) ?? 'unknown' : 'unknown';
  }
}
