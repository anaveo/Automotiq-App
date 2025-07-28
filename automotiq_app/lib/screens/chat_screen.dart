import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:automotiq_app/providers/model_provider.dart';
import 'package:automotiq_app/utils/logger.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  Uint8List? _selectedImage;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList('chat_messages') ?? [];

    final loadedMessages = data.map((msgJson) {
      final dynamic decoded = json.decode(msgJson);
      final map = Map<String, dynamic>.from(decoded);
      if (map['image'] != null) {
        map['image'] = base64Decode(map['image']);
      }
      return map;
    });

    setState(() {
      _messages.addAll(loadedMessages);
    });
  }

  Future<void> _saveMessages() async {
    final prefs = await SharedPreferences.getInstance();

    final encoded = _messages.map((msg) {
      final newMsg = Map<String, dynamic>.from(msg);
      if (newMsg['image'] != null) {
        newMsg['image'] = base64Encode(newMsg['image']);
      }
      return json.encode(newMsg);
    }).toList();

    await prefs.setStringList('chat_messages', encoded);
  }

  Future<void> _clearMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('chat_messages');
    setState(() {
      _messages.clear();
    });
  }

  Future<void> _pickImage() async {
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
        setState(() {
          _selectedImage = imageBytes;
        });
      }
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'ChatScreen._pickImage');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e')),
      );
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty && _selectedImage == null) return;

    final modelProvider = Provider.of<ModelProvider>(context, listen: false);
    if (!modelProvider.isChatInitialized || modelProvider.globalAgent == null) {
      AppLogger.logError('Global chat not initialized', null, 'ChatScreen._sendMessage');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat not initialized. Please try again.')),
      );
      return;
    }

    final messageData = {
      'text': text,
      'sender': 'user',
      'image': _selectedImage,
    };
    setState(() {
      _messages.add(messageData);
      _isLoading = true;
    });
    await _saveMessages();

    _controller.clear();
    final tempImage = _selectedImage;
    _selectedImage = null;

    try {
      final chat = modelProvider.globalAgent!;
      final message = tempImage != null
          ? Message.withImage(
              text: text.isEmpty ? 'Analyze this image' : text,
              imageBytes: tempImage,
              isUser: true,
            )
          : Message.text(text: text, isUser: true);

      AppLogger.logInfo(
        'Sending message: type=${message.hasImage ? "image+text" : "text"}, text="$text", imageSize=${tempImage?.length ?? 0}',
        'ChatScreen._sendMessage',
      );

      final tokenCount = await chat.maxTokens;
      AppLogger.logInfo('Prompt token count: $tokenCount', 'ChatScreen._sendMessage');

      await chat.addQueryChunk(message);
      final responseStream = chat.generateChatResponseAsync();
      String fullResponse = '';

      await for (final response in responseStream) {
        if (response is TextResponse) {
          setState(() {
            fullResponse += response.token;
            if (_messages.isNotEmpty && _messages.last['sender'] == 'bot') {
              _messages.last['text'] = fullResponse;
            } else {
              _messages.add({
                'text': fullResponse,
                'sender': 'bot',
                'image': null,
              });
            }
          });
          await _saveMessages();
        } else if (response is FunctionCallResponse) {
          final finalResponse = await chat.generateChatResponse();
          setState(() {
            _messages.add({
              'text': finalResponse.toString(),
              'sender': 'bot',
              'image': null,
            });
          });
          await _saveMessages();
        }
      }

      AppLogger.logInfo('Response received: $fullResponse', 'ChatScreen._sendMessage');
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'ChatScreen._sendMessage');
      setState(() {
        _messages.add({
          'text': 'Error: $e',
          'sender': 'bot',
          'image': null,
        });
      });
      await _saveMessages();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Assistant'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Clear chat',
            onPressed: _isLoading
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Clear Chat History?'),
                        content: const Text('This will permanently delete all messages.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await _clearMessages();
                    }
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
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    final isUser = message['sender'] == 'user';
                    final hasImage = message['image'] != null;
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
                                      message['image'] as Uint8List,
                                      width: 200,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        AppLogger.logError(error, stackTrace, 'ChatScreen.Image.memory');
                                        return const Text('Failed to load image');
                                      },
                                    ),
                                  ),
                                ),
                              if (message['text'] != null && message['text'].isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.all(12.0),
                                  decoration: BoxDecoration(
                                    color: isUser ? Colors.deepPurpleAccent : Colors.grey.shade900,
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  child: Text(
                                    message['text']!,
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
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.image, color: Colors.deepPurpleAccent),
                      onPressed: _isLoading ? null : _pickImage,
                      tooltip: 'Pick image',
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: _inputDecoration('How can I help?'),
                        onSubmitted: _isLoading ? null : _sendMessage,
                        enabled: !_isLoading,
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    IconButton(
                      icon: _isLoading
                          ? const CircularProgressIndicator()
                          : const Icon(Icons.send, color: Colors.deepPurpleAccent),
                      onPressed: _isLoading ? null : () => _sendMessage(_controller.text),
                      tooltip: 'Send message',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
