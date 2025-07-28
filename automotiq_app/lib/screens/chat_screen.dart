import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:automotiq_app/providers/model_provider.dart';
import 'package:automotiq_app/utils/logger.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  InferenceChat? _chat;
  final List<Map<String, String>> _messages = [];
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    try {
      final gemmaProvider = Provider.of<ModelProvider>(context, listen: false);
      _chat = await gemmaProvider.createChat(
        supportImage: false,
        supportsFunctionCalls: true,
      );
      setState(() {});
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'ChatScreen._initializeChat');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to initialize chat: $e')),
      );
    }
  }

  Future<void> _sendMessage(String text) async {
    if (_chat == null || text.trim().isEmpty) return;

    setState(() {
      _messages.add({'text': text, 'sender': 'user'});
      _isLoading = true;
    });
    _controller.clear();

    try {
      await _chat!.addQueryChunk(Message.text(text: text, isUser: true));
      final responseStream = _chat!.generateChatResponseAsync();
      String fullResponse = '';

      await for (final response in responseStream) {
        if (response is TextResponse) {
          setState(() {
            fullResponse += response.token;
            if (_messages.isNotEmpty && _messages.last['sender'] == 'bot') {
              _messages.last['text'] = fullResponse;
            } else {
              _messages.add({'text': fullResponse, 'sender': 'bot'});
            }
          });
        } else if (response is FunctionCallResponse) {
          // await Provider.of<ModelProvider>(context, listen: false).handleFunctionCall(context, response);
          final finalResponse = await _chat!.generateChatResponse();
          setState(() {
            _messages.add({'text': finalResponse.toString(), 'sender': 'bot'});
          });
        }
      }
    } catch (e, stackTrace) {
      AppLogger.logError(e, stackTrace, 'ChatScreen._sendMessage');
      setState(() {
        _messages.add({'text': 'Error: $e', 'sender': 'bot'});
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    // Chat instance is automatically closed by inferenceModel.close() in GemmaProvider
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OBD2 Assistant')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return ListTile(
                  title: Text(
                    message['text']!,
                    style: TextStyle(
                      color: message['sender'] == 'user' ? Colors.blue : Colors.black,
                    ),
                  ),
                  trailing: message['sender'] == 'user' ? const Icon(Icons.person) : const Icon(Icons.smart_toy),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Ask about OBD2 diagnostics...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: _isLoading ? null : _sendMessage,
                  ),
                ),
                IconButton(
                  icon: _isLoading ? const CircularProgressIndicator() : const Icon(Icons.send),
                  onPressed: _isLoading ? null : () => _sendMessage(_controller.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}