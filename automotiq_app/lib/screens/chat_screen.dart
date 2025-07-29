import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:automotiq_app/providers/model_provider.dart';
import 'package:automotiq_app/utils/logger.dart';
import '../services/unified_background_service.dart';

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
    // Don't dispose the background service since it's a singleton
    // _backgroundService.dispose(); // Remove this line
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (_isDisposed) return;
    
    switch (state) {
      case AppLifecycleState.resumed:
        AppLogger.logInfo('App resumed, checking chat inference status', 'ChatScreen.didChangeAppLifecycleState');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isDisposed && mounted && _scrollController.hasClients) {
            _scrollToBottom();
          }
          // Check if we need to resume any pending inference
          _checkAndResumeChatIfNeeded();
        });
        break;
      case AppLifecycleState.paused:
        AppLogger.logInfo('App backgrounded, chat inference continues', 'ChatScreen.didChangeAppLifecycleState');
        break;
      default:
        break;
    }
  }

  Future<void> _checkAndResumeChatIfNeeded() async {
    if (_isDisposed || !mounted) return;
    
    final modelProvider = Provider.of<ModelProvider>(context, listen: false);
    if (!modelProvider.isChatInitialized || modelProvider.globalAgent == null) {
      return;
    }

    // Only check for resume if there's NO inference currently running
    if (_backgroundService.hasChatInference) {
      AppLogger.logInfo('Chat inference is running, no need to resume', 'ChatScreen._checkAndResumeChatIfNeeded');
      return;
    }

    // Check if there are messages that might need processing
    final messages = _backgroundService.messages;
    if (messages.isNotEmpty) {
      final lastMessage = messages.last;
      
      // If the last message is from user, check if there should be an assistant response
      if (lastMessage.sender == 'user') {
        // Check if there's a follow-up assistant message or if one is being generated
        bool hasAssistantResponse = false;
        
        // Look through messages to see if the last user message has a response
        for (int i = messages.length - 1; i >= 0; i--) {
          if (messages[i].sender == 'user' && messages[i] == lastMessage) {
            // Found the last user message, check if there's an assistant response after it
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
        
        // Only resume if there's no assistant response AND no inference running
        if (!hasAssistantResponse && !_backgroundService.hasChatInference) {
          AppLogger.logInfo('Found orphaned user message without response and no running inference, resuming', 'ChatScreen._checkAndResumeChatIfNeeded');
          
          // Add a small delay to ensure UI is stable before resuming
          await Future.delayed(const Duration(milliseconds: 500));
          
          // Double-check that inference still isn't running after delay
          if (!_backgroundService.hasChatInference && mounted && !_isDisposed) {
            try {
              await _backgroundService.sendChatMessage(
                text: lastMessage.text,
                image: lastMessage.image,
                chat: modelProvider.globalAgent!,
              );
            } catch (e, stackTrace) {
              AppLogger.logError(e, stackTrace, 'ChatScreen._checkAndResumeChatIfNeeded');
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
        if (!_isDisposed && mounted && _scrollController.hasClients && _backgroundService.messages.isNotEmpty) {
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

  Future<void> _pickImage() async {
    if (_isDisposed) return;
    
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        final imageBytes = await pickedFile.readAsBytes();
        AppLogger.logInfo('Image picked: ${imageBytes.length} bytes', 'ChatScreen._pickImage');
        if (_isDisposed || !mounted) return;
        setState(() {
          _selectedImage = imageBytes;
        });
      }
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'ChatScreen._pickImage');
      if (_isDisposed || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e')),
      );
    }
  }

  Future<void> _sendMessage(String text) async {
    if (_isDisposed || (text.trim().isEmpty && _selectedImage == null)) return;

    final modelProvider = Provider.of<ModelProvider>(context, listen: false);
    if (!modelProvider.isChatInitialized || modelProvider.globalAgent == null) {
      AppLogger.logError('Global chat not initialized', null, 'ChatScreen._sendMessage');
      if (_isDisposed || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat not initialized. Please try again.')),
      );
      return;
    }

    _controller.clear();
    final tempImage = _selectedImage;
    
    // Check disposed and mounted before setState
    if (_isDisposed || !mounted) return;
    setState(() {
      _selectedImage = null;
    });

    try {
      await _backgroundService.sendChatMessage(
        text: text,
        image: tempImage,
        chat: modelProvider.globalAgent!,
      );

      // Check disposed and mounted after async operation
      if (_isDisposed || !mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed && mounted) {
          _scrollToBottom();
        }
      });
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'ChatScreen._sendMessage');
      if (_isDisposed || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: $e')),
      );
    }
  }

  Future<void> _clearMessages() async {
    if (_isDisposed || !mounted) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Chat?'),
        content: const Text('Previous messages will no longer be visible and any ongoing inference will be stopped.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    
    if (confirmed == true && !_isDisposed && mounted) {
      await _backgroundService.clearChatMessages();
    }
  }

  InputDecoration _inputDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: Theme.of(context).textTheme.bodyMedium,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
    );
  }

  Widget _buildMessage(ChatMessage message) {
    final isUser = message.sender == 'user';
    final hasImage = message.image != null;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          child: Column(
            crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (hasImage)
                Container(
                  margin: const EdgeInsets.only(bottom: 8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12.0),
                    child: Image.memory(
                      message.image!,
                      width: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        AppLogger.logError(error, stackTrace, 'ChatScreen.Image.memory');
                        return const Text('Failed to load image');
                      },
                    ),
                  ),
                ),
              if (message.text.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: isUser ? Colors.deepPurpleAccent : Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Text(
                    message.text,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isUser ? Colors.white : Colors.white70,
                        ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Assistant'),
        actions: [
          // Show indicator if there's background inference
          Consumer<UnifiedBackgroundService>(
            builder: (context, backgroundService, child) {
              if (backgroundService.hasChatInference) {
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
                        'Processing...',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          // Wrap the IconButton in Consumer to check inference state
          Consumer<UnifiedBackgroundService>(
            builder: (context, backgroundService, child) {
              final isInferenceActive = backgroundService.hasChatInference;
              
              return IconButton(
                icon: Icon(
                  Icons.edit_square,
                  color: isInferenceActive ? Colors.grey : null,
                ),
                tooltip: isInferenceActive 
                    ? 'Wait for inference to complete' 
                    : 'Create new chat',
                onPressed: isInferenceActive ? null : _clearMessages,
              );
            },
          ),
        ],
      ),
      body: Consumer<ModelProvider>(
        builder: (context, modelProvider, child) {
          if (!modelProvider.isChatInitialized) {
            return const Center(child: CircularProgressIndicator());
          }
          
          return Column(
            children: [
              Expanded(
                child: Consumer<UnifiedBackgroundService>(
                  builder: (context, backgroundService, child) {
                    // Check if inference just completed and we need to scroll
                    final isInferenceRunning = backgroundService.hasChatInference;
                    if (_wasInferenceRunning && !isInferenceRunning) {
                      // Inference just completed, scroll to bottom
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!_isDisposed && mounted) {
                          _scrollToBottom();
                        }
                      });
                    }
                    _wasInferenceRunning = isInferenceRunning;
                    
                    final messages = backgroundService.messages;
                    
                    if (messages.isEmpty) {
                      return const Center(
                        child: Text(
                          'Start a conversation!',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      );
                    }
                    
                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        return _buildMessage(messages[index]);
                      },
                    );
                  },
                ),
              ),
              // Image preview
              if (_selectedImage != null)
                Container(
                  margin: const EdgeInsets.all(8.0),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8.0),
                        child: Image.memory(
                          _selectedImage!,
                          height: 100,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () {
                            if (!_isDisposed && mounted) {
                              setState(() => _selectedImage = null);
                            }
                          },
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // Input area
              Container(
                padding: const EdgeInsets.all(8.0),
                child: Consumer<UnifiedBackgroundService>(
                  builder: (context, backgroundService, child) {
                    final isLoading = backgroundService.hasChatInference;
                    
                    return Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.image, color: Colors.deepPurpleAccent),
                          onPressed: isLoading ? null : _pickImage,
                          tooltip: 'Pick image',
                        ),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            decoration: _inputDecoration('How can I help?'),
                            onSubmitted: isLoading ? null : _sendMessage,
                            enabled: !isLoading,
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        IconButton(
                          icon: isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.send, color: Colors.deepPurpleAccent),
                          onPressed: isLoading ? null : () => _sendMessage(_controller.text),
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
    );
  }
}