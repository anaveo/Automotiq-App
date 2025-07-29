import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:automotiq_app/providers/model_provider.dart';
import 'package:automotiq_app/utils/logger.dart';
import '../services/unified_background_service.dart'; // Import the unified service

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
    
    // Check if DTCs have changed
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
        // Check if DTCs have changed while app was in background
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
    
    // Check if we have a diagnosis for current DTCs
    final existingDiagnosis = _backgroundService.getDiagnosisForDtcs(widget.dtcs);
    
    if (existingDiagnosis == null) {
      // No diagnosis exists for current DTCs, start one
      AppLogger.logInfo('No diagnosis found for current DTCs after inference completion, starting new inference', 'DiagnosisScreen._checkAndStartInferenceIfNeeded');
      _runInference();
    } else if (!existingDiagnosis.isComplete && !_backgroundService.isInferenceActiveForDtcs(widget.dtcs)) {
      // Diagnosis exists but is incomplete and not running, restart it
      AppLogger.logInfo('Incomplete diagnosis found for current DTCs, restarting inference', 'DiagnosisScreen._checkAndStartInferenceIfNeeded');
      _runInference();
    }
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
    
    // Update the processed DTCs and clear current diagnosis ID
    _lastProcessedDtcs = List.from(widget.dtcs);
    _currentDiagnosisId = null;
    
    // Force a check for new inference after a brief delay to let any UI updates settle
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
      // Update last processed DTCs
      _lastProcessedDtcs = List.from(widget.dtcs);
      
      // Check if we already have a diagnosis for these exact DTCs
      final existingDiagnosis = _backgroundService.getDiagnosisForDtcs(widget.dtcs);
      
      if (existingDiagnosis != null) {
        if (mounted) {
          setState(() {
            _currentDiagnosisId = existingDiagnosis.id;
          });
        }
        
        // If diagnosis is not complete and not currently running for these DTCs, start it
        if (!existingDiagnosis.isComplete && !_backgroundService.isInferenceActiveForDtcs(widget.dtcs)) {
          _runInference();
        }
      } else {
        // No existing diagnosis for these DTCs, start new one
        _runInference();
      }
    } else {
      // No DTCs, clear current diagnosis ID
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

    // Only check for conflicts if not forcing a rerun
    if (!forceRerun && _backgroundService.hasDiagnosisInference) {
      AppLogger.logInfo('Diagnosis inference already running, skipping new request', 'DiagnosisScreen._runInference');
      return;
    }

    final modelProvider = Provider.of<ModelProvider>(context, listen: false);
    if (!modelProvider.isChatInitialized || modelProvider.globalAgent == null) {
      AppLogger.logError('Global chat not initialized', null, 'DiagnosisScreen._runInference');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat not initialized. Please try again.')),
      );
      return;
    }

    try {
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
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'DiagnosisScreen._runInference');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to run diagnosis: $e')),
      );
    }
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

  Widget _buildDiagnosisContent(DiagnosisResult? diagnosis) {
    if (diagnosis == null) {
      if (widget.dtcs.isEmpty) {
        return const Center(
          child: Text(
            'No diagnostic trouble codes provided.',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        );
      }
      
      // Check if we're waiting for a diagnosis that doesn't exist yet
      // or if there's an active inference for different DTCs
      if (_backgroundService.hasDiagnosisInference) {
        final activeForCurrentDtcs = _backgroundService.isInferenceActiveForDtcs(widget.dtcs);
        if (activeForCurrentDtcs) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Initializing diagnosis...'),
              ],
            ),
          );
        } else {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.hourglass_empty, size: 48, color: Colors.grey),
                SizedBox(height: 16),
                Text('Waiting for current diagnosis to complete...'),
                SizedBox(height: 8),
                Text(
                  'Your diagnosis will start once the current one finishes.',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
      }
      
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Initializing diagnosis...'),
          ],
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
                      Text(
                        diagnosis.output,
                        style: const TextStyle(fontSize: 16),
                      ),
                    
                    // Show loading indicator if inference is still running
                    if (!diagnosis.isComplete && diagnosis.error == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Generating diagnosis...',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    // Show error if exists
                    if (diagnosis.error != null)
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
                                child: Text(
                                  diagnosis.error!,
                                  style: const TextStyle(color: Colors.red),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Diagnosis'),
        actions: [
          // Show indicator if there's background inference
          Consumer<UnifiedBackgroundService>(
            builder: (context, backgroundService, child) {
              if (backgroundService.hasDiagnosisInference) {
                return Container(
                  margin: const EdgeInsets.only(right: 8.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Analyzing...',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          
          // Re-run button - disable during active inference
          Consumer<UnifiedBackgroundService>(
            builder: (context, backgroundService, child) {
              final isInferenceActive = backgroundService.hasDiagnosisInference;
              
              return IconButton(
                icon: Icon(
                  Icons.refresh,
                  color: isInferenceActive ? Colors.grey : null,
                ),
                tooltip: isInferenceActive 
                    ? 'Wait for diagnosis to complete' 
                    : 'Re-run diagnosis',
                onPressed: (widget.dtcs.isEmpty || isInferenceActive) ? null : _clearAndRerun,
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Consumer<UnifiedBackgroundService>(
          builder: (context, backgroundService, child) {
            // Check if inference just completed and we need to start new one
            final isInferenceRunning = backgroundService.hasDiagnosisInference;
            if (_wasInferenceRunning && !isInferenceRunning) {
              // Inference just completed, check if we need to start new one
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _checkAndStartInferenceIfNeeded();
              });
            }
            _wasInferenceRunning = isInferenceRunning;
            
            final diagnosis = _currentDiagnosisId != null
                ? backgroundService.getDiagnosisById(_currentDiagnosisId!) ??
                  backgroundService.getDiagnosisForDtcs(widget.dtcs)
                : backgroundService.getDiagnosisForDtcs(widget.dtcs);
            
            return _buildDiagnosisContent(diagnosis);
          },
        ),
      ),
    );
  }
}