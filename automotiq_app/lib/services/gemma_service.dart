// import 'package:flutter/foundation.dart';
// import '../models/core/chat.dart';
// // import 'package:flutter_gemma/flutter_gemma.dart';
// // import '../models/flutter_gemma_interface.dart';
// // import '../models/model_file_manager_interface.dart';
// import '../models/core/message.dart';
// import '../models/core/model_response.dart';
// // import '../models/core/function_call_parser.dart';
// // import '../models/core/tool.dart';
// // import '../models/core/chat.dart';


// class GemmaLocalService {
//   final InferenceChat _chat;

//   GemmaLocalService(this._chat);

//   Future<void> addQuery(Message message) => _chat.addQuery(message);

//   /// Process message and return stream - back to direct streaming!
//   Future<Stream<ModelResponse>> processMessage(Message message) async {
//     debugPrint('GemmaLocalService: processMessage() called with: "${message.text}"');
//     debugPrint('GemmaLocalService: Adding query to chat: "${message.text}"');
//     await _chat.addQuery(message);
//     debugPrint('GemmaLocalService: Using direct InferenceChat stream (function handling: integrated)');
    
//     // Return direct stream from InferenceChat - no more intermediate processing!
//     return _chat.generateChatResponseAsync();
//   }

//   /// Legacy method for backward compatibility
//   Stream<ModelResponse> processMessageAsync(Message message) async* {
//     await _chat.addQuery(message);
//     yield* _chat.generateChatResponseAsync();
//   }
// }
