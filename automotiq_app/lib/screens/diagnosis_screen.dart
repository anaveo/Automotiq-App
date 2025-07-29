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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _backgroundService = UnifiedBackgroundService();
    _initializeDiagnosis();
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
        break;
      case AppLifecycleState.paused:
        AppLogger.logInfo('App backgrounded, diagnosis inference continues', 'DiagnosisScreen.didChangeAppLifecycleState');
        break;
      default:
        break;
    }
  }

  Future<void> _initializeDiagnosis() async {
    await _backgroundService.initialize();
    
    if (widget.dtcs.isNotEmpty) {
      // Check if we already have a diagnosis for these DTCs
      final existingDiagnosis = _backgroundService.getDiagnosisForDtcs(widget.dtcs);
      
      if (existingDiagnosis != null) {
        _currentDiagnosisId = existingDiagnosis.id;
        
        // If diagnosis is not complete and not currently running, start it
        if (!existingDiagnosis.isComplete && !_backgroundService.isInferenceActiveForDtcs(widget.dtcs)) {
          _runInference();
        }
      } else {
        // No existing diagnosis, start new one
        _runInference();
      }
    }
  }

  Future<void> _runInference({bool forceRerun = false}) async {
    if (widget.dtcs.isEmpty) return;

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
          
          // Re-run button
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-run diagnosis',
            onPressed: widget.dtcs.isEmpty ? null : _clearAndRerun,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Consumer<UnifiedBackgroundService>(
          builder: (context, backgroundService, child) {
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