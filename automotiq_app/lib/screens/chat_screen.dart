import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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
    if (!modelProvider.isChatInitialized || modelProvider.globalAgent == null) return;
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
        if (_scrollController.hasClients && _backgroundService.messages.isNotEmpty) {
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
        if (!_isDisposed && mounted) {
          setState(() => _selectedImage = imageBytes);
        }
      }
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'ChatScreen._pickImage');
      if (!_isDisposed || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
    }
  }

  Future<void> _sendMessage(String text) async {
    if (_isDisposed || (text.trim().isEmpty && _selectedImage == null)) return;
    final modelProvider = Provider.of<ModelProvider>(context, listen: false);
    if (!modelProvider.isChatInitialized || modelProvider.globalAgent == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat not initialized. Please try again.')));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
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
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
    );
  }

  Widget _buildMessage(ChatMessage message) {
    final isUser = message.sender == 'user';
    final hasImage = message.image != null;

    // Strip LLM tokens (like </end_of_turn>) and trim whitespace
    final cleanText = message.text.replaceAll(RegExp(r'<[^>]*>'), '').trim();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
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
                    ),
                  ),
                ),
              if (cleanText.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: isUser ? Colors.deepPurpleAccent : Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: isUser
                      ? Text(
                          cleanText,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
                        )
                      : MarkdownBody(
                          data: cleanText,
                          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                            p: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
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

    if (!hasChatInference && !isAgentBusy && queueLength == 0) return const SizedBox.shrink();

    String statusText = hasChatInference
        ? 'Processing...'
        : isAgentBusy
            ? 'In queue...'
            : 'Queued ($queueLength)';

    return Container(
      margin: const EdgeInsets.only(right: 8.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 4),
          Text(statusText, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Assistant'),
        actions: [
          Consumer<UnifiedBackgroundService>(
            builder: (context, backgroundService, child) {
              return _buildStatusIndicator(backgroundService);
            },
          ),
          Consumer<UnifiedBackgroundService>(
            builder: (context, backgroundService, child) {
              final isAnyInferenceActive = backgroundService.hasActiveInference || backgroundService.isAgentBusy;
              return IconButton(
                icon: Icon(Icons.edit_square, color: isAnyInferenceActive ? Colors.grey : null),
                tooltip: isAnyInferenceActive ? 'Wait for operations to complete' : 'Create new chat',
                onPressed: isAnyInferenceActive ? null : _clearMessages,
              );
            },
          ),
        ],
      ),
      body: Consumer<ModelProvider>(
        builder: (context, modelProvider, child) {
          if (!modelProvider.isChatInitialized) return const Center(child: CircularProgressIndicator());

          return Column(
            children: [
              Expanded(
                child: Consumer<UnifiedBackgroundService>(
                  builder: (context, backgroundService, child) {
                    final isInferenceRunning = backgroundService.hasChatInference;
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
                      return const Center(
                        child: Text('Start a conversation!', style: TextStyle(fontSize: 16, color: Colors.grey)),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                      itemCount: messages.length,
                      itemBuilder: (context, index) => _buildMessage(messages[index]),
                    );
                  },
                ),
              ),
              if (_selectedImage != null)
                Container(
                  margin: const EdgeInsets.all(8.0),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8.0),
                        child: Image.memory(_selectedImage!, height: 100, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedImage = null),
                          child: Container(
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(8.0),
                child: Consumer<UnifiedBackgroundService>(
                  builder: (context, backgroundService, child) {
                    final isLoading = backgroundService.hasChatInference || backgroundService.isAgentBusy;
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
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
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
