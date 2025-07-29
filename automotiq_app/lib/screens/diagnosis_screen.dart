import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:automotiq_app/providers/model_provider.dart';
import 'package:automotiq_app/utils/logger.dart';
import '../services/unified_background_service.dart';

class DiagnosisScreen extends StatefulWidget {
  const DiagnosisScreen({super.key, this.dtcs = const []});

  final List<String> dtcs;

  @override
  DiagnosisScreenState createState() => DiagnosisScreenState();
}

class DiagnosisScreenState extends State<DiagnosisScreen> with WidgetsBindingObserver {
  late UnifiedBackgroundService _backgroundService;
  String? _currentDiagnosisId;
  List<String> _lastProcessedDtcs = [];
  bool _isInitialized = false;
  bool _wasInferenceRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _backgroundService = UnifiedBackgroundService();
    _initializeDiagnosis();
  }

  @override
  void didUpdateWidget(DiagnosisScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (!_listEquals(oldWidget.dtcs, widget.dtcs)) {
      AppLogger.logInfo('DTCs changed from ${oldWidget.dtcs} to ${widget.dtcs}', 'DiagnosisScreen.didUpdateWidget');
      _handleDtcChange();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        AppLogger.logInfo('App resumed, checking diagnosis status', 'DiagnosisScreen.didChangeAppLifecycleState');
        if (_isInitialized && !_listEquals(_lastProcessedDtcs, widget.dtcs)) {
          AppLogger.logInfo('DTCs changed while app was backgrounded', 'DiagnosisScreen.didChangeAppLifecycleState');
          _handleDtcChange();
        }
        break;
      case AppLifecycleState.paused:
        AppLogger.logInfo('App backgrounded, diagnosis inference continues', 'DiagnosisScreen.didChangeAppLifecycleState');
        break;
      default:
        break;
    }
  }

  Future<void> _checkAndStartInferenceIfNeeded() async {
    if (!mounted || widget.dtcs.isEmpty) return;
    
    final existingDiagnosis = _backgroundService.getDiagnosisForDtcs(widget.dtcs);
    
    if (existingDiagnosis == null) {
      AppLogger.logInfo('No diagnosis found for current DTCs after inference completion, starting new inference', 'DiagnosisScreen._checkAndStartInferenceIfNeeded');
      _runInferenceSafelyWithChatCheck();
    } else if (!existingDiagnosis.isComplete && !_backgroundService.isInferenceActiveForDtcs(widget.dtcs)) {
      AppLogger.logInfo('Incomplete diagnosis found for current DTCs, restarting inference', 'DiagnosisScreen._checkAndStartInferenceIfNeeded');
      _runInferenceSafelyWithChatCheck();
    }
  }

  // Enhanced safe inference method that never shows queue-related errors to users and waits for chat initialization
  Future<void> _runInferenceSafelyWithChatCheck({bool forceRerun = false}) async {
    if (widget.dtcs.isEmpty) return;

    final modelProvider = Provider.of<ModelProvider>(context, listen: false);
    
    // If chat is not initialized, wait for it
    if (!modelProvider.isChatInitialized || modelProvider.globalAgent == null) {
      AppLogger.logInfo('Global chat not initialized, waiting for initialization', 'DiagnosisScreen._runInferenceSafelyWithChatCheck');
      
      // Set up a periodic check to wait for chat initialization
      _scheduleRetryWhenChatInitialized();
      return;
    }

    // Chat is initialized, proceed with normal inference
    return _runInferenceSafely(forceRerun: forceRerun);
  }

  // Schedule periodic retries when chat becomes initialized
  void _scheduleRetryWhenChatInitialized() async {
    // Wait a bit before checking again
    await Future.delayed(const Duration(seconds: 1));
    
    if (!mounted || widget.dtcs.isEmpty) return;
    
    final modelProvider = Provider.of<ModelProvider>(context, listen: false);
    
    // Check if chat is still not initialized
    if (!modelProvider.isChatInitialized || modelProvider.globalAgent == null) {
      // Chat still not ready, schedule another check
      _scheduleRetryWhenChatInitialized();
      return;
    }
    
    // Chat is now initialized, proceed with diagnosis
    AppLogger.logInfo('Global chat became initialized, starting diagnosis for DTCs: ${widget.dtcs.join(', ')}', 'DiagnosisScreen._scheduleRetryWhenChatInitialized');
    _runInferenceSafely();
  }
  // Enhanced safe inference method that never shows queue-related errors to users
  Future<void> _runInferenceSafely({bool forceRerun = false}) async {
    if (widget.dtcs.isEmpty) return;

    final modelProvider = Provider.of<ModelProvider>(context, listen: false);
    if (!modelProvider.isChatInitialized || modelProvider.globalAgent == null) {
      AppLogger.logError('Global chat not initialized', null, 'DiagnosisScreen._runInferenceSafely');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat not initialized. Please try again.')),
      );
      return;
    }

    // Check if agent is busy or there's chat inference running
    if (_backgroundService.isAgentBusy || _backgroundService.hasChatInference) {
      AppLogger.logInfo('Agent busy or chat active, will queue diagnosis for DTCs: ${widget.dtcs.join(', ')}', 'DiagnosisScreen._runInferenceSafely');
      
      // Create a temporary diagnosis result to show queued state
      final diagnosisKey = _backgroundService.generateDiagnosisKey(widget.dtcs);
      final tempDiagnosisId = '${diagnosisKey}_${DateTime.now().millisecondsSinceEpoch}';
      
      if (mounted) {
        setState(() {
          _currentDiagnosisId = tempDiagnosisId;
        });
      }
      
      // Set up a periodic check to retry when agent becomes available
      _scheduleRetryWhenAgentAvailable();
      return;
    }

    try {
      // Create a placeholder diagnosis result to show queued state immediately
      final diagnosisKey = _backgroundService.generateDiagnosisKey(widget.dtcs);
      final tempDiagnosisId = '${diagnosisKey}_${DateTime.now().millisecondsSinceEpoch}';
      
      if (mounted) {
        setState(() {
          _currentDiagnosisId = tempDiagnosisId;
        });
      }

      AppLogger.logInfo('Starting diagnosis inference for DTCs: ${widget.dtcs.join(', ')}', 'DiagnosisScreen._runInferenceSafely');

      final diagnosisId = await _backgroundService.runDiagnosis(
        dtcs: widget.dtcs,
        chat: modelProvider.globalAgent!,
        forceRerun: forceRerun,
      );
      
      if (mounted) {
        setState(() {
          _currentDiagnosisId = diagnosisId;
        });
      }

      AppLogger.logInfo('Diagnosis inference completed successfully for DTCs: ${widget.dtcs.join(', ')}', 'DiagnosisScreen._runInferenceSafely');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'DiagnosisScreen._runInferenceSafely');
      
      // Categorize the error type
      final errorMessage = e.toString().toLowerCase();
      final isQueueError = errorMessage.contains('queue') || 
                          errorMessage.contains('busy') || 
                          errorMessage.contains('already running') ||
                          errorMessage.contains('waiting') ||
                          errorMessage.contains('request cancelled') ||
                          errorMessage.contains('agent is currently') ||
                          errorMessage.contains('inference');
      
      final isNetworkError = errorMessage.contains('network') ||
                            errorMessage.contains('connection') ||
                            errorMessage.contains('timeout');
      
      final isResourceError = errorMessage.contains('memory') ||
                             errorMessage.contains('resource') ||
                             errorMessage.contains('out of');

      if (isQueueError) {
        // For queue errors, schedule a retry and don't show error to user
        AppLogger.logInfo('Diagnosis queued due to system busy: $e', 'DiagnosisScreen._runInferenceSafely');
        _scheduleRetryWhenAgentAvailable();
      } else if (mounted) {
        // Only show error to user for non-queue issues
        String userMessage;
        if (isNetworkError) {
          userMessage = 'Network error. Please check your connection and try again.';
        } else if (isResourceError) {
          userMessage = 'System resources are low. Please try again in a moment.';
        } else {
          userMessage = 'Unable to run diagnosis at this time. Please try again.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userMessage),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _runInferenceSafely(forceRerun: forceRerun),
            ),
          ),
        );
      }
    }
  }

  // Schedule periodic retries when agent becomes available
  void _scheduleRetryWhenAgentAvailable() async {
    // Wait a bit before checking again
    await Future.delayed(const Duration(seconds: 2));
    
    if (!mounted || widget.dtcs.isEmpty) return;
    
    // Check if agent is still busy
    if (_backgroundService.isAgentBusy || _backgroundService.hasChatInference) {
      // Agent still busy, schedule another check
      _scheduleRetryWhenAgentAvailable();
      return;
    }
    
    // Check if we already have a diagnosis or if inference is already running for these DTCs
    final existingDiagnosis = _backgroundService.getDiagnosisForDtcs(widget.dtcs);
    if (existingDiagnosis != null && existingDiagnosis.isComplete && existingDiagnosis.error == null) {
      // We already have a good diagnosis, no need to retry
      return;
    }
    
    if (_backgroundService.isInferenceActiveForDtcs(widget.dtcs)) {
      // Inference already running for these DTCs
      return;
    }
    
    // Agent is available and we need to run diagnosis
    AppLogger.logInfo('Agent became available, retrying diagnosis for DTCs: ${widget.dtcs.join(', ')}', 'DiagnosisScreen._scheduleRetryWhenAgentAvailable');
    _runInferenceSafely();
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _handleDtcChange() async {
    if (!mounted) return;

    AppLogger.logInfo('Handling DTC change from ${_lastProcessedDtcs} to ${widget.dtcs}', 'DiagnosisScreen._handleDtcChange');
    
    _lastProcessedDtcs = List.from(widget.dtcs);
    _currentDiagnosisId = null;
    
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        await _checkAndStartInferenceIfNeeded();
      }
    });
  }

  Future<void> _initializeDiagnosis() async {
    await _backgroundService.initialize();
    
    if (widget.dtcs.isNotEmpty) {
      _lastProcessedDtcs = List.from(widget.dtcs);
      
      final existingDiagnosis = _backgroundService.getDiagnosisForDtcs(widget.dtcs);
      
      if (existingDiagnosis != null) {
        if (mounted) {
          setState(() {
            _currentDiagnosisId = existingDiagnosis.id;
          });
        }
        
        if (!existingDiagnosis.isComplete && !_backgroundService.isInferenceActiveForDtcs(widget.dtcs)) {
          _runInferenceSafelyWithChatCheck();
        }
      } else {
        // For fresh DTCs, always use safe inference to handle queue gracefully
        _runInferenceSafelyWithChatCheck();
      }
    } else {
      if (mounted) {
        setState(() {
          _currentDiagnosisId = null;
        });
      }
    }
    
    _isInitialized = true;
  }

  Future<void> _runInference({bool forceRerun = false}) async {
    if (widget.dtcs.isEmpty) return;

    // Use the safe inference method for user-initiated actions too
    return _runInferenceSafely(forceRerun: forceRerun);
  }

  Future<void> _clearAndRerun() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Re-run Diagnosis?'),
        content: const Text('This will clear the current diagnosis and generate a new one. Any ongoing inference will be stopped.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Re-run'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _backgroundService.clearDiagnosis(widget.dtcs);
      _runInference(forceRerun: true);
    }
  }

  // // Helper method to clean LLM output
String _cleanLlmOutput(String output) {
  String cleaned = output;

  // Remove all LLM-style tags including malformed or attribute-laden tags
  cleaned = cleaned.replaceAll(RegExp(r'<[^>\n]*>', caseSensitive: false), '');
  cleaned = cleaned.replaceAll(RegExp(r'</[^>\n]*', caseSensitive: false), ''); // Catch tags like </endaboration role="assistant"

  // Remove standalone pipe-style delimiters (e.g., <|end|>)
  cleaned = cleaned.replaceAll(RegExp(r'<\|[^|>]+\|>', caseSensitive: false), '');

  // Collapse repeated newlines and spaces
  cleaned = cleaned.replaceAll(RegExp(r'\n\s*\n+'), '\n\n');
  cleaned = cleaned.replaceAll(RegExp(r'[ \t]+'), ' ');

  return cleaned.trim();
}


  // String _cleanLlmOutput(String output) {
  //   String cleaned = output;
    
  //   // Remove various forms of end_of_turn tags (case insensitive)
  //   cleaned = cleaned.replaceAll(RegExp(r'</?end_of_turn>', caseSensitive: false), '');
  //   cleaned = cleaned.replaceAll(RegExp(r'<end_of_turn/?>', caseSensitive: false), '');
  //   cleaned = cleaned.replaceAll(RegExp(r'</end_of_turn>', caseSensitive: false), '');
  //   cleaned = cleaned.replaceAll(RegExp(r'<end_of_turn>', caseSensitive: false), '');
  //   cleaned = cleaned.replaceAll(RegExp(r'</end_of_turn', caseSensitive: false), '');

  //   // Remove various forms of start_turn tags (case insensitive)
  //   cleaned = cleaned.replaceAll(RegExp(r'</?start_turn>', caseSensitive: false), '');
  //   cleaned = cleaned.replaceAll(RegExp(r'<start_turn/?>', caseSensitive: false), '');
  //   cleaned = cleaned.replaceAll(RegExp(r'</start_turn>', caseSensitive: false), '');
  //   cleaned = cleaned.replaceAll(RegExp(r'<start_turn>', caseSensitive: false), '');
    
  //   // Remove other common LLM artifacts
  //   cleaned = cleaned.replaceAll(RegExp(r'<\|im_end\|>', caseSensitive: false), '');
  //   cleaned = cleaned.replaceAll(RegExp(r'<\|im_start\|>', caseSensitive: false), '');
  //   cleaned = cleaned.replaceAll(RegExp(r'<\|endoftext\|>', caseSensitive: false), '');
  //   cleaned = cleaned.replaceAll(RegExp(r'<\|end\|>', caseSensitive: false), '');
  //   cleaned = cleaned.replaceAll(RegExp(r'<\|start\|>', caseSensitive: false), '');
    
  //   // Remove any remaining angle bracket patterns that look like tags
  //   cleaned = cleaned.replaceAll(RegExp(r'<[^>]*end[^>]*>', caseSensitive: false), '');
  //   cleaned = cleaned.replaceAll(RegExp(r'<[^>]*start[^>]*>', caseSensitive: false), '');

  //   // Clean up multiple whitespaces and newlines
  //   cleaned = cleaned.replaceAll(RegExp(r'\n\s*\n\s*\n'), '\n\n'); // Replace multiple newlines with double newline
  //   cleaned = cleaned.replaceAll(RegExp(r'[ \t]+'), ' '); // Replace multiple spaces/tabs with single space
    
  //   // Clean up multiple whitespaces and newlines
  //   cleaned = cleaned.replaceAll(RegExp(r'\n\s*\n\s*\n'), '\n\n'); // Replace multiple newlines with double newline
  //   cleaned = cleaned.replaceAll(RegExp(r'[ \t]+'), ' '); // Replace multiple spaces/tabs with single space
    
  //   // Trim whitespace
  //   cleaned = cleaned.trim();
    
  //   return cleaned;
  // }

  Widget _buildDiagnosisContent(DiagnosisResult? diagnosis, UnifiedBackgroundService backgroundService) {
    if (diagnosis == null) {
      if (widget.dtcs.isEmpty) {
        return Center(
          child: Container(
            padding: const EdgeInsets.all(32.0),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[700]!, width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 48,
                  color: Colors.grey[500],
                ),
                const SizedBox(height: 16),
                Text(
                  'No diagnostic trouble codes provided.',
                  style: TextStyle(
                    fontSize: 16, 
                    color: Colors.grey[400],
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }
      
      // Enhanced status checking with better queue information
      final isActiveForCurrentDtcs = backgroundService.isInferenceActiveForDtcs(widget.dtcs);
      final isAgentBusy = backgroundService.isAgentBusy;
      final queueLength = backgroundService.queueLength;
      final hasChatInference = backgroundService.hasChatInference;
      final hasDiagnosisInference = backgroundService.hasDiagnosisInference;
      
      // Check if chat is initialized
      final modelProvider = Provider.of<ModelProvider>(context, listen: false);
      final isChatInitialized = modelProvider.isChatInitialized && modelProvider.globalAgent != null;
      
      String statusMessage;
      String? subMessage;
      
      if (!isChatInitialized) {
        statusMessage = 'Initializing AI assistant...';
        subMessage = 'Please wait while the chat system starts up.';
      } else if (isActiveForCurrentDtcs && hasDiagnosisInference) {
        statusMessage = 'Analyzing diagnostic codes...';
        subMessage = 'AI is processing your vehicle\'s diagnostic trouble codes.';
      } else if (isActiveForCurrentDtcs && !hasDiagnosisInference) {
        statusMessage = 'Diagnosis queued for processing...';
        if (hasChatInference) {
          subMessage = 'Waiting for the chat assistant to finish, then your diagnosis will begin.';
        } else {
          subMessage = 'Your diagnosis will start shortly.';
        }
      } else if (isAgentBusy || queueLength > 0) {
        statusMessage = 'Waiting for system availability...';
        if (hasChatInference) {
          subMessage = 'The chat assistant is currently active. Your diagnosis will begin when it\'s available.';
        } else if (queueLength > 0) {
          subMessage = queueLength == 1 
              ? 'One operation ahead of you in the queue.'
              : '$queueLength operations ahead of you in the queue.';
        } else {
          subMessage = 'System is processing other requests. Please wait a moment.';
        }
      } else {
        statusMessage = 'Preparing diagnosis...';
        subMessage = 'Setting up the analysis for your diagnostic trouble codes.';
      }
      
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.cyan.withOpacity(0.3), width: 2),
                ),
                child: const CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.cyan,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (subMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  subMessage,
                  style: TextStyle(
                    fontSize: 14, 
                    color: Colors.grey[400],
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 32),
              // Show current DTCs being processed
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[700]!, width: 1),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Colors.amber[400],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Diagnostic Trouble Codes',
                            style: TextStyle(
                              fontWeight: FontWeight.bold, 
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: widget.dtcs.map((dtc) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.amber.withOpacity(0.3)),
                          ),
                          child: Text(
                            dtc,
                            style: TextStyle(
                              color: Colors.amber[300],
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        )).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Check if this diagnosis has a queue-related error that should be handled gracefully
    final hasQueueError = diagnosis.error != null && _isQueueRelatedError(diagnosis.error!);
    
    // If there's a queue-related error, treat it as if diagnosis is still loading/queued
    if (hasQueueError) {
      final isAgentBusy = backgroundService.isAgentBusy;
      final hasChatInference = backgroundService.hasChatInference;
      final queueLength = backgroundService.queueLength;
      
      String statusMessage;
      String? subMessage;
      
      if (hasChatInference) {
        statusMessage = 'Waiting for chat to complete...';
        subMessage = 'Your diagnosis will automatically start when the chat assistant finishes.';
      } else if (isAgentBusy || queueLength > 0) {
        statusMessage = 'Diagnosis will start automatically...';
        subMessage = 'Waiting for the system to become available. No action needed.';
      } else {
        statusMessage = 'Retrying diagnosis...';
        subMessage = 'The system will automatically attempt your diagnosis again.';
      }
      
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.cyan.withOpacity(0.3), width: 2),
                ),
                child: const CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.cyan,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (subMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  subMessage,
                  style: TextStyle(
                    fontSize: 14, 
                    color: Colors.grey[400],
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 32),
              // Show current DTCs being processed
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[700]!, width: 1),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Colors.amber[400],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Diagnostic Trouble Codes',
                            style: TextStyle(
                              fontWeight: FontWeight.bold, 
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: diagnosis.dtcs.map((dtc) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.amber.withOpacity(0.3)),
                          ),
                          child: Text(
                            dtc,
                            style: TextStyle(
                              color: Colors.amber[300],
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        )).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // DTCs Section
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[700]!, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Colors.amber[400],
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Diagnostic Trouble Codes',
                        style: TextStyle(
                          fontWeight: FontWeight.bold, 
                          fontSize: 18,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: diagnosis.dtcs.map((dtc) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.amber.withOpacity(0.3)),
                      ),
                      child: Text(
                        dtc,
                        style: TextStyle(
                          color: Colors.amber[300],
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    )).toList(),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Output Section Header
          Row(
            children: [
              Icon(
                Icons.auto_fix_high,
                color: Colors.cyan[400],
                size: 24,
              ),
              const SizedBox(width: 10),
              const Text(
                'AI Diagnosis',
                style: TextStyle(
                  fontWeight: FontWeight.bold, 
                  fontSize: 20,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[700]!, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (diagnosis.output.isNotEmpty)
                    MarkdownBody(
                      data: _cleanLlmOutput(diagnosis.output),
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(fontSize: 16, height: 1.6, color: Colors.white),
                        h1: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.cyan[300]),
                        h2: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.cyan[400]),
                        h3: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.cyan[400]),
                        h4: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        h5: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                        h6: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        strong: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        em: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey[300]),
                        code: TextStyle(
                          backgroundColor: Colors.grey[800],
                          color: Colors.cyan[300],
                          fontFamily: 'monospace',
                          fontSize: 14,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: Colors.grey[850],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[600]!),
                        ),
                        codeblockPadding: const EdgeInsets.all(16),
                        blockquote: TextStyle(
                          color: Colors.grey[400],
                          fontStyle: FontStyle.italic,
                        ),
                        blockquoteDecoration: BoxDecoration(
                          color: Colors.grey[850],
                          borderRadius: BorderRadius.circular(8),
                          border: Border(
                            left: BorderSide(
                              color: Colors.cyan.withOpacity(0.6),
                              width: 4,
                            ),
                          ),
                        ),
                        blockquotePadding: const EdgeInsets.all(16),
                        listBullet: TextStyle(fontSize: 16, color: Colors.cyan[400]),
                      ),
                    ),
                  
                  // Enhanced loading indicator with queue info
                  if (!diagnosis.isComplete && diagnosis.error == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 20.0),
                      child: _buildProgressIndicator(backgroundService, widget.dtcs),
                    ),
                  
                  // Show error if exists (but only non-queue errors)
                  if (diagnosis.error != null && !_isQueueRelatedError(diagnosis.error!))
                    Padding(
                      padding: const EdgeInsets.only(top: 20.0),
                      child: Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12.0),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.error_outline, color: Colors.red[400], size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Analysis Error',
                                    style: TextStyle(
                                      color: Colors.red[300],
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    diagnosis.error!,
                                    style: TextStyle(
                                      color: Colors.red[200],
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () => _runInference(forceRerun: true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red[600],
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Text(
                                      'Retry Analysis',
                                      style: TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to identify queue-related errors
  bool _isQueueRelatedError(String error) {
    final errorLower = error.toLowerCase();
    return errorLower.contains('queue') ||
           errorLower.contains('busy') ||
           errorLower.contains('already running') ||
           errorLower.contains('waiting') ||
           errorLower.contains('request cancelled') ||
           errorLower.contains('agent is currently') ||
           errorLower.contains('inference');
  }

  Widget _buildProgressIndicator(UnifiedBackgroundService backgroundService, List<String> dtcs) {
    final isActiveForCurrentDtcs = backgroundService.isInferenceActiveForDtcs(dtcs);
    final hasDiagnosisInference = backgroundService.hasDiagnosisInference;
    final hasChatInference = backgroundService.hasChatInference;
    final queueLength = backgroundService.queueLength;
    
    String statusText;
    String? detailText;
    
    if (isActiveForCurrentDtcs && hasDiagnosisInference) {
      statusText = 'Generating diagnosis...';
      detailText = 'AI is analyzing your diagnostic codes and formulating recommendations.';
    } else if (isActiveForCurrentDtcs && !hasDiagnosisInference) {
      statusText = 'Queued for analysis...';
      if (hasChatInference) {
        detailText = 'Waiting for chat to complete, then diagnosis will begin.';
      } else {
        detailText = 'Your diagnosis will start momentarily.';
      }
    } else {
      statusText = 'Waiting in queue...';
      if (hasChatInference) {
        detailText = 'Chat assistant is active. Diagnosis will follow.';
      } else if (queueLength > 0) {
        detailText = queueLength == 1 
            ? '1 operation ahead in queue.'
            : '$queueLength operations ahead in queue.';
      }
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyan.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.cyan[400],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: Colors.cyan[300],
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          if (detailText != null) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Text(
                detailText,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(UnifiedBackgroundService backgroundService) {
    final hasDiagnosisInference = backgroundService.hasDiagnosisInference;
    final isAgentBusy = backgroundService.isAgentBusy;
    final queueLength = backgroundService.queueLength;
    final isActiveForCurrentDtcs = backgroundService.isInferenceActiveForDtcs(widget.dtcs);
    final hasChatInference = backgroundService.hasChatInference;
    
    if (!hasDiagnosisInference && !isAgentBusy && queueLength == 0) {
      return const SizedBox.shrink();
    }
    
    String statusText;
    Color? statusColor;
    
    if (hasDiagnosisInference && isActiveForCurrentDtcs) {
      statusText = 'Analyzing...';
      statusColor = Colors.cyan[400];
    } else if (isActiveForCurrentDtcs) {
      statusText = 'Queued...';
      statusColor = Colors.amber[400];
    } else if (isAgentBusy && hasChatInference) {
      statusText = 'Chat active...';
      statusColor = Colors.blue[400];
    } else if (isAgentBusy) {
      statusText = 'Agent busy...';
      statusColor = Colors.amber[600];
    } else {
      statusText = 'Queue ($queueLength)';
      statusColor = Colors.grey[400];
    }
    
    return Container(
      margin: const EdgeInsets.only(right: 8.0),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor?.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor?.withOpacity(0.3) ?? Colors.grey),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor ?? Colors.grey),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Vehicle Diagnosis',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        actions: [
          // Show processing/queue status
          Consumer<UnifiedBackgroundService>(
            builder: (context, backgroundService, child) {
              return _buildStatusIndicator(backgroundService);
            },
          ),
          
          // Re-run button - improved state checking
          Consumer<UnifiedBackgroundService>(
            builder: (context, backgroundService, child) {
              final isAnyInferenceActive = backgroundService.hasActiveInference || backgroundService.isAgentBusy;
              
              return Container(
                margin: const EdgeInsets.only(right: 8),
                child: IconButton(
                  icon: Icon(
                    Icons.refresh,
                    color: isAnyInferenceActive ? Colors.grey[600] : Colors.white,
                    size: 24,
                  ),
                  tooltip: isAnyInferenceActive 
                      ? 'Wait for operations to complete' 
                      : 'Re-run diagnosis',
                  onPressed: (widget.dtcs.isEmpty || isAnyInferenceActive) ? null : _clearAndRerun,
                  style: IconButton.styleFrom(
                    backgroundColor: isAnyInferenceActive 
                        ? Colors.transparent 
                        : Colors.grey[800],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Container(
        color: Colors.black,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Consumer<UnifiedBackgroundService>(
            builder: (context, backgroundService, child) {
              final isInferenceRunning = backgroundService.hasDiagnosisInference;
              if (_wasInferenceRunning && !isInferenceRunning) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _checkAndStartInferenceIfNeeded();
                });
              }
              _wasInferenceRunning = isInferenceRunning;
              
              final diagnosis = _currentDiagnosisId != null
                  ? backgroundService.getDiagnosisById(_currentDiagnosisId!) ??
                    backgroundService.getDiagnosisForDtcs(widget.dtcs)
                  : backgroundService.getDiagnosisForDtcs(widget.dtcs);
              
              return _buildDiagnosisContent(diagnosis, backgroundService);
            },
          ),
        ),
      ),
    );
  }
}