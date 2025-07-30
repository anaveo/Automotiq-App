import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

/// Custom FileOutput to write logs to a file
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

/// Singleton Logger instance
class AppLogger {
  static final Logger _logger = Logger(
    printer: CallerPrinter(),
    output: MultiOutput([
      ConsoleOutput(),
      // CustomFileOutput()..init(), // enable if file logging needed
    ]),
    filter: ProductionFilter(),
  );

  /// Backward compatible: accepts [context] but ignores it
  static void logInfo(String message, [String? context]) {
    _logger.i(message);
  }

  static void logWarning(String message, [String? context]) {
    _logger.w(message);
  }

  static void logError(dynamic error, [StackTrace? stackTrace, String? context]) {
    _logger.e(error.toString(), error: error, stackTrace: stackTrace);
  }
}

/// Custom printer with caller detection
class CallerPrinter extends LogPrinter {
  final AnsiColor _errorColor   = AnsiColor.fg(1);
  final AnsiColor _warningColor = AnsiColor.fg(3);
  final AnsiColor _infoColor    = AnsiColor.fg(4);
  final AnsiColor _debugColor   = AnsiColor.fg(7);
  final AnsiColor _verboseColor = AnsiColor.fg(7);

  @override
  List<String> log(LogEvent event) {
    final callerInfo = _getCallerInfo();

    // Build output in the desired format
    final output = '[$callerInfo] ${_capitalize(event.level.name)}: ${event.message}';

    // Apply colors
    switch (event.level) {
      case Level.error:
        return [_errorColor(output)];
      case Level.warning:
        return [_warningColor(output)];
      case Level.info:
        return [_infoColor(output)];
      case Level.debug:
        return [_debugColor(output)];
      case Level.verbose:
        return [_verboseColor(output)];
      default:
        return [output];
    }
  }

String _getCallerInfo() {
  final trace = StackTrace.current.toString().split('\n');

  for (final line in trace) {
    // Skip any internal logger frames
    if (line.contains('AppLogger.') || line.contains('CallerPrinter.') || line.contains('Logger.')) {
      continue;
    }

    // Extract class + function from the first external frame
    final match = RegExp(r'#\d+\s+([^\s]+) \(').firstMatch(line);
    if (match != null) {
      final raw = match.group(1)!;
      return raw
          .replaceAll('<anonymous closure>', '()')
          .replaceAll('.<anonymous closure>', '()');
    }
  }

  return 'Unknown';
}

  String _capitalize(String text) =>
      text.isNotEmpty ? text[0].toUpperCase() + text.substring(1) : text;
}
