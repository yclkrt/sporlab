import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lingo_easy/lingo_easy.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sporlab/core/theme/app_colors.dart';
import 'package:sporlab/core/theme/app_gradients.dart';
import 'package:sporlab/core/widgets/main_scaffold.dart';
import 'package:sporlab/core/services/voice_command_service.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

enum MatchPhase {
  fighting, // Normal raunt devam ediyor veya başlatılmayı bekliyor
  announcingWinner, // Raunt kazananı ekranda gösteriliyor (3 saniye)
  restTime, // 1 dakikalık dinlenme süresi geriye sayıyor
  matchOver, // Maç tamamlandı
}

class TaekwondoScoreboardPage extends ConsumerStatefulWidget {
  const TaekwondoScoreboardPage({super.key});

  @override
  ConsumerState<TaekwondoScoreboardPage> createState() =>
      _TaekwondoScoreboardPageState();
}

class _TaekwondoScoreboardPageState
    extends ConsumerState<TaekwondoScoreboardPage> {
  // Best of 3 Raunt Takibi
  int _chungRoundsWon = 0;
  int _hongRoundsWon = 0;
  int _currentRound = 1;

  // Raunt İçi Puanlar ve Cezalar (Her rauntta sıfırlanır)
  int _chungScore = 0;
  int _hongScore = 0;
  int _chungPenalties = 0;
  int _hongPenalties = 0;

  // Süre Yönetimi
  int _roundDurationSec = 120; // Varsayılan 2 dakika (120 sn)
  int _remainingMs = 120 * 1000;
  bool _isRunning = false;
  Timer? _timer;
  DateTime? _lastTickTime;

  // Mola / Dinlenme Yönetimi (1 Dakika)
  MatchPhase _phase = MatchPhase.fighting;
  int _restRemainingMs = 60 * 1000;
  Timer? _restTimer;
  Timer? _announcementTimer;

  String _lastRoundWinnerName = '';
  Color _lastRoundWinnerColor = Colors.blue;
  String _lastRoundReason = '';
  String _lastRoundBadge = '';

  // Sesli Komut Yönetimi
  final VoiceCommandService _voiceService = VoiceCommandService();
  bool _isVoiceControlActive = false;
  String _lastRecognizedText = '';

  @override
  void dispose() {
    _timer?.cancel();
    _restTimer?.cancel();
    _announcementTimer?.cancel();
    _voiceService.stopListening();
    super.dispose();
  }

  void _startTimer() {
    if (_phase != MatchPhase.fighting) return;

    if (_remainingMs <= 0) {
      setState(() {
        _remainingMs = _roundDurationSec * 1000;
      });
    }

    _timer?.cancel();
    _lastTickTime = DateTime.now();

    // 40ms (~25fps) aralıklarla hassas milisaniye sayımı
    _timer = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      final elapsed = now.difference(_lastTickTime!).inMilliseconds;
      _lastTickTime = now;

      if (_remainingMs > elapsed) {
        setState(() {
          _remainingMs -= elapsed;
        });
      } else {
        setState(() {
          _remainingMs = 0;
        });
        _pauseTimer();
        _handleTimeOut();
      }
    });

    setState(() {
      _isRunning = true;
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
    });
  }

  void _resetTimer() {
    _pauseTimer();
    setState(() {
      _remainingMs = _roundDurationSec * 1000;
    });
  }

  /// Puan Ekle
  void _addScore(bool isChung, int points) {
    if (_phase != MatchPhase.fighting) {
      debugPrint('⚠️ _addScore called but phase is $_phase, not fighting');
      return;
    }

    debugPrint('✅ _addScore: isChung=$isChung, points=$points');
    setState(() {
      if (isChung) {
        _chungScore += points;
      } else {
        _hongScore += points;
      }
    });

    _checkAutomaticRoundEnd();
  }

  /// Puan Çıkar (Hatalı giriş düzeltme)
  void _subtractScore(bool isChung, int points) {
    if (_phase != MatchPhase.fighting) return;

    setState(() {
      if (isChung) {
        _chungScore = (_chungScore - points).clamp(0, 999);
      } else {
        _hongScore = (_hongScore - points).clamp(0, 999);
      }
    });
  }

  /// Ceza (Gam-jeom) Ekle (+1 puan rakibe verilir)
  void _addPenalty(bool isChung) {
    if (_phase != MatchPhase.fighting) {
      debugPrint('⚠️ _addPenalty called but phase is $_phase, not fighting');
      return;
    }

    debugPrint('✅ _addPenalty: isChung=$isChung');
    setState(() {
      if (isChung) {
        _chungPenalties++;
        _hongScore += 1;
      } else {
        _hongPenalties++;
        _chungScore += 1;
      }
    });

    _checkAutomaticRoundEnd();
  }

  /// Ceza Geri Al
  void _removePenalty(bool isChung) {
    if (_phase != MatchPhase.fighting) return;

    setState(() {
      if (isChung && _chungPenalties > 0) {
        _chungPenalties--;
        _hongScore = (_hongScore - 1).clamp(0, 999);
      } else if (!isChung && _hongPenalties > 0) {
        _hongPenalties--;
        _chungScore = (_chungScore - 1).clamp(0, 999);
      }
    });
  }

  /// Otomatik Raunt Bitiş Kuralları Kontrolü (12 Puan Farkı veya 5 Ceza)
  void _checkAutomaticRoundEnd() {
    if (_phase != MatchPhase.fighting) return;

    // 1. Kural: 5 Ceza (Gam-jeom) Kuralı
    if (_chungPenalties >= 5) {
      _endRound(
        winnerIsChung: false,
        reason:
            '${context.ln('chung_received_5_penalties')} (Gam-jeom ${context.ln('boundary')})',
        badge: '5 GAM-JEOM',
      );
      return;
    }
    if (_hongPenalties >= 5) {
      _endRound(
        winnerIsChung: true,
        reason:
            '${context.ln('hong_received_5_penalties')} (Gam-jeom ${context.ln('boundary')})',
        badge: '5 GAM-JEOM',
      );
      return;
    }

    // 2. Kural: 12 Puan Farkı Kuralı (Point Gap - PTG)
    if (_chungScore - _hongScore >= 12) {
      _endRound(
        winnerIsChung: true,
        reason:
            '12 ${context.ln('avantage_based_on_point_difference')} ($_chungScore - $_hongScore)',
        badge: '12 ${context.ln('point_gap').toUpperCase()} (PTG)',
      );
      return;
    }
    if (_hongScore - _chungScore >= 12) {
      _endRound(
        winnerIsChung: false,
        reason:
            '12 ${context.ln('avantage_based_on_point_difference')} ($_hongScore - $_chungScore)',
        badge: '12 ${context.ln('point_gap').toUpperCase()} (PTG)',
      );
      return;
    }
  }

  /// Süre Bittiğinde Kazananı Belirle
  void _handleTimeOut() {
    HapticFeedback.heavyImpact();

    if (_chungScore > _hongScore) {
      _endRound(
        winnerIsChung: true,
        reason:
            '${context.ln('points_lead_at_the_end_of_the_match')} ($_chungScore - $_hongScore)',
        badge: context.ln('expiration').toUpperCase(),
      );
    } else if (_hongScore > _chungScore) {
      _endRound(
        winnerIsChung: false,
        reason:
            '${context.ln('points_lead_at_the_end_of_the_match')} ($_hongScore - $_chungScore)',
        badge: context.ln('expiration').toUpperCase(),
      );
    } else {
      // Puanlar eşitse: Beraberlik Çözümü Dialogu
      _showTieBreakerDialog();
    }
  }

  /// Beraberlik Durumunda Hakem Kararı / Üstünlük Seçimi
  void _showTieBreakerDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.balance, color: AppColors.warning),
            SizedBox(width: 10),
            Text(context.ln('the_round_ended_in_a_draw')),
          ],
        ),
        content: Text(
          '${context.ln('scores_are_tied')} ($_chungScore - $_hongScore).\n${context.ln('select_the_side_that_achieved_technical_superiority_according_to_taekwondo_rules')}:',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _endRound(
                winnerIsChung: true,
                reason: context.ln('technical_superiority_referee_decision'),
                badge: context.ln('solution_for_a_draw').toUpperCase(),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF1565C0),
            ),
            child: Text(
              'CHUNG ${context.ln('to_win').toUpperCase()}',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _endRound(
                winnerIsChung: false,
                reason: context.ln('technical_superiority_referee_decision'),
                badge: context.ln('solution_for_a_draw').toUpperCase(),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFC62828),
            ),
            child: Text(
              'HONG ${context.ln('to_win').toUpperCase()}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// Raundu Sonlandır, Kazananı Göster ve 1 Dakikalık Dinlenme Süresini Başlat
  void _endRound({
    required bool winnerIsChung,
    required String reason,
    required String badge,
  }) {
    _pauseTimer();
    HapticFeedback.vibrate();

    int newChungWins = _chungRoundsWon;
    int newHongWins = _hongRoundsWon;

    if (winnerIsChung) {
      newChungWins++;
    } else {
      newHongWins++;
    }

    final winnerName = winnerIsChung
        ? 'CHUNG (${context.ln('blue').toUpperCase()})'
        : 'HONG (${context.ln('red').toUpperCase()})';
    final winnerColor = winnerIsChung
        ? const Color(0xFF1565C0)
        : const Color(0xFFC62828);

    setState(() {
      _chungRoundsWon = newChungWins;
      _hongRoundsWon = newHongWins;
      _lastRoundWinnerName = winnerName;
      _lastRoundWinnerColor = winnerColor;
      _lastRoundReason = reason;
      _lastRoundBadge = badge;
    });

    // Maç Bitti mi? (2 Raunt Kazanan Şampiyon Olur)
    final matchWon = newChungWins >= 2 || newHongWins >= 2;

    if (matchWon) {
      setState(() {
        _phase = MatchPhase.matchOver;
      });
      _showMatchWinnerDialog(
        winnerName: winnerName,
        winnerColor: winnerColor,
        reason: reason,
        finalScore: '$newChungWins - $newHongWins',
      );
    } else {
      // 1. Adım: Kazananı 3.5 saniye göster
      setState(() {
        _phase = MatchPhase.announcingWinner;
      });

      _announcementTimer?.cancel();
      _announcementTimer = Timer(const Duration(milliseconds: 5000), () {
        if (!mounted) return;
        _startRestTimer();
      });
    }
  }

  /// 1 Dakikalık Dinlenme / Mola Süresini Başlat
  void _startRestTimer() {
    _restTimer?.cancel();
    setState(() {
      _phase = MatchPhase.restTime;
      _restRemainingMs = 60 * 1000; // 1 Dakika (60 saniye)
    });

    _lastTickTime = DateTime.now();

    _restTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      final elapsed = now.difference(_lastTickTime!).inMilliseconds;
      _lastTickTime = now;

      if (_restRemainingMs > elapsed) {
        setState(() {
          _restRemainingMs -= elapsed;
        });
      } else {
        timer.cancel();
        _autoPrepareNextRound();
      }
    });
  }

  /// Dinlenme Süresi Bitince Sonraki Raundu Otomatik Hazırla
  void _autoPrepareNextRound() {
    _restTimer?.cancel();
    HapticFeedback.heavyImpact();

    setState(() {
      _currentRound++;
      _chungScore = 0;
      _hongScore = 0;
      _chungPenalties = 0;
      _hongPenalties = 0;
      _remainingMs = _roundDurationSec * 1000;
      _isRunning = false;
      _phase = MatchPhase.fighting;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$_currentRound. ${context.ln('ready_to_start_the_round')}!',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.accent,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Maç Kazananı Kutlama Dialogu
  void _showMatchWinnerDialog({
    required String winnerName,
    required Color winnerColor,
    required String reason,
    required String finalScore,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          backgroundColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: winnerColor.withValues(alpha: 0.15),
                  ),
                  child: Icon(
                    Icons.emoji_events_rounded,
                    size: 48,
                    color: winnerColor,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  context.ln('winning').toUpperCase(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  winnerName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: winnerColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${context.ln('round_score')}: $finalScore',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  reason,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _resetMatch();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: winnerColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      context.ln('start_a_new_match').toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Tüm Maçı Sıfırla
  void _resetMatch() {
    _pauseTimer();
    _restTimer?.cancel();
    _announcementTimer?.cancel();
    setState(() {
      _chungRoundsWon = 0;
      _hongRoundsWon = 0;
      _currentRound = 1;
      _chungScore = 0;
      _hongScore = 0;
      _chungPenalties = 0;
      _hongPenalties = 0;
      _remainingMs = _roundDurationSec * 1000;
      _isRunning = false;
      _phase = MatchPhase.fighting;
    });
  }


  // ==================== SESLI KOMUT YÖNETİMİ ====================

  /// Sesli kontrolü başlat / durdur
  Future<void> _toggleVoiceControl() async {
    if (_isVoiceControlActive) {
      await _stopVoiceControl();
    } else {
      await _startVoiceControl();
    }
  }

  /// Sesli komut dinlemeyi başlat
  Future<void> _startVoiceControl() async {
    // Mikrofon izin durumunu kontrol et
    final micStatus = await Permission.microphone.status;
    
    if (micStatus.isGranted) {
      // İzin zaten verilmiş, doğrudan başlat
      await _initializeVoiceService();
    } else if (micStatus.isPermanentlyDenied) {
      // İzin kalıcı olarak reddedildi, ayarlara yönlendir
      if (mounted) _showPermissionSettingsDialog();
    } else {
      // İzin iste
      final result = await Permission.microphone.request();
      if (result.isGranted) {
        await _initializeVoiceService();
      } else if (result.isPermanentlyDenied) {
        if (mounted) _showPermissionSettingsDialog();
      } else {
        if (mounted) {
          _showCommandFeedback('Mikrofon izni verilmedi', isError: true);
        }
      }
    }
  }

  /// Sesli servisi başlat
  Future<void> _initializeVoiceService() async {
    debugPrint('🎤 Initializing voice service...');
    final initialized = await _voiceService.initialize();
    if (!initialized) {
      debugPrint('❌ Voice service initialization failed');
      if (mounted) {
        _showCommandFeedback('Sesli tanıma başlatılamadı', isError: true);
      }
      return;
    }

    debugPrint('✅ Voice service initialized successfully');
    setState(() {
      _isVoiceControlActive = true;
    });

    await _startListeningSession();
    if (mounted) {
      _showCommandFeedback('🎤 Sesli komut aktif - Dinleniyor...');
    }
  }

  /// İzin ayarları dialogunu göster
  void _showPermissionSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.mic_off, color: Colors.redAccent, size: 28),
            const SizedBox(width: 12),
            const Text('Mikrofon İzni Gerekli'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sesli komut özelliğini kullanabilmek için mikrofon izni gereklidir.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber.shade700, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'İzin daha sonra reddedildi. Lütfen uygulama ayarlarından mikrofon iznini etkinleştirin.',
                      style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            icon: const Icon(Icons.settings, size: 18),
            label: const Text('Ayarları Aç'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Dinleme oturumu başlat
  Future<void> _startListeningSession() async {
    if (!_isVoiceControlActive) return;

    await _voiceService.startListening(
      onResult: (SpeechRecognitionResult result) {
        debugPrint('🎤 Speech result: finalResult=${result.finalResult}, words="${result.recognizedWords}"');
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          _processVoiceCommand(result.recognizedWords);
          // Sürekli dinleme için yeniden başlat
          Future.delayed(const Duration(milliseconds: 500), () {
            if (_isVoiceControlActive && mounted) {
              _startListeningSession();
            }
          });
        }
      },
      onDone: () {
        debugPrint('🎤 Listening session done, restarting...');
        // Dinleme bitti yeniden başlat (sürekli dinleme modu)
        if (_isVoiceControlActive && mounted) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (_isVoiceControlActive && mounted) {
              _startListeningSession();
            }
          });
        }
      },
    );
  }

  /// Sesli komut durdur
  Future<void> _stopVoiceControl() async {
    await _voiceService.stopListening();
    setState(() {
      _isVoiceControlActive = false;
    });
    _showCommandFeedback('Sesli komut kapatıldı');
  }


  /// Tanınan komutları işle
  void _processVoiceCommand(String command) {
    final normalizedCommand = _normalizeCommand(command.toLowerCase().trim());

    // Debug logging
    debugPrint('🎤 Voice command received: "$command"');
    debugPrint('🎤 Normalized command: "$normalizedCommand"');
    debugPrint('🎤 Current phase: $_phase');
    debugPrint('🎤 Is running: $_isRunning');

    setState(() {
      _lastRecognizedText = command;
    });

    // === CEZA KOMUTLARI (Gam-jeom) ===
    if (_matchAny(normalizedCommand, [
      'chung gam jeom', 'mavi gam jeom', 'maviye gam jeom',
      'maviye ceza', 'mavi ceza', 'chong gam jeom',
    ])) {
      _addPenalty(true);
      _showCommandFeedback('🔵 CHUNG Ceza (Gam-jeom)! Hong +1 puan');
      HapticFeedback.mediumImpact();
      return;
    }

    if (_matchAny(normalizedCommand, [
      'hong gam jeom', 'kırmızı gam jeom', 'kırmızıya gam jeom',
      'kırmızıya ceza', 'kırmızı ceza',
    ])) {
      _addPenalty(false);
      _showCommandFeedback('🔴 HONG Ceza (Gam-jeom)! Chung +1 puan');
      HapticFeedback.mediumImpact();
      return;
    }

    // === CEZA GERİ AL ===
    if (_matchAny(normalizedCommand, [
      'mavi ceza geri al', 'chung ceza geri al',
      'mavi ceza iptal', 'mavi ceza sil',
    ])) {
      _removePenalty(true);
      _showCommandFeedback('🔵 CHUNG ceza geri alındı');
      return;
    }

    if (_matchAny(normalizedCommand, [
      'kırmızı ceza geri al', 'hong ceza geri al',
      'kırmızı ceza iptal', 'kırmızı ceza sil',
    ])) {
      _removePenalty(false);
      _showCommandFeedback('🔴 HONG ceza geri alındı');
      return;
    }


    // === PUAN EKLE - CHUNG (Mavi) ===
    if (_matchAny(normalizedCommand, [
      'chung puan', 'chong puan', 'mavi puan', 'maviye puan',
      'mavi bir puan', 'chung bir puan', 'chong bir puan',
      'maviye bir puan', 'chung 1 puan', 'chong 1 puan',
    ])) {
      _addScore(true, 1);
      _showCommandFeedback('🔵 CHUNG +1 Puan');
      HapticFeedback.selectionClick();
      return;
    }

    if (_matchAny(normalizedCommand, [
      'mavi iki puan', 'chung iki puan', 'chong iki puan',
      'maviye iki puan', 'chung 2 puan', 'chong 2 puan', 'mavi 2 puan',
    ])) {
      _addScore(true, 2);
      _showCommandFeedback('🔵 CHUNG +2 Puan');
      HapticFeedback.selectionClick();
      return;
    }

    if (_matchAny(normalizedCommand, [
      'mavi üc puan', 'chung üc puan', 'chong üc puan',
      'maviye üc puan', 'chung 3 puan', 'chong 3 puan', 'mavi 3 puan',
      'mavi üç puan', 'chung üç puan', 'chong üç puan', 'maviye üç puan',
    ])) {
      _addScore(true, 3);
      _showCommandFeedback('🔵 CHUNG +3 Puan');
      HapticFeedback.selectionClick();
      return;
    }

    if (_matchAny(normalizedCommand, [
      'mavi dort puan', 'chung dort puan', 'chong dort puan',
      'maviye dort puan', 'chung 4 puan', 'chong 4 puan', 'mavi 4 puan',
      'mavi dört puan', 'chung dört puan', 'chong dört puan', 'maviye dört puan',
    ])) {
      _addScore(true, 4);
      _showCommandFeedback('🔵 CHUNG +4 Puan');
      HapticFeedback.selectionClick();
      return;
    }

    if (_matchAny(normalizedCommand, [
      'mavi bes puan', 'chung bes puan', 'chong bes puan',
      'maviye bes puan', 'chung 5 puan', 'chong 5 puan', 'mavi 5 puan',
      'mavi beş puan', 'chung beş puan', 'chong beş puan', 'maviye beş puan',
    ])) {
      _addScore(true, 5);
      _showCommandFeedback('🔵 CHUNG +5 Puan');
      HapticFeedback.selectionClick();
      return;
    }

    // === PUAN EKLE - HONG (Kırmızı) ===
    if (_matchAny(normalizedCommand, [
      'hong puan', 'kırmızı puan', 'kırmızıya puan',
      'kırmızı bir puan', 'hong bir puan', 'hong 1 puan', 'kırmızı 1 puan',
    ])) {
      _addScore(false, 1);
      _showCommandFeedback('🔴 HONG +1 Puan');
      HapticFeedback.selectionClick();
      return;
    }

    if (_matchAny(normalizedCommand, [
      'kırmızı iki puan', 'hong iki puan', 'kırmızıya iki puan',
      'hong 2 puan', 'kırmızı 2 puan',
    ])) {
      _addScore(false, 2);
      _showCommandFeedback('🔴 HONG +2 Puan');
      HapticFeedback.selectionClick();
      return;
    }

    if (_matchAny(normalizedCommand, [
      'kırmızı üc puan', 'hong üc puan', 'kırmızıya üc puan',
      'hong 3 puan', 'kırmızı 3 puan', 'kırmızı üç puan', 'hong üç puan', 'kırmızıya üç puan',
    ])) {
      _addScore(false, 3);
      _showCommandFeedback('🔴 HONG +3 Puan');
      HapticFeedback.selectionClick();
      return;
    }

    if (_matchAny(normalizedCommand, [
      'kırmızı dort puan', 'hong dort puan', 'kırmızıya dort puan',
      'hong 4 puan', 'kırmızı 4 puan', 'kırmızı dört puan', 'hong dört puan', 'kırmızıya dört puan',
    ])) {
      _addScore(false, 4);
      _showCommandFeedback('🔴 HONG +4 Puan');
      HapticFeedback.selectionClick();
      return;
    }

    if (_matchAny(normalizedCommand, [
      'kırmızı bes puan', 'hong bes puan', 'kırmızıya bes puan',
      'hong 5 puan', 'kırmızı 5 puan', 'kırmızı beş puan', 'hong beş puan', 'kırmızıya beş puan',
    ])) {
      _addScore(false, 5);
      _showCommandFeedback('🔴 HONG +5 Puan');
      HapticFeedback.selectionClick();
      return;
    }

    // === PUAN ÇIKAR (Düzeltme) ===
    if (_matchAny(normalizedCommand, [
      'mavi puan geri al', 'chung puan geri al', 'chong puan geri al',
      'mavi puan sil', 'mavi puan iptal',
    ])) {
      _subtractScore(true, 1);
      _showCommandFeedback('🔵 CHUNG -1 Puan (geri alındı)');
      return;
    }

    if (_matchAny(normalizedCommand, [
      'kırmızı puan geri al', 'hong puan geri al',
      'kırmızı puan sil', 'kırmızı puan iptal',
    ])) {
      _subtractScore(false, 1);
      _showCommandFeedback('🔴 HONG -1 Puan (geri alındı)');
      return;
    }

    // === ZAMAN YÖNETİMİ ===
    // "kalyeo" - Taekwondoya özel: Dur! Sporcular durur, saat durur
    if (_matchAny(normalizedCommand, [
      'kalyeo', 'kalyo', 'galyeo', 'galyo', 'kalio', 'kalyo',
      'kaliyo', 'dur taekwondo', 'dur sporcular',
    ])) {
      if (_isRunning && _phase == MatchPhase.fighting) {
        _pauseTimer();
        _showCommandFeedback('🛑 KALYEO! Sporcular durdu, saat durdu');
        HapticFeedback.heavyImpact();
      } else if (!_isRunning && _phase == MatchPhase.fighting) {
        _showCommandFeedback('Zaten duraklatılmış durumda');
      } else {
        _showCommandFeedback('Şu an dövüş süresi değil');
      }
      return;
    }

    // "kes out" / "kye-soğ" - Taekwondoya özel: Maçı devam ettir
    if (_matchAny(normalizedCommand, [
      'kes out', 'keso', 'kye soğ', 'kyesog', 'kye sog',
      'kesh', 'kesh', 'devam taekwondo', 'devam sporcular',
      'saldır', 'hücum', 'dövüş devam',
    ])) {
      if (!_isRunning && _phase == MatchPhase.fighting) {
        _startTimer();
        _showCommandFeedback('▶️ KES OUT! Maç devam ediyor!');
        HapticFeedback.heavyImpact();
      } else if (_isRunning) {
        _showCommandFeedback('Maç zaten devam ediyor');
      } else {
        _showCommandFeedback('Şu an dövüş süresi değil');
      }
      return;
    }

    // "başla", "start", "dövüşü başlat" - Genel başlatma
    if (_matchAny(normalizedCommand, [
      'basla', 'dövüsü basla', 'macı basla', 'baslat',
      'zamanı basla', 'saati basla', 'devam et', 'devam',
    ])) {
      if (!_isRunning && _phase == MatchPhase.fighting) {
        _startTimer();
        _showCommandFeedback('⏱️ Zaman Başlatıldı!');
        HapticFeedback.heavyImpact();
      } else if (_phase != MatchPhase.fighting) {
        _showCommandFeedback('Şu an dövüş süresi değil');
      }
      return;
    }

    if (_matchAny(normalizedCommand, [
      'dur', 'duraklat', 'durdur', 'zamanı durdur', 'saati durdur', 'bekle',
    ])) {
      if (_isRunning) {
        _pauseTimer();
        _showCommandFeedback('⏸️ Zaman Duraklatıldı');
        HapticFeedback.heavyImpact();
      }
      return;
    }

    // === MAÇ YÖNETİMİ ===
    if (_matchAny(normalizedCommand, [
      'sıfırla', 'macı sıfırla', 'yeniden basla', 'yeni mac', 'hepsini sıfırla',
    ])) {
      _resetMatch();
      _showCommandFeedback('🔄 Maç Sıfırlandı');
      HapticFeedback.heavyImpact();
      return;
    }

    if (_matchAny(normalizedCommand, [
      'raundu bitir', 'raund bitis', 'raundı bitir', 'round bitir',
    ])) {
      if (_phase == MatchPhase.fighting && _remainingMs > 0) {
        _handleTimeOut();
        _showCommandFeedback('🏁 Raund Sona Erdi');
        HapticFeedback.heavyImpact();
      }
      return;
    }

    // === KOMUTU ANLAMADIM ===
    debugPrint('❌ Command not recognized: "$command" (normalized: "$normalizedCommand")');
    _showCommandFeedback('❌ Anlaşılmadı: "$command"', isError: true);
  }


  /// Komut normalize et
  String _normalizeCommand(String text) {
    return text
        .replaceAll(RegExp(r'[^\w\sıçğüöşİÇĞÜÖŞ]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('chong', 'chung')
        .replaceAll('kızıl', 'kırmızı')
        .trim();
  }

  /// Komut eşleşme kontrolü
  bool _matchAny(String command, List<String> patterns) {
    for (final pattern in patterns) {
      if (command.contains(pattern) || pattern.contains(command)) {
        debugPrint('✅ Pattern matched: "$pattern" in command "$command"');
        return true;
      }
      if (_isSimilar(command, pattern)) {
        debugPrint('✅ Similar pattern matched: "$pattern" ~ "$command"');
        return true;
      }
    }
    return false;
  }

  /// İki string arasında benzerlik kontrolü
  bool _isSimilar(String a, String b) {
    if (a.length < 5 || b.length < 5) return false;
    final wordsA = a.split(' ');
    final wordsB = b.split(' ');
    for (final wordA in wordsA) {
      if (wordA.length < 3) continue;
      for (final wordB in wordsB) {
        if (wordB.length < 3) continue;
        if (wordA.contains(wordB) || wordB.contains(wordA)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Komut feedback göster
  void _showCommandFeedback(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError ? Colors.redAccent : Colors.greenAccent,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError 
            ? const Color(0xFF4E1E1E) 
            : const Color(0xFF1E4E2E),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: isError ? 2 : 1, milliseconds: 500),
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _setCustomRoundDuration(int totalSeconds) {
    _pauseTimer();
    setState(() {
      _roundDurationSec = totalSeconds;
      _remainingMs = totalSeconds * 1000;
    });
  }

  /// 1 dakikadan fazla ise: MM:SS
  /// 1 dakikadan az ise: SS.cs (Saniye ve Salise/Milisaniye)
  String _formatDisplayTime(int ms) {
    if (ms >= 60000) {
      final totalSec = ms ~/ 1000;
      final minutes = (totalSec ~/ 60).toString().padLeft(2, '0');
      final seconds = (totalSec % 60).toString().padLeft(2, '0');
      return '$minutes:$seconds';
    } else {
      final seconds = (ms ~/ 1000).toString().padLeft(2, '0');
      final centisecs = ((ms % 1000) ~/ 10).toString().padLeft(2, '0');
      return '$seconds.$centisecs';
    }
  }

  String _formatRoundBadgeTime(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  void _showDurationSettingsDialog(BuildContext context, bool isDark) {
    if (_phase != MatchPhase.fighting) return;

    int selectedMinutes = _roundDurationSec ~/ 60;
    int selectedSeconds = _roundDurationSec % 60;
    final minController = TextEditingController(
      text: selectedMinutes.toString(),
    );
    final secController = TextEditingController(
      text: selectedSeconds.toString(),
    );

    final presetDurations = [
      {'label': '1 Dk', 'seconds': 60},
      {'label': '1.5 Dk', 'seconds': 90},
      {'label': '2 Dk (Standart)', 'seconds': 120},
      {'label': '3 Dk', 'seconds': 180},
      {'label': '5 Dk', 'seconds': 300},
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              backgroundColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.timer_outlined,
                              color: AppColors.accent,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              context.ln('set_round_duration'),
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        context.ln('quick_options'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white54 : Colors.black54,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: presetDurations.map((item) {
                          final secs = item['seconds'] as int;
                          final isSelected = _roundDurationSec == secs;
                          return ChoiceChip(
                            label: Text(item['label'] as String),
                            selected: isSelected,
                            selectedColor: AppColors.accent,
                            backgroundColor: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.04),
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : Colors.black87),
                            ),
                            onSelected: (selected) {
                              if (selected) {
                                setDialogState(() {
                                  _setCustomRoundDuration(secs);
                                  minController.text = (secs ~/ 60).toString();
                                  secController.text = (secs % 60).toString();
                                });
                                Navigator.pop(ctx);
                              }
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        context.ln('set_custom_durations'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white54 : Colors.black54,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: minController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              decoration: InputDecoration(
                                labelText: context.ln('minute'),
                                labelStyle: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.black54,
                                ),
                                filled: true,
                                fillColor: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.black.withValues(alpha: 0.03),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            ':',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: secController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              decoration: InputDecoration(
                                labelText: context.ln('second'),
                                labelStyle: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.black54,
                                ),
                                filled: true,
                                fillColor: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.black.withValues(alpha: 0.03),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(
                                context.ln('cancel'),
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                final mins =
                                    int.tryParse(minController.text.trim()) ??
                                    0;
                                final secs =
                                    int.tryParse(secController.text.trim()) ??
                                    0;
                                final totalSecs = (mins * 60) + secs;
                                if (totalSecs > 0) {
                                  _setCustomRoundDuration(totalSecs);
                                  Navigator.pop(ctx);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                context.ln('save'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MainScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: isDark
                ? AppGradients.taekwondoDark
                : AppGradients.taekwondo,
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_martial_arts, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              "TAEKWONDO",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: context.ln('reset_match'),
            onPressed: _resetMatch,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF0D0D11), const Color(0xFF16161D)]
                : [const Color(0xFFF4F6FA), Colors.white],
          ),
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildTimerSection(isDark),
              const SizedBox(height: 16),
              _buildScoreboard(isDark),
              const SizedBox(height: 16),
              _buildScoringButtons(isDark),
              const SizedBox(height: 16),
              _buildPenaltySection(isDark),
              const SizedBox(height: 16),
              _buildVoiceControlPanel(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimerSection(bool isDark) {
    // 1. Durum: Raunt Kazananı Duyuru Alanı (3.5 Saniye)
    if (_phase == MatchPhase.announcingWinner) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E24) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _lastRoundWinnerColor.withValues(alpha: 0.4),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: _lastRoundWinnerColor.withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _lastRoundWinnerColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$_currentRound. ${context.ln('round_finish').toUpperCase()} ($_lastRoundBadge)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: _lastRoundWinnerColor,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.ln('round_winner').toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _lastRoundWinnerName,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: _lastRoundWinnerColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _lastRoundReason,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  context.ln('1_minute_rest_period_starting'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 2. Durum: 1 Dakikalık Dinlenme / Mola Süresi
    if (_phase == MatchPhase.restTime) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E24) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF11998E).withValues(alpha: 0.4),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF11998E).withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    context.ln('rest_break').toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                // Dinlenmeyi Atla Butonu
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _autoPrepareNextRound,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.ln('skip_the_break'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.skip_next, size: 14),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _formatDisplayTime(_restRemainingMs),
              style: TextStyle(
                fontSize: 52,
                fontWeight: FontWeight.w200,
                fontFamily: 'monospace',
                color: _restRemainingMs <= 10000
                    ? const Color(0xFFFF5252)
                    : const Color(0xFF38EF7D),
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_currentRound + 1}. ${context.ln('the_round_will_start_automatically')}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ],
        ),
      );
    }

    // 3. Durum: Normal Raunt / Dövüş Ekranı
    final isPaused =
        !_isRunning &&
        _remainingMs < (_roundDurationSec * 1000) &&
        _remainingMs > 0;
    final isUnderOneMinute = _remainingMs < 60000;
    final isCriticalTime = _remainingMs <= 10000 && _isRunning;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Raund Rozeti ve Best of 3 Durumu
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      gradient: isDark
                          ? AppGradients.taekwondoDark
                          : AppGradients.taekwondo,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${context.ln('round').toUpperCase()} $_currentRound/3',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),

              // Raund Süresi Ayarlama Butonu
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showDurationSettingsDialog(context, isDark),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.07)
                          : Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 14,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _formatRoundBadgeTime(_roundDurationSec),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.edit_outlined,
                          size: 12,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Süre Sayacı (1 dk altı ise SS.cs, üstü ise MM:SS)
          GestureDetector(
            onTap: () => _showDurationSettingsDialog(context, isDark),
            child: Column(
              children: [
                Text(
                  _formatDisplayTime(_remainingMs),
                  style: TextStyle(
                    fontSize: isUnderOneMinute ? 54 : 48,
                    fontWeight: FontWeight.w200,
                    fontFamily: 'monospace',
                    color: isCriticalTime
                        ? const Color(0xFFFF5252)
                        : (isDark ? Colors.white : Colors.black87),
                    letterSpacing: isUnderOneMinute ? 2 : 4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Başlat / Duraklat Butonları
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_isRunning) ...[
                // Süre çalışmıyorken: Tek BAŞLAT / DEVAM ET Butonu
                Expanded(
                  child: _buildTimerButton(
                    icon: Icons.play_arrow_rounded,
                    label: isPaused
                        ? context.ln('continue').toUpperCase()
                        : context.ln('start').toUpperCase(),
                    onTap: _startTimer,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
                    ),
                  ),
                ),
                if (isPaused) ...[
                  const SizedBox(width: 10),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _resetTimer,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.replay_rounded,
                          size: 22,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
              ] else ...[
                // Süre çalışıyorken: Tek DURAKLAT Butonu
                Expanded(
                  child: _buildTimerButton(
                    icon: Icons.pause_rounded,
                    label: context.ln('pause').toUpperCase(),
                    onTap: _pauseTimer,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF9900), Color(0xFFFF5E62)],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimerButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required LinearGradient gradient,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: gradient.colors.first.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreboard(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _buildPlayerCard(
            isDark: isDark,
            playerName: 'CHUNG',
            score: _chungScore,
            penalties: _chungPenalties,
            roundsWon: _chungRoundsWon,
            isBlue: true,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? const Color(0xFF2D2D3D)
                    : const Color(0xFFE0E0E0),
              ),
              child: Text(
                'VS',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildPlayerCard(
            isDark: isDark,
            playerName: 'HONG',
            score: _hongScore,
            penalties: _hongPenalties,
            roundsWon: _hongRoundsWon,
            isBlue: false,
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerCard({
    required bool isDark,
    required String playerName,
    required int score,
    required int penalties,
    required int roundsWon,
    required bool isBlue,
  }) {
    final gradient = isBlue
        ? const LinearGradient(colors: [Color(0xFF1565C0), Color(0xFF0D47A1)])
        : const LinearGradient(colors: [Color(0xFFC62828), Color(0xFFB71C1C)]);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.first.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Oyuncu Adı
          Text(
            playerName,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),

          // Kazanılan Raunt Noktaları (Best of 3 Takibi)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildRoundDot(filled: roundsWon >= 1),
              const SizedBox(width: 6),
              _buildRoundDot(filled: roundsWon >= 2),
            ],
          ),
          const SizedBox(height: 8),

          // Canlı Puan
          Text(
            '$score',
            style: const TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.w200,
              color: Colors.white,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 6),

          // Ceza Durumu (5 Ceza Sınırı)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: penalties >= 4
                  ? Colors.red.shade900.withValues(alpha: 0.8)
                  : Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: penalties >= 4
                  ? Border.all(color: Colors.yellowAccent, width: 1.5)
                  : null,
            ),
            child: Text(
              'Gam-jeom: $penalties / 5',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: penalties >= 4 ? Colors.yellowAccent : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoundDot({required bool filled}) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled
            ? Colors.amberAccent
            : Colors.white.withValues(alpha: 0.25),
        border: Border.all(
          color: filled ? Colors.amber : Colors.white.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: filled
            ? [
                BoxShadow(
                  color: Colors.amberAccent.withValues(alpha: 0.8),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }

  Widget _buildScoringButtons(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            context.ln('add_subtract_points').toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white54 : Colors.black45,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    const Text(
                      'CHUNG',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1565C0),
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildScoreButton(
                          '+1',
                          () => _addScore(true, 1),
                          const Color(0xFF1565C0),
                        ),
                        const SizedBox(width: 4),
                        _buildScoreButton(
                          '+2',
                          () => _addScore(true, 2),
                          const Color(0xFF1565C0),
                        ),
                        const SizedBox(width: 4),
                        _buildScoreButton(
                          '+3',
                          () => _addScore(true, 3),
                          const Color(0xFF1565C0),
                        ),
                        const SizedBox(width: 4),
                        _buildScoreButton(
                          '-1',
                          () => _subtractScore(true, 1),
                          Colors.grey,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    const Text(
                      'HONG',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFC62828),
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildScoreButton(
                          '+1',
                          () => _addScore(false, 1),
                          const Color(0xFFC62828),
                        ),
                        const SizedBox(width: 4),
                        _buildScoreButton(
                          '+2',
                          () => _addScore(false, 2),
                          const Color(0xFFC62828),
                        ),
                        const SizedBox(width: 4),
                        _buildScoreButton(
                          '+3',
                          () => _addScore(false, 3),
                          const Color(0xFFC62828),
                        ),
                        const SizedBox(width: 4),
                        _buildScoreButton(
                          '-1',
                          () => _subtractScore(false, 1),
                          Colors.grey,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScoreButton(String label, VoidCallback onTap, Color color) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 36,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPenaltySection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${context.ln('punishment').toUpperCase()} (GAM-JEOM)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white54 : Colors.black45,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _buildPenaltyButton(
                        label: 'CHUNG GAM-JEOM',
                        onTap: () => _addPenalty(true),
                        color: const Color(0xFF1565C0),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                      color: isDark ? Colors.white54 : Colors.black45,
                      tooltip: context.ln('take_back_the_penalty'),
                      onPressed: () => _removePenalty(true),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _buildPenaltyButton(
                        label: 'HONG GAM-JEOM',
                        onTap: () => _addPenalty(false),
                        color: const Color(0xFFC62828),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                      color: isDark ? Colors.white54 : Colors.black45,
                      tooltip: context.ln('take_back_the_penalty'),
                      onPressed: () => _removePenalty(false),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPenaltyButton({
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Sesli kontrol paneli
  Widget _buildVoiceControlPanel(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isVoiceControlActive
              ? const Color(0xFF00E676).withValues(alpha: 0.5)
              : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05)),
          width: _isVoiceControlActive ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _isVoiceControlActive
                ? const Color(0xFF00E676).withValues(alpha: 0.15)
                : (isDark ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.04)),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Başlık ve mikrofon ikonu
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isVoiceControlActive
                      ? const Color(0xFF00E676).withValues(alpha: 0.15)
                      : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _isVoiceControlActive ? Icons.mic : Icons.mic_none,
                  color: _isVoiceControlActive ? const Color(0xFF00E676) : (isDark ? Colors.white54 : Colors.black45),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SESLİ KONTROL',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white54 : Colors.black45,
                        letterSpacing: 2,
                      ),
                    ),
                    if (_isVoiceControlActive && _lastRecognizedText.isNotEmpty)
                      Text(
                        'Son: "$_lastRecognizedText"',
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              // Aktif dinleme göstergesi
              if (_isVoiceControlActive)
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF00E676),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Başlat / Durdur butonu
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _toggleVoiceControl,
              icon: Icon(
                _isVoiceControlActive ? Icons.stop : Icons.mic,
                size: 18,
              ),
              label: Text(
                _isVoiceControlActive ? 'DURDUR' : 'SESLİ KOMUT BAŞLAT',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isVoiceControlActive 
                    ? const Color(0xFFCF6679) 
                    : const Color(0xFF00E676),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Kullanılabilen komutlar
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _buildCommandChip('kalyeo', isDark),
              _buildCommandChip('kes out', isDark),
              _buildCommandChip('chung gam-jeom', isDark),
              _buildCommandChip('hong gam-jeom', isDark),
              _buildCommandChip('mavi puan', isDark),
              _buildCommandChip('kırmızı puan', isDark),
              _buildCommandChip('sıfırla', isDark),
              _buildCommandChip('raundu bitir', isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommandChip(String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white54 : Colors.black45,
        ),
      ),
    );
  }

}
