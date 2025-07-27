import 'pigeon.g.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

GemmaModel chosenModel = GemmaModel.values.firstWhere(
    (e) => e.filename == dotenv.env['HUGGINGFACE_MODEL_FILENAME'],
  );
  
enum GemmaModel {
  gemma3GpuLocalAsset(
    // model file should be pre-downloaded and placed in the assets folder
    url: 'assets/gemma3-1b-it-int4.task',
    filename: 'gemma3-1b-it-int4.task',
    displayName: 'Gemma3 1B IT (GPU / Local)',
    preferredBackend: PreferredBackend.gpu,
    temperature: 0.1,
    topK: 40,
    topP: 0.95,
  ),

  gemma3nLocalAsset(
    // model file should be pre-downloaded and placed in the assets folder
    url: '/data/user/0/com.automotiq.obdapp/app_flutter/gemma-3n-E2B-it-int4.task',
    filename: 'gemma-3n-E2B-it-int4.task',
    displayName: 'Gemma 3 Nano E2B IT Multimodal (Local Asset) ',
    preferredBackend: PreferredBackend.gpu,
    temperature: 0.1,
    topK: 5,
    topP: 0.95,
    supportsFunctionCalls: true,
  ),

  // Models from JSON - Gemma 3n E2B (Updated version)
  gemma3nGpu_2B(
    url:
    'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task',
    filename: 'gemma-3n-E2B-it-int4.task',
    displayName: 'Gemma 3n E2B IT Multimodal (GPU) 3.1Gb',
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
    displayName: 'Gemma 3n E2B IT Multimodal (CPU) 3.1Gb',
    preferredBackend: PreferredBackend.cpu,
    temperature: 1.0,
    topK: 64,
    topP: 0.95,
    supportImage: true,
    maxTokens: 4096,
    maxNumImages: 1,
    supportsFunctionCalls: true,
  ),

  gemma3nGpu_4B(
    url:
    'https://huggingface.co/google/gemma-3n-E4B-it-litert-preview/resolve/main/gemma-3n-E4B-it-int4.task',
    filename: 'gemma-3n-E4B-it-int4.task',
    displayName: 'Gemma 3n E4B IT Multimodal (GPU) 6.5Gb',
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
    displayName: 'Gemma 3n E4B IT Multimodal (CPU) 6.5Gb',
    preferredBackend: PreferredBackend.cpu,
    temperature: 1.0,
    topK: 64,
    topP: 0.95,
    supportImage: true,
    maxTokens: 4096,
    maxNumImages: 1,
    supportsFunctionCalls: true,
  ),

  // Models from JSON - Gemma3 1B IT q4 (Updated version)
  gemma3Gpu_1B(
    url:
    'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv2048.task',
    filename: 'Gemma3-1B-IT_multi-prefill-seq_q4_ekv2048.task',
    displayName: 'Gemma3 1B IT q4 (GPU) 0.5Gb',
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
    displayName: 'Gemma3 1B IT q4 (CPU) 0.5Gb',
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