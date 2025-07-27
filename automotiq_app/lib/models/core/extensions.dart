// import 'dart:convert';
import 'message.dart';

const userPrefix = "user";
const modelPrefix = "model";
const startTurn = "<start_of_turn>";
const endTurn = "<end_of_turn>";

extension MessageExtension on Message {
  String transformToChatPrompt() {
    // System messages should not be sent to the model
    if (type == MessageType.systemInfo) {
      return '';
    }
    return _transform();
  }

  String _transform() {
    if (isUser) {
      var content = text;
      if (type == MessageType.toolResponse) {
        content = '<tool_response>\n'
            'Tool Name: $toolName\n'
            'Tool Response:\n$text\n'
            '</tool_response>';
      }
      return '$startTurn$userPrefix\n$content$endTurn\n$startTurn$modelPrefix\n';
    }

    // Handle model responses - for GemmaIt format
    var content = text;
    if (type == MessageType.toolCall) {
      content = text;
    }
    return '$content$endTurn\n';
  }
}
