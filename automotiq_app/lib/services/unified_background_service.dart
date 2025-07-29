import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:automotiq_app/utils/logger.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

enum InferenceType { chat, diagnosis }

class ChatMessage {
  final String text;
  final String sender;
  final Uint8List? image;
  final DateTime timestamp;
  final String id;

  ChatMessage({
    required this.text,
    required this.sender,
    this.image,
    DateTime? timestamp,
    String? id,
  }) : timestamp = timestamp ?? DateTime.now(),
       id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'sender': sender,
      'image': image != null ? base64Encode(image!) : null,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'id': id,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      text: json['text'] as String? ?? '',
      sender: json['sender'] as String? ?? 'unknown',
      image: json['image'] != null ? base64Decode(json['image']) : null,
      timestamp: json['timestamp'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : DateTime.now(),
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }
}

class DiagnosisResult {
  final List<String> dtcs;
  final String prompt;
  final String output;
  final DateTime timestamp;
  final String id;
  final bool isComplete;
  final String? error;

  DiagnosisResult({
    required this.dtcs,
    required this.prompt,
    required this.output,
    DateTime? timestamp,
    String? id,
    this.isComplete = false,
    this.error,
  }) : timestamp = timestamp ?? DateTime.now(),
       id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  Map<String, dynamic> toJson() {
    return {
      'dtcs': dtcs,
      'prompt': prompt,
      'output': output,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'id': id,
      'isComplete': isComplete,
      'error': error,
    };
  }

  factory DiagnosisResult.fromJson(Map<String, dynamic> json) {
    return DiagnosisResult(
      dtcs: List<String>.from(json['dtcs'] as List? ?? []),
      prompt: json['prompt'] as String? ?? '',
      output: json['output'] as String? ?? '',
      timestamp: json['timestamp'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : DateTime.now(),
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      isComplete: json['isComplete'] as bool? ?? false,
      error: json['error'] as String?,
    );
  }

  DiagnosisResult copyWith({
    List<String>? dtcs,
    String? prompt,
    String? output,
    DateTime? timestamp,
    String? id,
    bool? isComplete,
    String? error,
  }) {
    return DiagnosisResult(
      dtcs: dtcs ?? this.dtcs,
      prompt: prompt ?? this.prompt,
      output: output ?? this.output,
      timestamp: timestamp ?? this.timestamp,
      id: id ?? this.id,
      isComplete: isComplete ?? this.isComplete,
      error: error ?? this.error,
    );
  }
}

class ActiveInference {
  final String id;
  final InferenceType type;
  final StreamSubscription subscription;
  final Completer<void>? completer;

  ActiveInference({
    required this.id,
    required this.type,
    required this.subscription,
    this.completer,
  });
}

// Queue request for managing agent access
class QueuedRequest {
  final String id;
  final InferenceType type;
  final Completer<String> completer;
  final Future<String> Function() operation;

  QueuedRequest({
    required this.id,
    required this.type,
    required this.completer,
    required this.operation,
  });
}

class UnifiedBackgroundService extends ChangeNotifier {
  static UnifiedBackgroundService? _instance;
  factory UnifiedBackgroundService() {
    _instance ??= UnifiedBackgroundService._internal();
    return _instance!;
  }
  UnifiedBackgroundService._internal();

  bool _isDisposed = false;

  // Chat-related data
  final List<ChatMessage> _messages = [];
  
  // Diagnosis-related data
  final Map<String, DiagnosisResult> _diagnoses = {};
  
  // Shared inference management
  final Map<String, ActiveInference> _activeInferences = {};
  
  // Agent access queue
  final List<QueuedRequest> _requestQueue = [];
  bool _isAgentBusy = false;
  
  // Getters
  List<ChatMessage> get messages => _isDisposed ? [] : List.unmodifiable(_messages);
  Map<String, DiagnosisResult> get diagnoses => _isDisposed ? {} : Map.unmodifiable(_diagnoses);
  bool get hasActiveInference => _isDisposed ? false : _activeInferences.isNotEmpty;
  int get activeInferenceCount => _isDisposed ? 0 : _activeInferences.length;
  bool get hasChatInference => _isDisposed ? false : _activeInferences.values.any((inf) => inf.type == InferenceType.chat);
  bool get hasDiagnosisInference => _isDisposed ? false : _activeInferences.values.any((inf) => inf.type == InferenceType.diagnosis);
  bool get isAgentBusy => _isAgentBusy;
  int get queueLength => _requestQueue.length;

  // Initialize the service
  Future<void> initialize() async {
    if (_isDisposed) return;
    
    await Future.wait([
      _loadMessages(),
      _loadDiagnoses(),
    ]);
  }

  // === AGENT QUEUE MANAGEMENT ===
  
  Future<String> _enqueueRequest(QueuedRequest request) async {
    if (_isDisposed) {
      request.completer.completeError('Service disposed');
      return '';
    }

    _requestQueue.add(request);
    AppLogger.logInfo(
      'Request ${request.id} (${request.type}) added to queue. Queue length: ${_requestQueue.length}',
      'UnifiedBackgroundService._enqueueRequest',
    );
    
    notifyListeners(); // Notify UI about queue change
    
    if (!_isAgentBusy) {
      _processQueue();
    }
    
    return request.completer.future;
  }

  Future<void> _processQueue() async {
    if (_isDisposed || _isAgentBusy || _requestQueue.isEmpty) return;
    
    _isAgentBusy = true;
    notifyListeners();
    
    while (_requestQueue.isNotEmpty && !_isDisposed) {
      final request = _requestQueue.removeAt(0);
      
      AppLogger.logInfo(
        'Processing request ${request.id} (${request.type}). Remaining in queue: ${_requestQueue.length}',
        'UnifiedBackgroundService._processQueue',
      );
      
      try {
        final result = await request.operation();
        if (!request.completer.isCompleted) {
          request.completer.complete(result);
        }
      } catch (e, stackTrace) {
        AppLogger.logError(e, stackTrace, 'UnifiedBackgroundService._processQueue.${request.type}');
        if (!request.completer.isCompleted) {
          request.completer.completeError(e);
        }
      }
      
      // Small delay between requests to prevent overwhelming the agent
      if (_requestQueue.isNotEmpty && !_isDisposed) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    
    _isAgentBusy = false;
    notifyListeners();
    
    AppLogger.logInfo('Queue processing completed', 'UnifiedBackgroundService._processQueue');
  }

  void _cancelQueuedRequest(String requestId) {
    _requestQueue.removeWhere((request) {
      if (request.id == requestId) {
        if (!request.completer.isCompleted) {
          request.completer.completeError('Request cancelled');
        }
        return true;
      }
      return false;
    });
    notifyListeners();
  }

  // === CHAT METHODS ===
  
  Future<void> _loadMessages() async {
    if (_isDisposed) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getStringList('chat_messages') ?? [];
      
      if (_isDisposed) return;
      
      _messages.clear();
      for (final msgJson in data) {
        try {
          final message = ChatMessage.fromJson(json.decode(msgJson));
          _messages.add(message);
        } catch (e) {
          // Skip corrupted messages and continue loading
          AppLogger.logError(e, null, 'UnifiedBackgroundService._loadMessages.parseMessage');
          continue;
        }
      }
      
      if (!_isDisposed) {
        notifyListeners();
      }
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'UnifiedBackgroundService._loadMessages');
    }
  }

  Future<void> _saveMessages() async {
    if (_isDisposed) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = _messages.map((msg) => json.encode(msg.toJson())).toList();
      await prefs.setStringList('chat_messages', encoded);
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'UnifiedBackgroundService._saveMessages');
    }
  }

  Future<String> sendChatMessage({
    required String text,
    Uint8List? image,
    required dynamic chat,
  }) async {
    if (_isDisposed || (text.trim().isEmpty && image == null)) return '';
    
    final messageId = DateTime.now().millisecondsSinceEpoch.toString();
    
    // Add user message immediately
    final userMessage = ChatMessage(
      text: text,
      sender: 'user',
      image: image,
      id: messageId,
    );
    
    _messages.add(userMessage);
    if (!_isDisposed) {
      notifyListeners();
      await _saveMessages();
    }

    // Add placeholder bot message
    final botMessage = ChatMessage(
      text: '',
      sender: 'bot',
      id: '${messageId}_bot',
    );
    _messages.add(botMessage);
    if (!_isDisposed) {
      notifyListeners();
    }

    // Create queued request
    final request = QueuedRequest(
      id: messageId,
      type: InferenceType.chat,
      completer: Completer<String>(),
      operation: () => _executeChatInference(messageId, text, image, chat),
    );

    return _enqueueRequest(request);
  }

  Future<String> _executeChatInference(
    String messageId,
    String text,
    Uint8List? image,
    dynamic chat,
  ) async {
    if (_isDisposed) return '';

    try {
      final message = image != null
          ? Message.withImage(
              text: text.isEmpty ? 'Analyze this image' : text,
              imageBytes: image,
              isUser: true,
            )
          : Message.text(text: text, isUser: true);

      AppLogger.logInfo(
        'Executing chat inference: type=${message.hasImage ? "image+text" : "text"}, text="$text"',
        'UnifiedBackgroundService._executeChatInference',
      );

      await chat.addQueryChunk(message);
      final responseStream = chat.generateChatResponseAsync();
      String fullResponse = '';

      final streamSubscription = responseStream.listen(
        (response) async {
          if (_isDisposed) return;
          
          if (response is TextResponse) {
            fullResponse += response.token;
            
            final botIndex = _messages.indexWhere((msg) => msg.id == '${messageId}_bot');
            if (botIndex != -1 && !_isDisposed) {
              _messages[botIndex] = ChatMessage(
                text: fullResponse,
                sender: 'bot',
                id: '${messageId}_bot',
                timestamp: _messages[botIndex].timestamp,
              );
              notifyListeners();
              await _saveMessages();
            }
          } else if (response is FunctionCallResponse) {
            try {
              final finalResponse = await chat.generateChatResponse();
              final botIndex = _messages.indexWhere((msg) => msg.id == '${messageId}_bot');
              if (botIndex != -1 && !_isDisposed) {
                _messages[botIndex] = ChatMessage(
                  text: finalResponse.toString(),
                  sender: 'bot',
                  id: '${messageId}_bot',
                  timestamp: _messages[botIndex].timestamp,
                );
                notifyListeners();
                await _saveMessages();
              }
            } catch (e, stackTrace) {
              AppLogger.logError(e, stackTrace, 'UnifiedBackgroundService.chat.FunctionCallResponse');
            }
          }
        },
        onError: (error, stackTrace) {
          if (_isDisposed) return;
          
          AppLogger.logError(error, stackTrace, 'UnifiedBackgroundService.chat.responseStream');
          
          final botIndex = _messages.indexWhere((msg) => msg.id == '${messageId}_bot');
          if (botIndex != -1) {
            _messages[botIndex] = ChatMessage(
              text: 'Error: $error',
              sender: 'bot',
              id: '${messageId}_bot',
              timestamp: _messages[botIndex].timestamp,
            );
            if (!_isDisposed) {
              notifyListeners();
              _saveMessages();
            }
          }
        },
        onDone: () {
          if (!_isDisposed) {
            _activeInferences.remove(messageId);
            notifyListeners();
          }
          AppLogger.logInfo('Chat response completed: $fullResponse', 'UnifiedBackgroundService._executeChatInference');
        },
      );

      if (!_isDisposed) {
        _activeInferences[messageId] = ActiveInference(
          id: messageId,
          type: InferenceType.chat,
          subscription: streamSubscription,
        );
        notifyListeners();
      }

      return messageId;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'UnifiedBackgroundService._executeChatInference');
      
      if (!_isDisposed) {
        final botIndex = _messages.indexWhere((msg) => msg.id == '${messageId}_bot');
        if (botIndex != -1) {
          _messages[botIndex] = ChatMessage(
            text: 'Error: $e',
            sender: 'bot',
            id: '${messageId}_bot',
            timestamp: _messages[botIndex].timestamp,
          );
          notifyListeners();
          await _saveMessages();
        }
      }
      
      rethrow;
    }
  }

  Future<void> clearChatMessages() async {
    if (_isDisposed) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('chat_messages');
      _messages.clear();
      
      // Cancel chat-related streams and remove from queue
      final chatInferences = _activeInferences.entries
          .where((entry) => entry.value.type == InferenceType.chat)
          .toList();
      
      for (final entry in chatInferences) {
        entry.value.subscription.cancel();
        _activeInferences.remove(entry.key);
      }
      
      // Cancel queued chat requests
      _requestQueue.removeWhere((request) {
        if (request.type == InferenceType.chat) {
          if (!request.completer.isCompleted) {
            request.completer.completeError('Chat cleared');
          }
          return true;
        }
        return false;
      });
      
      if (!_isDisposed) {
        notifyListeners();
      }
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'UnifiedBackgroundService.clearChatMessages');
    }
  }

  // === DIAGNOSIS METHODS ===
  
  Future<void> _loadDiagnoses() async {
    if (_isDisposed) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getStringList('diagnosis_results') ?? [];
      
      if (_isDisposed) return;
      
      _diagnoses.clear();
      for (final resultJson in data) {
        try {
          final result = DiagnosisResult.fromJson(json.decode(resultJson));
          _diagnoses[_generateDiagnosisKey(result.dtcs)] = result;
        } catch (e) {
          // Skip corrupted diagnoses and continue loading
          AppLogger.logError(e, null, 'UnifiedBackgroundService._loadDiagnoses.parseDiagnosis');
          continue;
        }
      }
      
      if (!_isDisposed) {
        notifyListeners();
      }
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'UnifiedBackgroundService._loadDiagnoses');
    }
  }

  Future<void> _saveDiagnoses() async {
    if (_isDisposed) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = _diagnoses.values
          .map((result) => json.encode(result.toJson()))
          .toList();
      await prefs.setStringList('diagnosis_results', encoded);
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'UnifiedBackgroundService._saveDiagnoses');
    }
  }

  String _generateDiagnosisKey(List<String> dtcs) {
    final sortedDtcs = List<String>.from(dtcs)..sort();
    return sortedDtcs.join('_').toLowerCase();
  }

  // Public method to generate diagnosis key for external use
  String generateDiagnosisKey(List<String> dtcs) {
    return _generateDiagnosisKey(dtcs);
  }

  String _createDiagnosisPrompt(List<String> dtcs) {
    return "You are an AI mechanic. Your role is to diagnose the health of a vehicle, given its diagnostic trouble codes and recommend further action. The vehicle has the following diagnostic trouble codes: ${dtcs.join(', ')}";
  }

  Future<String> runDiagnosis({
    required List<String> dtcs,
    required dynamic chat,
    bool forceRerun = false,
  }) async {
    if (_isDisposed || dtcs.isEmpty) return '';
    
    final diagnosisKey = _generateDiagnosisKey(dtcs);
    final diagnosisId = '${diagnosisKey}_${DateTime.now().millisecondsSinceEpoch}';
    
    // Check if we already have a recent diagnosis
    if (!forceRerun && _diagnoses.containsKey(diagnosisKey)) {
      final existingDiagnosis = _diagnoses[diagnosisKey]!;
      if (existingDiagnosis.isComplete && existingDiagnosis.error == null) {
        AppLogger.logInfo('Using existing diagnosis for DTCs: ${dtcs.join(', ')}', 'UnifiedBackgroundService.runDiagnosis');
        return existingDiagnosis.id;
      }
    }

    // Check if there's already an active inference for these DTCs
    if (_activeInferences.containsKey(diagnosisKey)) {
      AppLogger.logInfo('Diagnosis already running for DTCs: ${dtcs.join(', ')}', 'UnifiedBackgroundService.runDiagnosis');
      final activeInference = _activeInferences[diagnosisKey]!;
      await activeInference.completer?.future;
      return _diagnoses[diagnosisKey]?.id ?? diagnosisId;
    }

    // Check if this diagnosis is already queued
    final existingRequest = _requestQueue.firstWhere(
      (request) => request.id == diagnosisKey && request.type == InferenceType.diagnosis,
      orElse: () => QueuedRequest(id: '', type: InferenceType.chat, completer: Completer(), operation: () async => ''),
    );
    
    if (existingRequest.id.isNotEmpty) {
      AppLogger.logInfo('Diagnosis already queued for DTCs: ${dtcs.join(', ')}', 'UnifiedBackgroundService.runDiagnosis');
      return existingRequest.completer.future;
    }

    // Create initial diagnosis result
    final initialResult = DiagnosisResult(
      dtcs: dtcs,
      prompt: _createDiagnosisPrompt(dtcs),
      output: '',
      id: diagnosisId,
      isComplete: false,
    );
    
    _diagnoses[diagnosisKey] = initialResult;
    if (!_isDisposed) {
      notifyListeners();
      await _saveDiagnoses();
    }

    // Create queued request
    final request = QueuedRequest(
      id: diagnosisKey,
      type: InferenceType.diagnosis,
      completer: Completer<String>(),
      operation: () => _executeDiagnosisInference(diagnosisKey, dtcs, chat),
    );

    return _enqueueRequest(request);
  }

  Future<String> _executeDiagnosisInference(
    String diagnosisKey,
    List<String> dtcs,
    dynamic chat,
  ) async {
    if (_isDisposed) return '';

    final completer = Completer<void>();
    final prompt = _createDiagnosisPrompt(dtcs);

    try {
      await chat.addQueryChunk(
          Message.text(text: 'Reset context for new diagnosis', isUser: false));
      await chat.addQueryChunk(Message.text(text: prompt, isUser: true));

      final responseStream = chat.generateChatResponseAsync();
      String responseText = '';

      AppLogger.logInfo('Executing diagnosis inference for DTCs: ${dtcs.join(', ')}', 'UnifiedBackgroundService._executeDiagnosisInference');

      final streamSubscription = responseStream.listen(
        (response) async {
          if (_isDisposed) return;
          
          if (response is TextResponse) {
            responseText += response.token;
            
            _diagnoses[diagnosisKey] = _diagnoses[diagnosisKey]!.copyWith(
              output: responseText,
            );
            if (!_isDisposed) {
              notifyListeners();
              await _saveDiagnoses();
            }
          } else if (response is FunctionCallResponse) {
            try {
              final finalResponse = await chat.generateChatResponse();
              _diagnoses[diagnosisKey] = _diagnoses[diagnosisKey]!.copyWith(
                output: finalResponse.toString(),
                isComplete: true,
              );
              if (!_isDisposed) {
                notifyListeners();
                await _saveDiagnoses();
              }
            } catch (e, stackTrace) {
              AppLogger.logError(e, stackTrace, 'UnifiedBackgroundService.diagnosis.FunctionCallResponse');
              if (!_isDisposed) {
                _diagnoses[diagnosisKey] = _diagnoses[diagnosisKey]!.copyWith(
                  error: 'Error processing function call: $e',
                  isComplete: true,
                );
                notifyListeners();
                await _saveDiagnoses();
              }
            }
          }
        },
        onError: (error, stackTrace) {
          if (_isDisposed) return;
          
          AppLogger.logError(error, stackTrace, 'UnifiedBackgroundService.diagnosis.responseStream');
          
          _diagnoses[diagnosisKey] = _diagnoses[diagnosisKey]!.copyWith(
            error: 'Inference failed: $error',
            isComplete: true,
          );
          if (!_isDisposed) {
            notifyListeners();
            _saveDiagnoses();
          }
        },
        onDone: () {
          if (_isDisposed) return;
          
          if (_diagnoses.containsKey(diagnosisKey) && !_diagnoses[diagnosisKey]!.isComplete) {
            _diagnoses[diagnosisKey] = _diagnoses[diagnosisKey]!.copyWith(
              isComplete: true,
            );
            notifyListeners();
            _saveDiagnoses();
          }
          
          _activeInferences.remove(diagnosisKey);
          completer.complete();
          notifyListeners();
          
          AppLogger.logInfo('Diagnosis completed for DTCs: ${dtcs.join(', ')}', 'UnifiedBackgroundService._executeDiagnosisInference');
        },
      );

      if (!_isDisposed) {
        _activeInferences[diagnosisKey] = ActiveInference(
          id: diagnosisKey,
          type: InferenceType.diagnosis,
          subscription: streamSubscription,
          completer: completer,
        );
        notifyListeners();
      }

      await completer.future;
      return _diagnoses[diagnosisKey]?.id ?? '';
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'UnifiedBackgroundService._executeDiagnosisInference');
      
      if (!_isDisposed) {
        _diagnoses[diagnosisKey] = _diagnoses[diagnosisKey]!.copyWith(
          error: 'Inference failed: $e',
          isComplete: true,
        );
        notifyListeners();
        await _saveDiagnoses();
      }
      
      _activeInferences.remove(diagnosisKey);
      completer.complete();
      
      rethrow;
    }
  }

  DiagnosisResult? getDiagnosisForDtcs(List<String> dtcs) {
    if (_isDisposed) return null;
    final key = _generateDiagnosisKey(dtcs);
    return _diagnoses[key];
  }

  DiagnosisResult? getDiagnosisById(String id) {
    if (_isDisposed) return null;
    return _diagnoses.values.cast<DiagnosisResult?>().firstWhere(
      (diagnosis) => diagnosis?.id == id,
      orElse: () => null,
    );
  }

  bool isInferenceActiveForDtcs(List<String> dtcs) {
    if (_isDisposed) return false;
    final key = _generateDiagnosisKey(dtcs);
    return _activeInferences.containsKey(key) || 
           _requestQueue.any((request) => request.id == key && request.type == InferenceType.diagnosis);
  }

  Future<void> clearDiagnosis(List<String> dtcs) async {
    if (_isDisposed) return;
    
    final key = _generateDiagnosisKey(dtcs);
    
    // Cancel active stream if exists
    _activeInferences[key]?.subscription.cancel();
    _activeInferences.remove(key);
    
    // Cancel queued request if exists
    _cancelQueuedRequest(key);
    
    // Remove from storage
    _diagnoses.remove(key);
    await _saveDiagnoses();
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  Future<void> clearAllDiagnoses() async {
    if (_isDisposed) return;
    
    // Cancel diagnosis-related streams
    final diagnosisInferences = _activeInferences.entries
        .where((entry) => entry.value.type == InferenceType.diagnosis)
        .toList();
    
    for (final entry in diagnosisInferences) {
      entry.value.subscription.cancel();
      _activeInferences.remove(entry.key);
    }
    
    // Cancel queued diagnosis requests
    _requestQueue.removeWhere((request) {
      if (request.type == InferenceType.diagnosis) {
        if (!request.completer.isCompleted) {
          request.completer.completeError('Diagnoses cleared');
        }
        return true;
      }
      return false;
    });
    
    // Clear storage
    _diagnoses.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('diagnosis_results');
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  // === SHARED METHODS ===
  
  Future<void> clearAll() async {
    if (_isDisposed) return;
    
    await Future.wait([
      clearChatMessages(),
      clearAllDiagnoses(),
    ]);
  }

  @override
  void dispose() {
    _isDisposed = true;
    
    // Cancel all active streams
    for (final inference in _activeInferences.values) {
      inference.subscription.cancel();
    }
    _activeInferences.clear();
    
    // Cancel all queued requests
    for (final request in _requestQueue) {
      if (!request.completer.isCompleted) {
        request.completer.completeError('Service disposed');
      }
    }
    _requestQueue.clear();
    
    super.dispose();
    
    // Reset the singleton instance so it can be recreated
    _instance = null;
  }
}