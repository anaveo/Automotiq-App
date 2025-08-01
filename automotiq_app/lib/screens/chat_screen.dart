import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:automotiq_app/providers/model_provider.dart';
import 'package:automotiq_app/utils/logger.dart';
import '../services/unified_background_service.dart';


import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';


class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late UnifiedBackgroundService _backgroundService;
  Uint8List? _selectedImage;
  bool _isDisposed = false;
  bool _wasInferenceRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _backgroundService = UnifiedBackgroundService();
    _initializeChat();
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed) return;
    switch (state) {
      case AppLifecycleState.resumed:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isDisposed && mounted && _scrollController.hasClients) {
            _scrollToBottom();
          }
          _checkAndResumeChatIfNeeded();
        });
        break;
      default:
        break;
    }
  }

  Future<void> _checkAndResumeChatIfNeeded() async {
    if (_isDisposed || !mounted) return;
    final modelProvider = Provider.of<ModelProvider>(context, listen: false);
    if (!modelProvider.isChatInitialized || modelProvider.globalAgent == null)
      return;
    if (_backgroundService.hasChatInference) return;

    final messages = _backgroundService.messages;
    if (messages.isNotEmpty) {
      final lastMessage = messages.last;
      if (lastMessage.sender == 'user') {
        bool hasAssistantResponse = false;
        for (int i = messages.length - 1; i >= 0; i--) {
          if (messages[i].sender == 'user' && messages[i] == lastMessage) {
            if (i < messages.length - 1) {
              for (int j = i + 1; j < messages.length; j++) {
                if (messages[j].sender == 'assistant') {
                  hasAssistantResponse = true;
                  break;
                }
              }
            }
            break;
          }
        }

        if (!hasAssistantResponse && !_backgroundService.hasChatInference) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (!_backgroundService.hasChatInference && mounted && !_isDisposed) {
            try {
              await _backgroundService.sendChatMessage(
                text: lastMessage.text,
                image: lastMessage.image,
                chat: modelProvider.globalAgent!,
              );
            } catch (e, stackTrace) {
              AppLogger.logError(
                e,
                stackTrace,
                'ChatScreen._checkAndResumeChatIfNeeded',
              );
            }
          }
        }
      }
    }
  }

  Future<void> _initializeChat() async {
    if (_isDisposed) return;
    await _backgroundService.initialize();
    if (!_isDisposed && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients &&
            _backgroundService.messages.isNotEmpty) {
          _scrollToBottom();
        }
      });
    }
  }

  void _scrollToBottom() {
    if (!_isDisposed && mounted && _scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<Uint8List?> pickImageUniversal({required ImageSource source}) async {
  try {
    // Handle permissions
    if (source == ImageSource.camera) {
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        throw Exception('Camera permission denied');
      }
    }

    Uint8List? imageBytes;

    if (source == ImageSource.camera) {
      // Use different camera strategies based on platform/device
      imageBytes = await _captureImageUniversal();
    } else {
      // Gallery selection - use standard image picker
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      
      if (pickedFile != null) {
        imageBytes = await pickedFile.readAsBytes();
      }
    }

    return imageBytes;
    
  } catch (e) {
    print('Universal image picker error: $e');
    return null;
  }
}

Future<Uint8List?> _captureImageUniversal() async {
  // Try multiple camera capture methods for maximum compatibility
  
  // Method 1: Try direct camera plugin (most reliable for Samsung)
  try {
    return await _captureWithCameraPlugin();
  } catch (e) {
    print('Camera plugin failed: $e');
  }
  
  // Method 2: Try image picker with reduced settings
  try {
    return await _captureWithImagePickerReduced();
  } catch (e) {
    print('Reduced image picker failed: $e');
  }
  
  // Method 3: Try standard image picker as last resort
  try {
    return await _captureWithImagePickerStandard();
  } catch (e) {
    print('Standard image picker failed: $e');
  }
  
  throw Exception('All camera capture methods failed');
}

Future<Uint8List?> _captureWithCameraPlugin() async {
  CameraController? controller;
  
  try {
    // Get available cameras
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw Exception('No cameras available');
    
    // Initialize camera controller
    controller = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false, // Disable audio for faster initialization
    );
    
    await controller.initialize();
    
    // Take picture
    final XFile photo = await controller.takePicture();
    final imageBytes = await photo.readAsBytes();
    
    // Clean up temporary file
    try {
      await File(photo.path).delete();
    } catch (e) {
      // Ignore cleanup errors
    }
    
    return imageBytes;
    
  } finally {
    // Always dispose controller
    try {
      await controller?.dispose();
    } catch (e) {
      // Ignore disposal errors
    }
  }
}

Future<Uint8List?> _captureWithImagePickerReduced() async {
  final picker = ImagePicker();
  
  // Use reduced settings for problematic devices
  final pickedFile = await picker.pickImage(
    source: ImageSource.camera,
    maxWidth: 600,
    maxHeight: 600,
    imageQuality: 50,
    preferredCameraDevice: CameraDevice.rear,
    requestFullMetadata: false,
  ).timeout(
    const Duration(seconds: 30),
    onTimeout: () => throw Exception('Camera timeout'),
  );
  
  if (pickedFile != null) {
    return await pickedFile.readAsBytes();
  }
  
  return null;
}

Future<Uint8List?> _captureWithImagePickerStandard() async {
  final picker = ImagePicker();
  
  final pickedFile = await picker.pickImage(
    source: ImageSource.camera,
    maxWidth: 1024,
    maxHeight: 1024,
    imageQuality: 85,
  );
  
  if (pickedFile != null) {
    return await pickedFile.readAsBytes();
  }
  
  return null;
}

Future<void> _pickImage() async {
  final source = ImageSource.camera;
  
  if (_isDisposed) return;
  
  try {
    Uint8List? imageBytes;
    
    // Handle permissions
    if (source == ImageSource.camera) {
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Camera permission denied')),
          );
        }
        return;
      }
      
      // Show camera preview screen
      imageBytes = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          builder: (context) => CameraPreviewScreen(),
          fullscreenDialog: true,
        ),
      );
    } else {
      // Gallery selection
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      
      if (pickedFile != null) {
        imageBytes = await pickedFile.readAsBytes();
      }
    }
    
    if (imageBytes != null && !_isDisposed && mounted) {
      setState(() => _selectedImage = imageBytes);
    }
    
  } catch (e, stackTrace) {
    AppLogger.logError(e, stackTrace, 'ChatScreen._pickImage');
    if (!_isDisposed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick image: ${e.toString()}'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}


  Future<void> _sendMessage(String text) async {
    if (_isDisposed || (text.trim().isEmpty && _selectedImage == null)) return;
    final modelProvider = Provider.of<ModelProvider>(context, listen: false);
    if (!modelProvider.isChatInitialized || modelProvider.globalAgent == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chat not initialized. Please try again.'),
        ),
      );
      return;
    }

    _controller.clear();
    final tempImage = _selectedImage;
    if (_isDisposed || !mounted) return;
    setState(() => _selectedImage = null);

    try {
      await _backgroundService.sendChatMessage(
        text: text,
        image: tempImage,
        chat: modelProvider.globalAgent!,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed && mounted) {
          _scrollToBottom();
        }
      });
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'ChatScreen._sendMessage');
      if (_isDisposed || !mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
    }
  }

  Future<void> _clearMessages() async {
    if (_isDisposed || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        titleTextStyle: Theme.of(context).textTheme.titleMedium,
        contentTextStyle: Theme.of(context).textTheme.bodySmall,
        title: const Text('Create New Chat?'),
        content: const Text(
          'Previous messages will no longer be visible and any ongoing inference will be stopped.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Create',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.deepPurpleAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && !_isDisposed && mounted) {
      await _backgroundService.clearChatMessages();
    }
  }

  // // Helper method to clean LLM output (same as DiagnosisScreen)
  String _cleanLlmOutput(String output) {
    String cleaned = output;

    // Remove all LLM-style tags including malformed or attribute-laden tags
    cleaned = cleaned.replaceAll(
      RegExp(r'<[^>\n]*>', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'</[^>\n]*', caseSensitive: false),
      '',
    ); // Catch tags like </endaboration role="assistant"

    // Remove standalone pipe-style delimiters (e.g., <|end|>)
    cleaned = cleaned.replaceAll(
      RegExp(r'<\|[^|>]+\|>', caseSensitive: false),
      '',
    );

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

  //   // Trim whitespace
  //   cleaned = cleaned.trim();

  //   return cleaned;
  // }

  InputDecoration _inputDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: Colors.grey[500]),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: Colors.grey[700]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: Colors.grey[700]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: Colors.deepPurpleAccent[400]!, width: 2),
      ),
      filled: true,
      fillColor: Colors.grey[900],
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 12.0,
      ),
    );
  }

  Widget _buildMessage(ChatMessage message) {
    final isUser = message.sender == 'user';
    final hasImage = message.image != null;

    // Use the comprehensive cleaning function instead of basic regex
    final cleanText = _cleanLlmOutput(message.text);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          child: Column(
            crossAxisAlignment: isUser
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (hasImage)
                Container(
                  margin: const EdgeInsets.only(bottom: 8.0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.0),
                    border: Border.all(color: Colors.grey[700]!, width: 1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12.0),
                    child: Image.memory(
                      message.image!,
                      width: 200,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              if (cleanText.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: isUser
                        ? const Color.fromARGB(157, 88, 10, 255)
                        : Colors.grey[900],
                    borderRadius: BorderRadius.circular(16.0),
                    border: Border.all(
                      color: isUser
                          ? const Color.fromARGB(
                              255,
                              98,
                              42,
                              253,
                            ).withOpacity(0.3)
                          : Colors.grey[700]!,
                      width: 1,
                    ),
                  ),
                  child: isUser
                      ? Text(
                          cleanText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.4,
                          ),
                        )
                      : MarkdownBody(
                          data: cleanText,
                          // TODO: Refine styles to match design language
                          styleSheet: MarkdownStyleSheet(
                            p: const TextStyle(
                              fontSize: 16,
                              height: 1.6,
                              color: Colors.white,
                            ),
                            h1: Theme.of(context).textTheme.titleLarge,
                            h2: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurpleAccent[400],
                            ),
                            h3: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurpleAccent[400],
                            ),
                            h4: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            h5: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            h6: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            strong: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            em: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey[300],
                            ),
                            code: TextStyle(
                              backgroundColor: Colors.grey[800],
                              color: Colors.deepPurpleAccent[300],
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
                                  color: Colors.deepPurpleAccent.withOpacity(
                                    0.6,
                                  ),
                                  width: 4,
                                ),
                              ),
                            ),
                            blockquotePadding: const EdgeInsets.all(16),
                            listBullet: TextStyle(
                              fontSize: 16,
                              color: Colors.deepPurpleAccent[400],
                            ),
                          ),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(UnifiedBackgroundService backgroundService) {
    final hasChatInference = backgroundService.hasChatInference;
    final isAgentBusy = backgroundService.isAgentBusy;
    final queueLength = backgroundService.queueLength;

    if (!hasChatInference && !isAgentBusy && queueLength == 0)
      return const SizedBox.shrink();

    String statusText;
    Color? statusColor;

    if (hasChatInference) {
      statusText = 'Processing...';
      statusColor = Colors.deepPurpleAccent[400];
    } else if (isAgentBusy) {
      statusText = 'In queue...';
      statusColor = Colors.amber[400];
    } else {
      statusText = 'Queued ($queueLength)';
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
              valueColor: AlwaysStoppedAnimation<Color>(
                statusColor ?? Colors.grey,
              ),
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
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.grey[900],
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Vehicle Assistant',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
          ),
          actions: [
            Consumer<UnifiedBackgroundService>(
              builder: (context, backgroundService, child) {
                return _buildStatusIndicator(backgroundService);
              },
            ),
            Consumer<UnifiedBackgroundService>(
              builder: (context, backgroundService, child) {
                final isAnyInferenceActive =
                    backgroundService.hasActiveInference ||
                    backgroundService.isAgentBusy;
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    icon: Icon(
                      Icons.edit_square,
                      color: isAnyInferenceActive
                          ? Colors.grey[600]
                          : Colors.white,
                      size: 24,
                    ),
                    tooltip: isAnyInferenceActive
                        ? 'Wait for operations to complete'
                        : 'Create new chat',
                    onPressed: isAnyInferenceActive ? null : _clearMessages,
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
          child: Consumer<ModelProvider>(
            builder: (context, modelProvider, child) {
              if (!modelProvider.isChatInitialized) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.grey[900],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.deepPurpleAccent.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: const CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.deepPurpleAccent,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Initializing AI Assistant...',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  Expanded(
                    child: Consumer<UnifiedBackgroundService>(
                      builder: (context, backgroundService, child) {
                        final isInferenceRunning =
                            backgroundService.hasChatInference;
                        if (_wasInferenceRunning && !isInferenceRunning) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!_isDisposed && mounted) {
                              _scrollToBottom();
                            }
                          });
                        }
                        _wasInferenceRunning = isInferenceRunning;

                        final messages = backgroundService.messages;
                        if (messages.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: EdgeInsetsGeometry.all(32),
                              child: Container(
                                padding: const EdgeInsets.all(32.0),
                                decoration: BoxDecoration(
                                  color: Colors.grey[900],
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.grey[700]!,
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.chat_outlined, size: 32),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Start a conversation!',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Ask me anything about your vehicle or automotive issues.',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        return ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                            vertical: 8.0,
                            horizontal: 16.0,
                          ),
                          itemCount: messages.length,
                          itemBuilder: (context, index) =>
                              _buildMessage(messages[index]),
                        );
                      },
                    ),
                  ),
                  if (_selectedImage != null)
                    Container(
                      margin: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12.0),
                        border: Border.all(color: Colors.grey[700]!, width: 1),
                      ),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12.0),
                            child: Image.memory(
                              _selectedImage!,
                              height: 100,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedImage = null),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.grey[600]!,
                                    width: 1,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      border: Border(
                        top: BorderSide(color: Colors.grey[700]!, width: 1),
                      ),
                    ),
                    child: Consumer<UnifiedBackgroundService>(
                      builder: (context, backgroundService, child) {
                        final isLoading =
                            backgroundService.hasChatInference ||
                            backgroundService.isAgentBusy;
                        return Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.image,
                                color: isLoading
                                    ? Colors.grey[600]
                                    : Colors.deepPurpleAccent,
                                size: 24,
                              ),
                              onPressed: isLoading ? null : _pickImage,
                              tooltip: 'Pick image',
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                style: const TextStyle(color: Colors.white),
                                decoration: _inputDecoration('How can I help?'),
                                onSubmitted: isLoading ? null : _sendMessage,
                                enabled: !isLoading,
                                maxLines: null,
                              ),
                            ),
                            const SizedBox(width: 12.0),
                            IconButton(
                              icon: isLoading
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.grey[400],
                                      ),
                                    )
                                  : const Icon(
                                      Icons.send,
                                      color: Colors.deepPurpleAccent,
                                      size: 24,
                                    ),
                              onPressed: isLoading
                                  ? null
                                  : () => _sendMessage(_controller.text),
                              tooltip: 'Send message',
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}


class CameraPreviewScreen extends StatefulWidget {
  const CameraPreviewScreen({Key? key}) : super(key: key);

  @override
  State<CameraPreviewScreen> createState() => _CameraPreviewScreenState();
}

class _CameraPreviewScreenState extends State<CameraPreviewScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) Navigator.of(context).pop();
        return;
      }

      _controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _controller!.initialize();
      
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      print('Camera initialization error: $e');
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) {
      return;
    }

    setState(() => _isCapturing = true);

    try {
      final XFile photo = await _controller!.takePicture();
      final imageBytes = await photo.readAsBytes();
      
      // Clean up temporary file
      try {
        await File(photo.path).delete();
      } catch (e) {
        // Ignore cleanup errors
      }
      
      if (mounted) {
        Navigator.of(context).pop(imageBytes);
      }
      
    } catch (e) {
      print('Take picture error: $e');
      setState(() => _isCapturing = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to take picture: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('Initializing camera...', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview
          Positioned.fill(
            child: CameraPreview(_controller!),
          ),
          
          // Top bar with close button
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close, color: Colors.white, size: 24),
              ),
            ),
          ),
          
          // Bottom controls
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 32,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Gallery button
                GestureDetector(
                  onTap: () async {
                    try {
                      final picker = ImagePicker();
                      final pickedFile = await picker.pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 1024,
                        maxHeight: 1024,
                        imageQuality: 85,
                      );
                      
                      if (pickedFile != null && mounted) {
                        final imageBytes = await pickedFile.readAsBytes();
                        Navigator.of(context).pop(imageBytes);
                      }
                    } catch (e) {
                      print('Gallery picker error: $e');
                    }
                  },
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.photo_library, color: Colors.white),
                  ),
                ),
                
                // Capture button
                GestureDetector(
                  onTap: _isCapturing ? null : _takePicture,
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: _isCapturing ? Colors.grey : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 3),
                    ),
                    child: _isCapturing
                        ? Center(child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.camera, color: Colors.black, size: 30),
                  ),
                ),
                
                // Placeholder for spacing
                SizedBox(width: 50),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}