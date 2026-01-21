// screens/daily_questions_screen.dart - PREMIUM INDUSTRY LEVEL VERSION
import 'package:flutter/material.dart';
import '../services/daily_questions_service.dart';
import '../services/user_profile_service.dart';

class DailyQuestionsScreen extends StatefulWidget {
  final VoidCallback onCompleted;

  const DailyQuestionsScreen({super.key, required this.onCompleted});

  @override
  State<DailyQuestionsScreen> createState() => _DailyQuestionsScreenState();
}

class _DailyQuestionsScreenState extends State<DailyQuestionsScreen>
    with SingleTickerProviderStateMixin {
  final DailyQuestionsService _questionsService = DailyQuestionsService();
  final UserProfileService _userProfileService = UserProfileService();

  final TextEditingController _bedtimeController = TextEditingController();
  final TextEditingController _wakeTimeController = TextEditingController();

  bool? _napped;
  bool? _feltRested;
  bool? _usedSleepAid;
  bool? _usualEnvironment;
  bool? _consumedSubstances;
  bool? _screenTimeBeforeBed;
  bool? _feltStressed;
  int _activityIntensity = 50; // Default to moderate activity

  // Animation
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;

  // Smart sleep time tracking
  bool _isFirstThreeDays = true;
  bool _usedUsualTimes = true;
  String? _usualBedtime;
  String? _usualWakeTime;
  int _submissionCount = 0;

  // Premium color palette
  static const _background = Color(0xFF000000);
  static const _surface = Color(0xFF111111);
  static const _surfaceElevated = Color(0xFF1A1A1A);
  static const _primary = Color(0xFF007AFF);
  static const _primaryLight = Color(0xFF4DA3FF);
  static const _textPrimary = Color(0xFFFFFFFF);
  static const _textSecondary = Color(0xFF8E8E93);
  static const _textTertiary = Color(0xFF48484A);
  static const _accentGreen = Color(0xFF32D74B);
  static const _accentOrange = Color(0xFFFF9F0A);
  static const _separator = Color(0xFF38383A);

  // Slider gesture tracking
  double _dragStartX = 0;
  double _dragStartValue = 0;
  double _usableWidth = 0;

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    _slideAnimation = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    _initializeSleepTimeLogic();
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initializeSleepTimeLogic() async {
    _submissionCount = await _questionsService.getSubmissionCount();

    final profile = await _userProfileService.getUserProfile();
    _usualBedtime = profile?.usualBedtime;
    _usualWakeTime = profile?.usualWakeTime;

    setState(() {
      _isFirstThreeDays = _submissionCount < 3;

      if (!_isFirstThreeDays &&
          _usualBedtime != null &&
          _usualWakeTime != null) {
        _bedtimeController.text = _usualBedtime!;
        _wakeTimeController.text = _usualWakeTime!;
      }
    });
  }

  // Premium gradient border card with enhanced visual hierarchy
  Widget _buildPremiumCard({
    required Widget child,
    double borderRadius = 20,
    EdgeInsets padding = const EdgeInsets.all(24),
    bool hasGradientBorder = true,
    Color backgroundColor = const Color(0xFF111111),
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: hasGradientBorder
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _textTertiary.withOpacity(0.3),
                  _separator.withOpacity(0.1),
                  _textTertiary.withOpacity(0.1),
                ],
              )
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius - 1.5),
            color: backgroundColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius - 1.5),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }

  // Premium time selection with enhanced visual feedback
  Future<void> _selectTime(TextEditingController controller) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: _primary,
              surface: _surfaceElevated,
              onSurface: _textPrimary,
            ),
            dialogBackgroundColor: _surface,
            timePickerTheme: TimePickerThemeData(
              backgroundColor: _surface,
              hourMinuteTextColor: _textPrimary,
              hourMinuteColor: _surfaceElevated,
              dayPeriodTextColor: _textPrimary,
              dayPeriodColor: _surfaceElevated,
              dialBackgroundColor: _surfaceElevated,
              dialHandColor: _primary,
              dialTextColor: _textPrimary,
              entryModeIconColor: _textSecondary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final formattedTime =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() {
        controller.text = formattedTime;
        if (!_isFirstThreeDays) {
          _usedUsualTimes = false;
        }
      });
    }
  }

  // Enhanced smart sleep time question with premium layout
  Widget _buildSmartSleepTimeQuestion() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: _isFirstThreeDays
                ? _buildFirstThreeDaysContent()
                : _buildRegularContent(),
          ),
        );
      },
    );
  }

  Widget _buildFirstThreeDaysContent() {
    return Column(
      children: [
        _buildTimeQuestion(
          'What time did you go to bed?',
          _bedtimeController,
          Icons.nightlight_round_rounded,
        ),
        const SizedBox(height: 24), // Increased spacing
        _buildTimeQuestion(
          'What time did you wake up?',
          _wakeTimeController,
          Icons.wb_sunny_rounded,
        ),
        const SizedBox(height: 20),
        _buildPremiumCard(
          padding: const EdgeInsets.all(20),
          backgroundColor: _primary.withOpacity(0.08),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _primary.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.insights_rounded, color: _primary, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Learning your sleep pattern',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Day ${_submissionCount + 1} of 3 • We\'re establishing your baseline',
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRegularContent() {
    return Column(
      children: [
        _buildPremiumCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _usedUsualTimes
                          ? _accentGreen.withOpacity(0.2)
                          : _accentOrange.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _usedUsualTimes
                          ? Icons.check_circle_rounded
                          : Icons.schedule_rounded,
                      color: _usedUsualTimes ? _accentGreen : _accentOrange,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Sleep Schedule',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Sleep times display
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _separator.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    _buildTimeDisplayRow(
                      'Bedtime',
                      _bedtimeController.text,
                      Icons.nightlight_round_rounded,
                      _primaryLight,
                    ),
                    const SizedBox(height: 16),
                    _buildTimeDisplayRow(
                      'Wake Time',
                      _wakeTimeController.text,
                      Icons.wb_sunny_rounded,
                      _accentOrange,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Follow schedule question
              Text(
                'Did you follow your usual schedule?',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: _buildScheduleOption(
                      'Yes, Same Times',
                      _usedUsualTimes,
                      Icons.check_circle_rounded,
                      onTap: () {
                        setState(() {
                          _usedUsualTimes = true;
                          _bedtimeController.text = _usualBedtime!;
                          _wakeTimeController.text = _usualWakeTime!;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildScheduleOption(
                      'Edit Times',
                      !_usedUsualTimes,
                      Icons.edit_rounded,
                      onTap: () {
                        setState(() {
                          _usedUsualTimes = false;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        if (!_usedUsualTimes) ...[
          const SizedBox(height: 24),
          _buildTimeQuestion(
            'What time did you go to bed?',
            _bedtimeController,
            Icons.nightlight_round_rounded,
          ),
          const SizedBox(height: 24),
          _buildTimeQuestion(
            'What time did you wake up?',
            _wakeTimeController,
            Icons.wb_sunny_rounded,
          ),
        ],
      ],
    );
  }

  Widget _buildTimeDisplayRow(
    String label,
    String time,
    IconData icon,
    Color color,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: _textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        Text(
          time,
          style: TextStyle(
            color: _textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleOption(
    String text,
    bool isSelected,
    IconData icon, {
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isSelected ? _primary.withOpacity(0.15) : _surfaceElevated,
            border: Border.all(
              color: isSelected ? _primary : _separator,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? _primary : _textSecondary,
                size: 20,
              ),
              const SizedBox(height: 8),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? _primary : _textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeQuestion(
    String question,
    TextEditingController controller,
    IconData icon,
  ) {
    return _buildPremiumCard(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _selectTime(controller),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_surfaceElevated, _surface],
                    ),
                  ),
                  child: Icon(icon, color: _primary, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        question,
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (controller.text.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          controller.text,
                          style: TextStyle(
                            color: _primary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _surfaceElevated,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.access_time_rounded,
                    color: _textSecondary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Premium activity slider with fixed layout and proper calculations
  Widget _buildActivityIntensitySlider() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: _buildPremiumCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _accentGreen.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.fitness_center_rounded,
                          color: _accentGreen,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Activity Intensity',
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Premium display area
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _surfaceElevated,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _separator.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '$_activityIntensity',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                color: _getActivityIntensityColor(
                                  _activityIntensity,
                                ),
                              ),
                            ),
                            Text(
                              '%',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w500,
                                color: _textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getActivityIntensityLevel(_activityIntensity),
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getActivityIntensityDescription(_activityIntensity),
                          style: TextStyle(color: _textTertiary, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Fixed slider with proper calculations and gesture tracking
                  Container(
                    height: 80,
                    decoration: BoxDecoration(
                      color: _surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _separator.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final trackWidth = constraints.maxWidth - 48;
                        final thumbSize = 48.0;
                        _usableWidth = trackWidth - thumbSize;

                        final thumbX =
                            24 + _usableWidth * (_activityIntensity / 100);
                        final progressWidth = thumbX - 24 + thumbSize / 2;

                        return Stack(
                          children: [
                            // Background track
                            Positioned(
                              left: 24,
                              right: 24,
                              top: 36,
                              child: Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  color: _separator.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),

                            // Progress bar
                            Positioned(
                              left: 24,
                              top: 36,
                              child: Container(
                                width: progressWidth.clamp(0, trackWidth),
                                height: 6,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(3),
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color.fromARGB(255, 27, 125, 195),
                                      const Color.fromARGB(255, 27, 125, 195),
                                      const Color.fromARGB(255, 27, 125, 195),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Thumb with fixed gesture tracking
                            Positioned(
                              left: thumbX,
                              top: 16,
                              child: GestureDetector(
                                onPanStart: (details) {
                                  _dragStartX = details.globalPosition.dx;
                                  _dragStartValue = _activityIntensity
                                      .toDouble();
                                },
                                onPanUpdate: (details) {
                                  final delta =
                                      details.globalPosition.dx - _dragStartX;
                                  final percentDelta =
                                      (delta / _usableWidth) * 100;
                                  final newValue =
                                      (_dragStartValue + percentDelta).clamp(
                                        0,
                                        100,
                                      );

                                  setState(() {
                                    _activityIntensity = newValue.round();
                                  });
                                },
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.grab,
                                  child: Container(
                                    width: thumbSize,
                                    height: thumbSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _surfaceElevated,
                                      border: Border.all(
                                        color: _getActivityIntensityColor(
                                          _activityIntensity,
                                        ),
                                        width: 3,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.4),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                        BoxShadow(
                                          color: _getActivityIntensityColor(
                                            _activityIntensity,
                                          ).withOpacity(0.2),
                                          blurRadius: 16,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.drag_indicator_rounded,
                                      color: _getActivityIntensityColor(
                                        _activityIntensity,
                                      ),
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Intensity markers
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildIntensityMarker(0, 'Light'),
                        _buildIntensityMarker(25, ''),
                        _buildIntensityMarker(50, 'Moderate'),
                        _buildIntensityMarker(75, ''),
                        _buildIntensityMarker(100, 'Vigorous'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildIntensityMarker(int value, String label) {
    return Column(
      children: [
        Container(
          width: 2,
          height: 6,
          decoration: BoxDecoration(
            color: _textTertiary,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: _textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  // Helper methods for activity intensity
  Color _getActivityIntensityColor(int intensity) {
    if (intensity <= 25)
      return const Color.fromARGB(255, 27, 125, 195); // Green
    if (intensity <= 50)
      return const Color.fromARGB(255, 27, 125, 195); // Orange
    if (intensity <= 75)
      return const Color.fromARGB(255, 27, 125, 195); // Deep orange
    return const Color.fromARGB(255, 27, 125, 195); // Red
  }

  String _getActivityIntensityLevel(int intensity) {
    if (intensity <= 25) return 'Light Activity';
    if (intensity <= 50) return 'Moderate Activity';
    if (intensity <= 75) return 'High Activity';
    return 'Very High Activity';
  }

  String _getActivityIntensityDescription(int intensity) {
    if (intensity <= 25) return 'Light walking, stretching, daily chores';
    if (intensity <= 50) return 'Brisk walking, light cycling, gardening';
    if (intensity <= 75) return 'Running, swimming, intense workouts';
    return 'Competitive sports, heavy lifting, HIIT training';
  }

  // Premium yes/no question with enhanced interaction
  Widget _buildYesNoQuestion(
    String question,
    bool? value,
    Function(bool?) onChanged,
  ) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: _buildPremiumCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    question,
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _buildAnswerOption(
                          'Yes',
                          value == true,
                          Icons.check_rounded,
                          _accentGreen,
                          () => onChanged(true),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildAnswerOption(
                          'No',
                          value == false,
                          Icons.close_rounded,
                          Color(0xFFFF453A),
                          () => onChanged(false),
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
  }

  Widget _buildAnswerOption(
    String text,
    bool isSelected,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isSelected ? color.withOpacity(0.15) : _surfaceElevated,
            border: Border.all(
              color: isSelected ? color : _separator,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? color : _textSecondary, size: 24),
              const SizedBox(height: 12),
              Text(
                text,
                style: TextStyle(
                  color: isSelected ? color : _textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitQuestions() async {
    if (_bedtimeController.text.isEmpty || _wakeTimeController.text.isEmpty) {
      _showError('Please fill in bedtime and wake time');
      return;
    }

    final timeRegex = RegExp(r'^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$');
    if (!timeRegex.hasMatch(_bedtimeController.text) ||
        !timeRegex.hasMatch(_wakeTimeController.text)) {
      _showError('Invalid time format');
      return;
    }

    final questions = DailyQuestions(
      date: DateTime.now(),
      bedtime: _bedtimeController.text,
      wakeTime: _wakeTimeController.text,
      usedUsualTimes: _usedUsualTimes,
      napped: _napped,
      feltRested: _feltRested,
      usedSleepAid: _usedSleepAid,
      usualEnvironment: _usualEnvironment,
      consumedSubstances: _consumedSubstances,
      screenTimeBeforeBed: _screenTimeBeforeBed,
      feltStressed: _feltStressed,
      activityIntensity: _activityIntensity, // NEW
    );

    await _questionsService.saveQuestions(questions);

    if (_submissionCount == 2) {
      final avgTimes = await _questionsService.calculateAverageSleepTimes();
      if (avgTimes != null) {
        await _userProfileService.updateSleepTimes(
          avgTimes['bedtime']!,
          avgTimes['wakeTime']!,
        );
      }
    }

    widget.onCompleted();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: _textPrimary)),
        backgroundColor: _surfaceElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 8,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Premium header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      color: _textSecondary,
                      onPressed: widget.onCompleted,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Daily Sleep Check-in',
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize:
                                (MediaQuery.of(context).size.width * 0.065)
                                    .clamp(24.0, 26.0),
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isFirstThreeDays
                              ? 'Day ${_submissionCount + 1} of 3 • Establishing your baseline'
                              : 'Quick daily check-in',
                          style: TextStyle(
                            color: _textSecondary,
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Main content with enhanced breathing space
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      _buildSmartSleepTimeQuestion(),
                      const SizedBox(height: 32),

                      // Questions with staggered animation
                      ..._buildQuestionsList().asMap().entries.map((entry) {
                        final index = entry.key;
                        final widget = entry.value;
                        return Padding(
                          padding: EdgeInsets.only(bottom: 24),
                          child: AnimatedBuilder(
                            animation: _animationController,
                            builder: (context, child) {
                              return Transform.translate(
                                offset: Offset(
                                  0,
                                  _slideAnimation.value * (1 - index * 0.1),
                                ),
                                child: Opacity(
                                  opacity:
                                      _fadeAnimation.value * (1 - index * 0.1),
                                  child: child,
                                ),
                              );
                            },
                            child: widget,
                          ),
                        );
                      }).toList(),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),

              // Premium submit button
              _buildPremiumCard(
                padding: const EdgeInsets.all(0),
                hasGradientBorder: false,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _submitQuestions,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [_primary, _primaryLight],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _primary.withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_rounded,
                            color: _textPrimary,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Submit Answers',
                            style: TextStyle(
                              color: _textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildQuestionsList() {
    return [
      _buildActivityIntensitySlider(), // Fixed slider with proper gesture tracking
      _buildYesNoQuestion(
        'Did you nap today?',
        _napped,
        (value) => setState(() => _napped = value),
      ),
      _buildYesNoQuestion(
        'Did you feel rested when you woke up?',
        _feltRested,
        (value) => setState(() => _feltRested = value),
      ),
      _buildYesNoQuestion(
        'Did you use a sleep aid?',
        _usedSleepAid,
        (value) => setState(() => _usedSleepAid = value),
      ),
      _buildYesNoQuestion(
        'Did you sleep in your usual environment?',
        _usualEnvironment,
        (value) => setState(() => _usualEnvironment = value),
      ),
      _buildYesNoQuestion(
        'Did you consume caffeine or alcohol before bed?',
        _consumedSubstances,
        (value) => setState(() => _consumedSubstances = value),
      ),
      _buildYesNoQuestion(
        'Did you look at screens before sleeping?',
        _screenTimeBeforeBed,
        (value) => setState(() => _screenTimeBeforeBed = value),
      ),
      _buildYesNoQuestion(
        'Did you feel stressed before bed?',
        _feltStressed,
        (value) => setState(() => _feltStressed = value),
      ),
    ];
  }
}
