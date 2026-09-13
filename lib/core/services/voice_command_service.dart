import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceCommandService {
  static final VoiceCommandService _instance = VoiceCommandService._internal();
  factory VoiceCommandService() => _instance;
  VoiceCommandService._internal();

  final SpeechToText _speechToText = SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;

  bool get isListening => _isListening;
  bool get isAvailable => _speechToText.isAvailable;

  Future<bool> initialize() async {
    if (_isInitialized) return true;

    // Request microphone permission
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      return false;
    }

    _isInitialized = await _speechToText.initialize(
      onError: (error) {
        debugPrint('Speech recognition error: $error');
        _isListening = false;
      },
      onStatus: (status) {
        debugPrint('Speech recognition status: $status');
        if (status == 'notListening' || status == 'done') {
          _isListening = false;
        }
      },
    );

    return _isInitialized;
  }

  Future<void> startListening({
    required Function(SpeechRecognitionResult) onResult,
    required Function() onDone,
  }) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return;
    }

    if (_isListening) return;

    _isListening = true;
    debugPrint('🎤 Starting speech recognition...');
    await _speechToText.listen(
      onResult: (result) {
        onResult(result);
        // Call onDone when final result is received
        if (result.finalResult) {
          onDone();
        }
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        localeId: 'tr_TR',
        cancelOnError: false,
        partialResults: true,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  Future<void> stopListening() async {
    if (!_isListening) return;
    _isListening = false;
    await _speechToText.stop();
  }

  void dispose() {
    _speechToText.cancel();
  }
}

/// Parsed voice command data for creating a reminder
class VoiceCommandData {
  final String title;
  final TimeOfDay? time;
  final int offsetMinutes;
  final String? description;

  VoiceCommandData({
    required this.title,
    this.time,
    this.offsetMinutes = 0,
    this.description,
  });
}

/// Parses voice command text to extract reminder information
VoiceCommandData parseVoiceCommand(String text) {
  String processedText = text.toLowerCase().trim();
  TimeOfDay? extractedTime;
  int offsetMinutes = 0;
  String title = text;

  // Extract time patterns like "saat 8", "saat 14:30", "08:00'da", "14:30'da"
  final timePatterns = [
    RegExp(r'saat\s*(\d{1,2})[:\.]?(\d{2})?'),
    RegExp(r'(\d{1,2})[:\.](\d{2})\s*(?:da|de|ta|te)?'),
    RegExp(r'(\d{1,2})\s*(?:da|de|ta|te)'),
  ];

  for (final pattern in timePatterns) {
    final match = pattern.firstMatch(processedText);
    if (match != null) {
      int hour = int.parse(match.group(1)!);
      int minute = 0;
      if (match.group(2) != null) {
        minute = int.parse(match.group(2)!);
      }
      if (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
        extractedTime = TimeOfDay(hour: hour, minute: minute);
        break;
      }
    }
  }

  // Extract offset patterns like "15 dakika önce", "30 dk önce", "1 saat önce"
  final offsetPatterns = [
    RegExp(r'(\d+)\s*(?:dakika|dk)\s*önce'),
    RegExp(r'(\d+)\s*(?:saat)\s*önce'),
  ];

  for (int i = 0; i < offsetPatterns.length; i++) {
    final match = offsetPatterns[i].firstMatch(processedText);
    if (match != null) {
      final value = int.parse(match.group(1)!);
      offsetMinutes = i == 1 ? value * 60 : value; // Convert hours to minutes
      break;
    }
  }

  // Extract title - remove time and offset info to get cleaner title
  title = text
      .replaceAll(RegExp(r'saat\s*\d{1,2}[:\.]?\d{0,2}\s*(?:da|de|ta|te)?'), '')
      .replaceAll(RegExp(r'\d{1,2}[:\.]\d{2}\s*(?:da|de|ta|te)?'), '')
      .replaceAll(RegExp(r'\d+\s*(?:dakika|dk|saat)\s*önce'), '')
      .replaceAll(RegExp(r'hatırlatıcı\s*ekle'), '')
      .replaceAll(RegExp(r'hatırlat\s*beni'), '')
      .replaceAll(RegExp(r'hatırlat'), '')
      .trim();

  // If title is empty after cleaning, use a default
  if (title.isEmpty) {
    title = 'Sesli Hatırlatıcı';
  }

  // Capitalize first letter
  title = title[0].toUpperCase() + title.substring(1);

  return VoiceCommandData(
    title: title,
    time: extractedTime,
    offsetMinutes: offsetMinutes,
    description: 'Sesli komut ile oluşturuldu',
  );
}
