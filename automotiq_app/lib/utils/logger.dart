import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

// Custom FileOutput to write logs to a file
class CustomFileOutput extends LogOutput {
  File? _file;

  @override
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
      // CustomFileOutput()..init(),
    ]),
    filter: ProductionFilter(), // Log all levels in debug, filter in production
  );

  static void logInfo(String message, [String? context]) {
    _logger.i(
      '${context != null ? '[$context] ' : ''}Info: $message',
    );
  }

  static void logWarning(String message, [String? context]) {
    _logger.w(
      '${context != null ? '[$context] ' : ''}Warning: $message',
    );
  }
  
  static void logError(dynamic error, StackTrace? stackTrace, [String? context]) {
    _logger.e(
      '${context != null ? '[$context] ' : ''}Error: $error',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

class CallerPrinter extends LogPrinter {
  // ANSI color codes: 31=red, 33=yellow, 34=blue, 36=cyan, 32=green
  final AnsiColor _errorColor   = AnsiColor.fg(1);
  final AnsiColor _warningColor = AnsiColor.fg(3);
  final AnsiColor _infoColor    = AnsiColor.fg(4);
  final AnsiColor _debugColor   = AnsiColor.fg(7);
  final AnsiColor _verboseColor = AnsiColor.fg(7);

  @override
  List<String> log(LogEvent event) {
    final trace = StackTrace.current.toString().split('\n');
    final callerLine = trace.length > 4 ? trace[4] : trace[0];
    final callerInfo = _extractCaller(callerLine);

    var output = '[$callerInfo] ${event.level.name}: ${event.message}';

    switch (event.level) {
      case Level.error:
        output = _errorColor(output);
        break;
      case Level.warning:
        output = _warningColor(output);
        break;
      case Level.info:
        output = _infoColor(output);
        break;
      case Level.debug:
        output = _debugColor(output);
        break;
      case Level.verbose:
        output = _verboseColor(output);
        break;
      default:
        break;
    }

    return [output];
  }

  String _extractCaller(String line) {
    final match = RegExp(r'#\d+\s+(.+?) \(').firstMatch(line);
    return match != null ? match.group(1)! : 'unknown';
  }
}
