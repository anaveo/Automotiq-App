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

  // Helper method to clean LLM output
  String _cleanLlmOutput(String output) {
    String cleaned = output;
    
    // Remove various forms of end_of_turn tags (case insensitive)
    cleaned = cleaned.replaceAll(RegExp(r'</?end_of_turn>', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<end_of_turn/?>', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'</end_of_turn>', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<end_of_turn>', caseSensitive: false), '');
    
    // Remove other common LLM artifacts
    cleaned = cleaned.replaceAll(RegExp(r'<\|im_end\|>', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<\|im_start\|>', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<\|endoftext\|>', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<\|end\|>', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<\|start\|>', caseSensitive: false), '');
    
    // Remove any remaining angle bracket patterns that look like tags
    cleaned = cleaned.replaceAll(RegExp(r'<[^>]*end[^>]*>', caseSensitive: false), '');
    
    // Clean up multiple whitespaces and newlines
    cleaned = cleaned.replaceAll(RegExp(r'\n\s*\n\s*\n'), '\n\n'); // Replace multiple newlines with double newline
    cleaned = cleaned.replaceAll(RegExp(r'[ \t]+'), ' '); // Replace multiple spaces/tabs with single space
    
    // Trim whitespace
    cleaned = cleaned.trim();
    
    return cleaned;
  }

  Widget _buildDiagnosisContent(DiagnosisResult? diagnosis, UnifiedBackgroundService backgroundService) {
    if (diagnosis == null) {
      if (widget.dtcs.isEmpty) {
        return const Center(
          child: Text(
            'No diagnostic trouble codes provided.',
            style: TextStyle(fontSize: 16, color: Colors.grey),
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
              const CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.deepPurpleAccent,
              ),
              const SizedBox(height: 24),
              Text(
                statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (subMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  subMessage,
                  style: TextStyle(
                    fontSize: 14, 
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              // Show current DTCs being processed
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Diagnostic Trouble Codes:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: widget.dtcs.map((dtc) => Chip(
                          label: Text(dtc),
                          backgroundColor: Colors.orange.withOpacity(0.2),
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
              const CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.deepPurpleAccent,
              ),
              const SizedBox(height: 24),
              Text(
                statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (subMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  subMessage,
                  style: TextStyle(
                    fontSize: 14, 
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              // Show current DTCs being processed
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Diagnostic Trouble Codes:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: diagnosis.dtcs.map((dtc) => Chip(
                          label: Text(dtc),
                          backgroundColor: Colors.orange.withOpacity(0.2),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // DTCs Section
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Diagnostic Trouble Codes:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: diagnosis.dtcs.map((dtc) => Chip(
                    label: Text(dtc),
                    backgroundColor: Colors.orange.withOpacity(0.2),
                  )).toList(),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Prompt Section (collapsible)
        ExpansionTile(
          title: const Text(
            'AI Prompt',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                diagnosis.prompt,
                style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 8),
        
        // Output Section
        const Text(
          'Diagnosis:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 8),
        
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (diagnosis.output.isNotEmpty)
                      MarkdownBody(
                        data: _cleanLlmOutput(diagnosis.output),
                        styleSheet: MarkdownStyleSheet(
                          p: const TextStyle(fontSize: 16, height: 1.5),
                          h1: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          h2: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          h3: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          h4: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          h5: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          h6: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          strong: const TextStyle(fontWeight: FontWeight.bold),
                          em: const TextStyle(fontStyle: FontStyle.italic),
                          code: TextStyle(
                            backgroundColor: Colors.grey[200],
                            fontFamily: 'monospace',
                            fontSize: 14,
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          codeblockPadding: const EdgeInsets.all(12),
                          blockquote: TextStyle(
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                          blockquoteDecoration: BoxDecoration(
                            color: Colors.grey[50],
                            border: Border(
                              left: BorderSide(
                                color: Colors.grey[400]!,
                                width: 4,
                              ),
                            ),
                          ),
                          blockquotePadding: const EdgeInsets.all(12),
                          listBullet: const TextStyle(fontSize: 16),
                        ),
                      ),
                    
                    // Enhanced loading indicator with queue info
                    if (!diagnosis.isComplete && diagnosis.error == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: _buildProgressIndicator(backgroundService, widget.dtcs),
                      ),
                    
                    // Show error if exists (but only non-queue errors)
                    if (diagnosis.error != null && !_isQueueRelatedError(diagnosis.error!))
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Container(
                          padding: const EdgeInsets.all(12.0),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8.0),
                            border: Border.all(color: Colors.red.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Analysis Error',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      diagnosis.error!,
                                      style: const TextStyle(color: Colors.red),
                                    ),
                                    const SizedBox(height: 8),
                                    ElevatedButton(
                                      onPressed: () => _runInference(forceRerun: true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text('Retry Analysis'),
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
          ),
        ),
      ],
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
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                statusText,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        if (detailText != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Text(
              detailText,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
          ),
        ],
      ],
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
      statusColor = Colors.green;
    } else if (isActiveForCurrentDtcs) {
      statusText = 'Queued...';
      statusColor = Colors.orange;
    } else if (isAgentBusy && hasChatInference) {
      statusText = 'Chat active...';
      statusColor = Colors.blue;
    } else if (isAgentBusy) {
      statusText = 'Agent busy...';
      statusColor = Colors.amber;
    } else {
      statusText = 'Queue ($queueLength)';
      statusColor = Colors.grey;
    }
    
    return Container(
      margin: const EdgeInsets.only(right: 8.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor ?? Colors.grey),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            statusText,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Diagnosis'),
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
              
              return IconButton(
                icon: Icon(
                  Icons.refresh,
                  color: isAnyInferenceActive ? Colors.grey : null,
                ),
                tooltip: isAnyInferenceActive 
                    ? 'Wait for operations to complete' 
                    : 'Re-run diagnosis',
                onPressed: (widget.dtcs.isEmpty || isAnyInferenceActive) ? null : _clearAndRerun,
              );
            },
          ),
        ],
      ),
      body: Padding(
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
    );
  }
}