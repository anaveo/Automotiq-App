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
  
  // Getters
  List<ChatMessage> get messages => _isDisposed ? [] : List.unmodifiable(_messages);
  Map<String, DiagnosisResult> get diagnoses => _isDisposed ? {} : Map.unmodifiable(_diagnoses);
  bool get hasActiveInference => _isDisposed ? false : _activeInferences.isNotEmpty;
  int get activeInferenceCount => _isDisposed ? 0 : _activeInferences.length;
  bool get hasChatInference => _isDisposed ? false : _activeInferences.values.any((inf) => inf.type == InferenceType.chat);
  bool get hasDiagnosisInference => _isDisposed ? false : _activeInferences.values.any((inf) => inf.type == InferenceType.diagnosis);

  // Initialize the service
  Future<void> initialize() async {
    if (_isDisposed) return;
    
    await Future.wait([
      _loadMessages(),
      _loadDiagnoses(),
    ]);
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
    
    // Add user message
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

    try {
      final message = image != null
          ? Message.withImage(
              text: text.isEmpty ? 'Analyze this image' : text,
              imageBytes: image,
              isUser: true,
            )
          : Message.text(text: text, isUser: true);

      AppLogger.logInfo(
        'Sending chat message: type=${message.hasImage ? "image+text" : "text"}, text="$text"',
        'UnifiedBackgroundService.sendChatMessage',
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
          AppLogger.logInfo('Chat response completed: $fullResponse', 'UnifiedBackgroundService.sendChatMessage');
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
      AppLogger.logError(e, stackTrace, 'UnifiedBackgroundService.sendChatMessage');
      
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
      
      // Cancel chat-related streams
      final chatInferences = _activeInferences.entries
          .where((entry) => entry.value.type == InferenceType.chat)
          .toList();
      
      for (final entry in chatInferences) {
        entry.value.subscription.cancel();
        _activeInferences.remove(entry.key);
      }
      
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

    final completer = Completer<void>();
    final prompt = _createDiagnosisPrompt(dtcs);
    
    // Create initial diagnosis result
    final initialResult = DiagnosisResult(
      dtcs: dtcs,
      prompt: prompt,
      output: '',
      id: diagnosisId,
      isComplete: false,
    );
    
    _diagnoses[diagnosisKey] = initialResult;
    if (!_isDisposed) {
      notifyListeners();
      await _saveDiagnoses();
    }

    try {
      await chat.addQueryChunk(
          Message.text(text: 'Reset context for new diagnosis', isUser: false));
      await chat.addQueryChunk(Message.text(text: prompt, isUser: true));

      final responseStream = chat.generateChatResponseAsync();
      String responseText = '';

      AppLogger.logInfo('Starting diagnosis for DTCs: ${dtcs.join(', ')}', 'UnifiedBackgroundService.runDiagnosis');

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
          
          AppLogger.logInfo('Diagnosis completed for DTCs: ${dtcs.join(', ')}', 'UnifiedBackgroundService.runDiagnosis');
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

      return diagnosisId;
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'UnifiedBackgroundService.runDiagnosis');
      
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
    return _activeInferences.containsKey(key);
  }

  Future<void> clearDiagnosis(List<String> dtcs) async {
    if (_isDisposed) return;
    
    final key = _generateDiagnosisKey(dtcs);
    
    // Cancel active stream if exists
    _activeInferences[key]?.subscription.cancel();
    _activeInferences.remove(key);
    
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
    
    super.dispose();
    
    // Reset the singleton instance so it can be recreated
    _instance = null;
  }
}