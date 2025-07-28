import 'pigeon.g.dart';

enum GemmaModel {

  // Gemma 3n 2B Models
  gemma3nGpu_2B(
    url:
    'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task',
    filename: 'gemma-3n-E2B-it-int4.task',
    displayName: 'Gemma 3n E2B IT Multimodal (GPU)',
    preferredBackend: PreferredBackend.gpu,
    temperature: 1.0,
    topK: 64,
    topP: 0.95,
    supportImage: true,
    maxTokens: 4096,
    maxNumImages: 1,
    supportsFunctionCalls: true,
  ),
  gemma3nCpu_2B(
    url:
    'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task',
    filename: 'gemma-3n-E2B-it-int4.task',
    displayName: 'Gemma 3n E2B IT Multimodal (CPU)',
    preferredBackend: PreferredBackend.cpu,
    temperature: 1.0,
    topK: 64,
    topP: 0.95,
    supportImage: true,
    maxTokens: 4096,
    maxNumImages: 1,
    supportsFunctionCalls: true,
  ),

  // Gemma 3n 4B Models
  gemma3nGpu_4B(
    url:
    'https://huggingface.co/google/gemma-3n-E4B-it-litert-preview/resolve/main/gemma-3n-E4B-it-int4.task',
    filename: 'gemma-3n-E4B-it-int4.task',
    displayName: 'Gemma 3n E4B IT Multimodal (GPU)',
    preferredBackend: PreferredBackend.gpu,
    temperature: 1.0,
    topK: 64,
    topP: 0.95,
    supportImage: true,
    maxTokens: 4096,
    maxNumImages: 1,
    supportsFunctionCalls: true,
  ),
  gemma3nCpu_4B(
    url:
    'https://huggingface.co/google/gemma-3n-E4B-it-litert-preview/resolve/main/gemma-3n-E4B-it-int4.task',
    filename: 'gemma-3n-E4B-it-int4.task',
    displayName: 'Gemma 3n E4B IT Multimodal (CPU)',
    preferredBackend: PreferredBackend.cpu,
    temperature: 1.0,
    topK: 64,
    topP: 0.95,
    supportImage: true,
    maxTokens: 4096,
    maxNumImages: 1,
    supportsFunctionCalls: true,
  ),

  // Gemma 3 1B Models
  gemma3Gpu_1B(
    url:
    'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv2048.task',
    filename: 'Gemma3-1B-IT_multi-prefill-seq_q4_ekv2048.task',
    displayName: 'Gemma3 1B IT q4 (GPU)',
    preferredBackend: PreferredBackend.gpu,
    temperature: 1.0,
    topK: 64,
    topP: 0.95,
    maxTokens: 1024,
  ),
  gemma3Cpu_1B(
    url:
    'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv2048.task',
    filename: 'Gemma3-1B-IT_multi-prefill-seq_q4_ekv2048.task',
    displayName: 'Gemma3 1B IT q4 (CPU)',
    preferredBackend: PreferredBackend.cpu,
    temperature: 1.0,
    topK: 64,
    topP: 0.95,
    maxTokens: 1024,
  );

  // Define fields for the enum
  final String url;
  final String filename;
  final String displayName;
  final PreferredBackend preferredBackend;
  final double temperature;
  final int topK;
  final double topP;
  final bool supportImage;
  final int maxTokens;
  final int? maxNumImages;
  final bool supportsFunctionCalls;

  // Constructor for the enum
  const GemmaModel({
    required this.url,
    required this.filename,
    required this.displayName,
    required this.preferredBackend,
    required this.temperature,
    required this.topK,
    required this.topP,
    this.supportImage = false,
    this.maxTokens = 1024,
    this.maxNumImages,
    this.supportsFunctionCalls = false,
  });
}