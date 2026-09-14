import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lingo_easy/lingo_easy.dart';
import 'package:sporlab/core/theme/app_colors.dart';
import 'package:sporlab/features/dashboard/model/step_data.dart';
import 'package:sporlab/features/dashboard/providers/step_provider.dart';

class PedometerCard extends ConsumerStatefulWidget {
  const PedometerCard({super.key});

  @override
  ConsumerState<PedometerCard> createState() => _PedometerCardState();
}

class _PedometerCardState extends ConsumerState<PedometerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Initialize the step tracker service with context for localization
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(stepTrackerProvider.notifier).initialize(context);
        // Start animation after initialization
        if (mounted) {
          _pulseController.repeat(reverse: true);
        }
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Dil değişikliğini algıla ve lokalizasyonu güncelle
    ref.read(stepTrackerProvider.notifier).changeLanguage(context);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stepData = ref.watch(stepTrackerProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.45)
                : const Color(0xFF667EEA).withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          if (stepData.isGoalReached)
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.2),
              blurRadius: 30,
              spreadRadius: 2,
            ),
        ],
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // Ambient glowing background gradients
            Positioned(
              top: -60,
              right: -60,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      (stepData.isGoalReached
                              ? AppColors.accent
                              : const Color(0xFF667EEA))
                          .withValues(alpha: isDark ? 0.18 : 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -40,
              left: -40,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(
                        0xFF764BA2,
                      ).withValues(alpha: isDark ? 0.15 : 0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(22.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header Row
                  _buildHeader(context, isDark, stepData),

                  const SizedBox(height: 20),

                  // Permission / Sensor Warning Banner if needed
                  if (!stepData.hasPermission)
                    _buildPermissionBanner(context, isDark)
                  else if (!stepData.isSensorAvailable &&
                      stepData.errorMessage != null)
                    _buildSensorWarning(isDark, stepData.errorMessage!),

                  // Main Circular Visualizer & Status
                  _buildProgressVisualizer(isDark, stepData),

                  const SizedBox(height: 24),

                  // 3 Metric Pills (Calories, Distance, Active Time)
                  _buildMetricPills(isDark, stepData),

                  const SizedBox(height: 24),

                  // Mini 7-Day Activity Bar Chart
                  _buildWeeklyActivity(isDark, stepData),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Üst Başlık ve Hedef Ayarlama Butonu
  Widget _buildHeader(BuildContext context, bool isDark, StepData data) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF667EEA).withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.directions_walk_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.ln('daily_steps').toUpperCase(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: isDark ? Colors.white : AppColors.lightText,
                  ),
                ),
                const SizedBox(height: 2),
                _buildLiveStatusBadge(isDark, data),
              ],
            ),
          ],
        ),

        // Settings / Target Goal Button
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showGoalDialog(context, data.stepGoal),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 15,
                    color: isDark ? Colors.white70 : AppColors.lightText,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatNumber(data.stepGoal),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white70 : AppColors.lightText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Canlı Yürüyüş / Durum Rozeti
  Widget _buildLiveStatusBadge(bool isDark, StepData data) {
    final isWalking = data.status == StepStatus.walking;
    final color = isWalking
        ? AppColors.accent
        : (isDark ? AppColors.darkHint : AppColors.lightHint);

    return Row(
      children: [
        if (isWalking)
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.6),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.6),
            ),
          ),
        const SizedBox(width: 6),
        Text(
          data.statusText,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isWalking
                ? color
                : (isDark ? AppColors.darkHint : AppColors.lightHint),
          ),
        ),
      ],
    );
  }

  /// İzin Bildirim Kartı
  Widget _buildPermissionBanner(BuildContext context, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: isDark ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.warning,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.ln('movement_permit_required'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.ln('you_must_grant_sensor_access_to_count_steps'),
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () =>
                ref.read(stepTrackerProvider.notifier).retryPermission(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              context.ln('allow'),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  /// Sensör Uyarısı
  Widget _buildSensorWarning(bool isDark, String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: isDark ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.info,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Dairesel İlerleme ve Adım Göstergesi
  Widget _buildProgressVisualizer(bool isDark, StepData data) {
    final progress = data.progress;
    final isReached = data.isGoalReached;

    return Center(
      child: SizedBox(
        width: 220,
        height: 220,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Custom radial animated arc
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: progress),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (context, animatedProgress, child) {
                return CustomPaint(
                  size: const Size(220, 220),
                  painter: _StepProgressPainter(
                    progress: animatedProgress,
                    isDark: isDark,
                    isGoalReached: isReached,
                  ),
                );
              },
            ),

            // Inner Content
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Goal Reached or Target Percentage Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isReached
                        ? AppColors.accent.withValues(alpha: 0.2)
                        : (isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : const Color(0xFF667EEA).withValues(alpha: 0.1)),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isReached
                          ? AppColors.accent
                          : const Color(0xFF667EEA).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isReached
                            ? Icons.check_circle_rounded
                            : Icons.local_fire_department_rounded,
                        size: 13,
                        color: isReached
                            ? AppColors.accent
                            : const Color(0xFF667EEA),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isReached
                            ? context.ln('target_ok').toUpperCase()
                            : '%${data.progressPercentage}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: isReached
                              ? AppColors.accent
                              : (isDark
                                    ? Colors.white
                                    : const Color(0xFF667EEA)),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 6),

                // Large Step Count
                TweenAnimationBuilder<int>(
                  tween: IntTween(begin: 0, end: data.todaySteps),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutQuad,
                  builder: (context, animatedSteps, child) {
                    return Text(
                      _formatNumber(animatedSteps),
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: isDark ? Colors.white : AppColors.lightText,
                      ),
                    );
                  },
                ),

                // Target Subtitle
                Text(
                  '/${_formatNumber(data.stepGoal)} ${context.ln('step')}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkHint : AppColors.lightHint,
                  ),
                ),

                if (!isReached) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${_formatNumber(data.remainingSteps)} ${context.ln('step_remained').toLowerCase()}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: (isDark ? AppColors.darkHint : AppColors.lightHint)
                          .withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 3 İstatistik Hapı (Kalori, Mesafe, Aktif Süre)
  Widget _buildMetricPills(bool isDark, StepData data) {
    return Row(
      children: [
        Expanded(
          child: _buildMetricItem(
            isDark: isDark,
            icon: Icons.local_fire_department_rounded,
            iconColor: const Color(0xFFFF5252),
            gradientColors: [const Color(0xFFFF5252), const Color(0xFFFF7A00)],
            value: _formatNumber(data.caloriesBurned),
            unit: 'kcal',
            label: context.ln('calorie'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMetricItem(
            isDark: isDark,
            icon: Icons.route_rounded,
            iconColor: const Color(0xFF38EF7D),
            gradientColors: [const Color(0xFF11998E), const Color(0xFF38EF7D)],
            value: data.distanceKm.toStringAsFixed(2),
            unit: 'km',
            label: context.ln('distance'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMetricItem(
            isDark: isDark,
            icon: Icons.timer_outlined,
            iconColor: const Color(0xFF00D2FF),
            gradientColors: [const Color(0xFF0052D4), const Color(0xFF4364F7)],
            value: '${data.activeMinutes}',
            unit: context.ln('minute_short'),
            label: context.ln('active_duration'),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricItem({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required List<Color> gradientColors,
    required String value,
    required String unit,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors
                    .map((c) => c.withValues(alpha: 0.2))
                    .toList(),
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppColors.lightText,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.darkHint : AppColors.lightHint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkHint : AppColors.lightHint,
            ),
          ),
        ],
      ),
    );
  }

  /// 7 Günlük Aktivite Mini Bar Grafiği
  Widget _buildWeeklyActivity(bool isDark, StepData data) {
    if (data.weeklySteps.isEmpty) return const SizedBox.shrink();

    final maxVal = data.weeklySteps.values.fold<int>(
      data.stepGoal,
      (max, e) => e > max ? e : max,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.ln('weekly_activity').toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: isDark ? AppColors.darkHint : AppColors.lightHint,
                ),
              ),
              Text(
                context.ln('7_day_trend'),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.darkHint : AppColors.lightHint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: data.weeklySteps.entries.map((entry) {
              final isToday = entry.key == data.weeklySteps.keys.last;
              final steps = entry.value;
              final heightRatio = maxVal > 0
                  ? (steps / maxVal).clamp(0.08, 1.0)
                  : 0.08;
              final reachedGoal = steps >= data.stepGoal;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    steps > 0 ? '${(steps / 1000).toStringAsFixed(1)}k' : '0',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                      color: isToday
                          ? (isDark ? Colors.white : AppColors.lightText)
                          : (isDark ? AppColors.darkHint : AppColors.lightHint),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 16,
                    height: 54 * heightRatio,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: isToday
                            ? (reachedGoal
                                  ? [AppColors.accent, const Color(0xFF38EF7D)]
                                  : [
                                      const Color(0xFF667EEA),
                                      const Color(0xFF764BA2),
                                    ])
                            : (reachedGoal
                                  ? [
                                      AppColors.accent.withValues(alpha: 0.5),
                                      AppColors.accent.withValues(alpha: 0.8),
                                    ]
                                  : [
                                      (isDark ? Colors.white : Colors.black)
                                          .withValues(alpha: 0.08),
                                      (isDark ? Colors.white : Colors.black)
                                          .withValues(alpha: 0.2),
                                    ]),
                      ),
                      boxShadow: isToday
                          ? [
                              BoxShadow(
                                color: const Color(
                                  0xFF667EEA,
                                ).withValues(alpha: 0.4),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    entry.key,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isToday ? FontWeight.w900 : FontWeight.w600,
                      color: isToday
                          ? const Color(0xFF667EEA)
                          : (isDark ? AppColors.darkHint : AppColors.lightHint),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// Hedef Belirleme Dialogu
  void _showGoalDialog(BuildContext context, int currentGoal) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    int selected = currentGoal;
    final presetGoals = [5000, 8000, 10000, 12000, 15000];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              backgroundColor: isDark ? const Color(0xFF2D2D2D) : Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.track_changes_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.ln('daily_goal').toUpperCase(),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: isDark ? Colors.white : AppColors.lightText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${context.ln('select_the_number_of_steps_you_want_to_complete_daily')}:',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.darkHint
                            : AppColors.lightHint,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Preset Goal Chips
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: presetGoals.map((g) {
                        final isSelected = selected == g;
                        return InkWell(
                          onTap: () {
                            setModalState(() => selected = g);
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF667EEA)
                                  : (isDark
                                        ? Colors.white.withValues(alpha: 0.06)
                                        : Colors.black.withValues(alpha: 0.05)),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF667EEA)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              _formatNumber(g),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: isSelected
                                    ? Colors.white
                                    : (isDark
                                          ? Colors.white70
                                          : AppColors.lightText),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(
                              context.ln('give_up'),
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.darkHint
                                    : AppColors.lightHint,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () {
                              ref
                                  .read(stepTrackerProvider.notifier)
                                  .setGoal(selected);
                              Navigator.pop(ctx);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF667EEA),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 4,
                            ),
                            child: Text(
                              context.ln('save'),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatNumber(int number) {
    return number.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }
}

/// Dairesel İlerleme Çizici
class _StepProgressPainter extends CustomPainter {
  final double progress;
  final bool isDark;
  final bool isGoalReached;

  _StepProgressPainter({
    required this.progress,
    required this.isDark,
    required this.isGoalReached,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 24) / 2;
    const strokeWidth = 14.0;

    // Background track arc (from 135 deg to 45 deg, 270 deg total)
    const startAngle = 135 * (math.pi / 180);
    const sweepAngle = 270 * (math.pi / 180);

    final trackPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    // Active progress arc
    if (progress > 0) {
      final activeSweep = sweepAngle * progress;

      final gradientColors = isGoalReached
          ? [const Color(0xFF2ECC71), const Color(0xFF38EF7D)]
          : [
              const Color(0xFF667EEA),
              const Color(0xFF764BA2),
              const Color(0xFFFF6B6B),
            ];

      final rect = Rect.fromCircle(center: center, radius: radius);
      final gradient = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
        colors: gradientColors,
        transform: GradientRotation(startAngle),
      );

      final progressPaint = Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(rect, startAngle, activeSweep, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _StepProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isDark != isDark ||
        oldDelegate.isGoalReached != isGoalReached;
  }
}
