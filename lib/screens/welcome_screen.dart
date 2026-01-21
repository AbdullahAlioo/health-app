// welcome_page.dart - COMPLETE PROFESSIONAL VERSION WITH ENHANCED CONNECTION LOGIC
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:zyora_final/services/ble_service.dart';
import 'package:zyora_final/services/user_profile_service.dart';

class WelcomeScreen extends StatefulWidget {
  final BLEService bleService;
  final VoidCallback onComplete;

  const WelcomeScreen({
    super.key,
    required this.bleService,
    required this.onComplete,
  });

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  bool _isConnecting = false;
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _bedtimeController = TextEditingController();
  final TextEditingController _wakeTimeController = TextEditingController();

  final UserProfileService _userProfileService = UserProfileService();
  int _currentStep = 0;
  bool _showWelcome = true;

  // PROFESSIONAL COLOR PALETTE
  static const _background = Color(0xFF000000);
  static const _surface = Color(0xFF111111);
  static const _primary = Color(0xFF007AFF);
  static const _primaryDark = Color(0xFF0056CC);
  static const _textPrimary = Color(0xFFFFFFFF);
  static const _textSecondary = Color(0xFF8E8E93);
  static const _textTertiary = Color(0xFF48484A);
  static const _separator = Color(0xFF38383A);
  static const _errorColor = Color(0xFFFF3B30);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();
    _checkFirstTimeUser();

    // Listen for connection state changes
    widget.bleService.connectionStream.listen((isConnected) {
      if (isConnected && _currentStep == 2) {
        // Device connected, navigate to dashboard
        widget.onComplete();
      }
    });
  }

  Future<void> _checkFirstTimeUser() async {
    final profile = await _userProfileService.getUserProfile();
    if (profile != null && profile.age != null) {
      setState(() {
        _showWelcome = false;
        _currentStep = 2;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _ageController.dispose();
    _bedtimeController.dispose();
    _wakeTimeController.dispose();
    super.dispose();
  }

  // STEP 1: WELCOME SCREEN - Improved with better content distribution
  Widget _buildWelcomeScreen() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: double.infinity,
              height: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  // Top spacing - balanced
                  const SizedBox(height: 80),

                  // Logo Section
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: _primary,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.health_and_safety,
                      color: _textPrimary,
                      size: 48,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Main Content - Properly centered
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Title
                        Text(
                          'Welcome to Zyora',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: _textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Subtitle with benefits
                        Column(
                          children: [
                            _buildBenefitRow(
                              'Real-time health monitoring',
                              Icons.monitor_heart_rounded,
                            ),
                            const SizedBox(height: 16),
                            _buildBenefitRow(
                              'Personalized sleep analysis',
                              Icons.nightlight_round_rounded,
                            ),
                            const SizedBox(height: 16),
                            _buildBenefitRow(
                              'Smart activity tracking',
                              Icons.fitness_center_rounded,
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),

                        // Description
                        Text(
                          'Join thousands of users who have transformed their health journey with personalized insights and continuous monitoring.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: _textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bottom Section
                  Column(
                    children: [
                      // Get Started Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _currentStep = 1;
                              _controller.reset();
                              _controller.forward();
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            foregroundColor: _textPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Get Started',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Step indicator
                      _buildStepIndicator(),

                      const SizedBox(height: 32),
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

  Widget _buildBenefitRow(String text, IconData icon) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: _primary, size: 20),
        const SizedBox(width: 12),
        Text(
          text,
          style: TextStyle(
            color: _textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  // STEP 2: PROFILE SCREEN - Already perfect
  Widget _buildProfileScreen() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: double.infinity,
              height: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 60),

                  // Header
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _currentStep = 0;
                          _controller.reset();
                          _controller.forward();
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: _textPrimary,
                          size: 20,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Title
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Your Profile',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Subtitle
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Help us personalize your experience',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w400,
                        color: _textSecondary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Form
                  Container(
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        // Age Input
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: _separator, width: 0.5),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.cake_rounded,
                                color: _textTertiary,
                                size: 20,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextField(
                                  controller: _ageController,
                                  keyboardType: TextInputType.number,
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    hintText: 'Age',
                                    hintStyle: TextStyle(
                                      color: _textTertiary,
                                      fontSize: 17,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Bedtime Input
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: _separator, width: 0.5),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.nightlight_round_rounded,
                                color: _textTertiary,
                                size: 20,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () =>
                                      _selectTime(context, _bedtimeController),
                                  child: Text(
                                    _bedtimeController.text.isEmpty
                                        ? 'Bedtime'
                                        : _bedtimeController.text,
                                    style: TextStyle(
                                      color: _bedtimeController.text.isEmpty
                                          ? _textTertiary
                                          : _textPrimary,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Wake Time Input
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.wb_sunny_rounded,
                                color: _textTertiary,
                                size: 20,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () =>
                                      _selectTime(context, _wakeTimeController),
                                  child: Text(
                                    _wakeTimeController.text.isEmpty
                                        ? 'Wake Time'
                                        : _wakeTimeController.text,
                                    style: TextStyle(
                                      color: _wakeTimeController.text.isEmpty
                                          ? _textTertiary
                                          : _textPrimary,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Help Text
                  Text(
                    'This helps us provide personalized health insights and sleep analysis.',
                    style: TextStyle(
                      color: _textTertiary,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),

                  const Spacer(),

                  // Continue Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveProfileAndContinue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: _textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // STEP 3: CONNECT SCREEN - WITH ENHANCED CONNECTION LOGIC
  Widget _buildConnectScreen() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: double.infinity,
              height: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  // FIXED: Smaller top spacing and compact back button
                  const SizedBox(height: 20),

                  // FIXED: Compact back button that doesn't push content down
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _currentStep = 1;
                          _controller.reset();
                          _controller.forward();
                        });
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(0, 17, 17, 17),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: _textPrimary,
                          size: 16,
                        ),
                      ),
                    ),
                  ),

                  // FIXED: Main content with proper constraints
                  Expanded(
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: MediaQuery.of(context).size.height * 0.6,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Icon
                            Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                color: _surface,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.watch_rounded,
                                color: _primary,
                                size: 50,
                              ),
                            ),

                            const SizedBox(height: 40),

                            // Title
                            Text(
                              'Connect Your Device',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: _textPrimary,
                                letterSpacing: -0.5,
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Description
                            Text(
                              'Pair your smartwatch to unlock comprehensive health monitoring and personalized insights.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w400,
                                color: _textSecondary,
                                height: 1.5,
                              ),
                            ),

                            const SizedBox(height: 40),

                            // ONLY 3 MAIN FEATURES - FIXED WITH BETTER LAYOUT
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                vertical: 20,
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: _surface,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                children: [
                                  _buildConnectFeatureRow(
                                    'Real-time Health Monitoring',
                                    Icons.monitor_heart_rounded,
                                  ),
                                  const SizedBox(height: 16),
                                  _buildConnectFeatureRow(
                                    'Sleep & Recovery Analysis',
                                    Icons.nightlight_round_rounded,
                                  ),
                                  const SizedBox(height: 16),
                                  _buildConnectFeatureRow(
                                    'Activity & Fitness Tracking',
                                    Icons.fitness_center_rounded,
                                  ),

                                  // "More" Button - COMPACT DESIGN
                                  const SizedBox(height: 12),
                                  Container(height: 1, color: _separator),
                                  const SizedBox(height: 8),
                                  _buildMoreButton(),
                                ],
                              ),
                            ),

                            // ADDED: Extra spacing to ensure content doesn't get hidden
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // FIXED: Bottom Section with proper spacing - NOW FIXED AT BOTTOM
                  SafeArea(
                    child: Column(
                      children: [
                        // Connect Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isConnecting
                                ? null
                                : () {
                                    _connectToDevice();
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primary,
                              foregroundColor: _textPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_isConnecting)
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(
                                        _textPrimary,
                                      ),
                                    ),
                                  )
                                else
                                  Icon(Icons.bluetooth_rounded, size: 20),
                                const SizedBox(width: 12),
                                Text(
                                  _isConnecting
                                      ? 'Searching...'
                                      : 'Connect Device',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Terms & Policies Section - COMPACT DESIGN
                        Column(
                          children: [
                            // Terms Text
                            Text(
                              'By connecting, you agree to our',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _textTertiary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),

                            // Terms & Policies Buttons
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildPolicyButton('Terms of Service', () {
                                  _showTermsAndPolicies('Terms of Service');
                                }),
                                const SizedBox(width: 12),
                                _buildPolicyButton('Privacy Policy', () {
                                  _showTermsAndPolicies('Privacy Policy');
                                }),
                              ],
                            ),
                          ],
                        ),
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

  // ENHANCED CONNECTION LOGIC
  Future<void> _connectToDevice() async {
    setState(() {
      _isConnecting = true;
    });

    try {
      // Step 1: Check Bluetooth Status
      final bluetoothState = await FlutterBluePlus.adapterState.first;
      if (bluetoothState != BluetoothAdapterState.on) {
        _showError('Bluetooth is turned off.');
        setState(() {
          _isConnecting = false;
        });
        return;
      }

      // Step 2: Check Existing Connection
      if (widget.bleService.isConnected) {
        print('Device already connected, navigating to dashboard...');
        widget.onComplete();
        return;
      }

      // Step 3: Search & Connect to Device
      final bool connectionSuccess = await widget.bleService.scanForDevices();

      if (connectionSuccess) {
        print('Device connected successfully!');
        // The connection stream listener will handle navigation
      } else {
        _showError('Device not found.');
      }
    } catch (e) {
      print('Connection error: $e');
      _showError('Connection failed. Please try again.');
    } finally {
      setState(() {
        _isConnecting = false;
      });
    }
  }

  // "More" Button that shows all features
  Widget _buildMoreButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _showAllFeatures,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'View All Features',
                style: TextStyle(
                  color: _primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward_rounded, color: _primary, size: 14),
            ],
          ),
        ),
      ),
    );
  }

  // Updated feature row for the 3 main features
  Widget _buildConnectFeatureRow(String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: _primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: _textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Terms & Policy Button
  Widget _buildPolicyButton(String text, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Text(
            text,
            style: TextStyle(
              color: _primary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: index == _currentStep
                ? _primary
                : _textTertiary.withOpacity(0.3),
          ),
        );
      }),
    );
  }

  // Modal that shows ALL your app features
  void _showAllFeatures() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                'All Zyora Features',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 8),

              Text(
                'Comprehensive health monitoring and insights',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: _textSecondary),
              ),
              const SizedBox(height: 32),

              // All Features Grid
              Column(
                children: [
                  // Row 1
                  Row(
                    children: [
                      Expanded(
                        child: _buildFeatureItem(
                          'Heart Rate Monitoring',
                          Icons.favorite_rounded,
                          Colors.red,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildFeatureItem(
                          'SpO₂ Tracking',
                          Icons.air_rounded,
                          Color(0xFF4A7AFF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Row 2
                  Row(
                    children: [
                      Expanded(
                        child: _buildFeatureItem(
                          'Sleep Analysis',
                          Icons.nightlight_round_rounded,
                          Colors.purple,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildFeatureItem(
                          'Activity Tracking',
                          Icons.directions_walk_rounded,
                          Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Row 3
                  Row(
                    children: [
                      Expanded(
                        child: _buildFeatureItem(
                          'Stress Monitoring',
                          Icons.psychology_rounded,
                          Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildFeatureItem(
                          'Recovery Scores',
                          Icons.health_and_safety_rounded,
                          Colors.teal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Row 4 - Biohacking Features
                  Row(
                    children: [
                      Expanded(
                        child: _buildFeatureItem(
                          'VO₂-max Analysis',
                          Icons.directions_run_rounded,
                          Color(0xFF2196F3),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildFeatureItem(
                          'HRV Insights',
                          Icons.insights_rounded,
                          Color(0xFF9C27B0),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Row 5 - Advanced Metrics
                  Row(
                    children: [
                      Expanded(
                        child: _buildFeatureItem(
                          'Body Temperature',
                          Icons.thermostat_rounded,
                          Color(0xFFFF5722),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildFeatureItem(
                          'Breathing Rate',
                          Icons.airline_seat_individual_suite_rounded,
                          Color(0xFF00BCD4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Row 6 - Health Scores
                  Row(
                    children: [
                      Expanded(
                        child: _buildFeatureItem(
                          'Health Scores',
                          Icons.auto_awesome_rounded,
                          Color(0xFF4CAF50),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildFeatureItem(
                          'Biohacking Metrics',
                          Icons.biotech_rounded,
                          Color(0xFFE91E63),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Close Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: _textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Got It'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // Individual feature item in the modal
  Widget _buildFeatureItem(String title, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _separator, width: 1),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // Terms & Policies Modal
  void _showTermsAndPolicies(String type) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                type,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 8),

              Text(
                'Last updated: ${DateTime.now().toString().split(' ')[0]}',
                style: TextStyle(color: _textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 24),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (type == 'Terms of Service') ..._buildTermsContent(),
                      if (type == 'Privacy Policy') ..._buildPrivacyContent(),

                      const SizedBox(height: 24),

                      // Permissions Section
                      _buildPermissionsSection(),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Close Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: _textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('I Understand'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildTermsContent() {
    return [
      Text(
        'Welcome to Zyora! These terms outline the rules and regulations for the use of our health monitoring application.',
        style: TextStyle(color: _textPrimary, fontSize: 15, height: 1.5),
      ),
      const SizedBox(height: 16),

      _buildSectionTitle('1. Acceptance of Terms'),
      Text(
        'By accessing and using Zyora, you accept and agree to be bound by the terms and provision of this agreement.',
        style: TextStyle(color: _textSecondary, fontSize: 14, height: 1.5),
      ),

      const SizedBox(height: 16),

      _buildSectionTitle('2. Health Data Collection'),
      Text(
        'Zyora collects health metrics including heart rate, sleep patterns, activity data, and other biometric information to provide personalized health insights.',
        style: TextStyle(color: _textSecondary, fontSize: 14, height: 1.5),
      ),

      const SizedBox(height: 16),

      _buildSectionTitle('3. User Responsibilities'),
      Text(
        'You are responsible for maintaining the confidentiality of your account and for all activities that occur under your account.',
        style: TextStyle(color: _textSecondary, fontSize: 14, height: 1.5),
      ),

      const SizedBox(height: 16),

      _buildSectionTitle('4. Medical Disclaimer'),
      Text(
        'Zyora is not a medical device and should not be used for medical diagnosis or treatment. Always consult healthcare professionals for medical advice.',
        style: TextStyle(color: _textSecondary, fontSize: 14, height: 1.5),
      ),
    ];
  }

  List<Widget> _buildPrivacyContent() {
    return [
      Text(
        'Your privacy is important to us. This privacy policy explains what personal data we collect and how we use it.',
        style: TextStyle(color: _textPrimary, fontSize: 15, height: 1.5),
      ),
      const SizedBox(height: 16),

      _buildSectionTitle('1. Information We Collect'),
      Text(
        'We collect health metrics, device information, and usage data to provide and improve our services.',
        style: TextStyle(color: _textSecondary, fontSize: 14, height: 1.5),
      ),

      const SizedBox(height: 16),

      _buildSectionTitle('2. How We Use Your Data'),
      Text(
        '• Provide personalized health insights and recommendations\n• Improve our algorithms and services\n• Ensure app functionality and performance',
        style: TextStyle(color: _textSecondary, fontSize: 14, height: 1.5),
      ),

      const SizedBox(height: 16),

      _buildSectionTitle('3. Data Security'),
      Text(
        'We implement appropriate security measures to protect your personal information against unauthorized access.',
        style: TextStyle(color: _textSecondary, fontSize: 14, height: 1.5),
      ),

      const SizedBox(height: 16),

      _buildSectionTitle('4. Data Sharing'),
      Text(
        'We do not sell your personal health data. We may share anonymized, aggregated data for research purposes.',
        style: TextStyle(color: _textSecondary, fontSize: 14, height: 1.5),
      ),
    ];
  }

  // Permissions Section (Common to both)
  Widget _buildPermissionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('App Permissions'),
        const SizedBox(height: 12),

        _buildPermissionItem(
          'Bluetooth Access',
          'Required to connect with your smartwatch and sync health data',
        ),
        _buildPermissionItem(
          'Health Data',
          'Collects heart rate, sleep, activity, and other biometric information',
        ),
        _buildPermissionItem(
          'Notifications',
          'Sends health insights and important updates',
        ),
        _buildPermissionItem(
          'Background Data',
          'Continuously monitors health metrics in the background',
        ),
        _buildPermissionItem(
          'Location (Optional)',
          'Used for activity tracking and workout routes',
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: _textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildPermissionItem(String permission, String description) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded, color: _primary, size: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  permission,
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectTime(
    BuildContext context,
    TextEditingController controller,
  ) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(primary: _primary, surface: _surface),
            dialogBackgroundColor: _background,
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final formattedTime =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      controller.text = formattedTime;
      setState(() {});
    }
  }

  Future<void> _saveProfileAndContinue() async {
    final age = int.tryParse(_ageController.text);
    if (age == null || age < 1 || age > 120) {
      _showError('Please enter a valid age');
      return;
    }

    if (_bedtimeController.text.isEmpty) _bedtimeController.text = '22:00';
    if (_wakeTimeController.text.isEmpty) _wakeTimeController.text = '07:00';

    await _userProfileService.saveUserProfile(
      UserProfile(
        age: age,
        usualBedtime: _bedtimeController.text,
        usualWakeTime: _wakeTimeController.text,
        createdAt: DateTime.now(),
      ),
    );

    setState(() {
      _currentStep = 2;
      _controller.reset();
      _controller.forward();
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _errorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_showWelcome) {
      return _buildConnectScreen();
    }

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: IndexedStack(
          index: _currentStep,
          children: [
            _buildWelcomeScreen(),
            _buildProfileScreen(),
            _buildConnectScreen(),
          ],
        ),
      ),
    );
  }
}
