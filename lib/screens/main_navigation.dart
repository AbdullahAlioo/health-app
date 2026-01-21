import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../services/background_ble_service.dart'; // Import the background BLE service
import 'dashboard_screen.dart';
import 'analysis_screen.dart';
import 'ai_chat_screen.dart';
import 'target_screen.dart';
import 'package:zyora_final/screens/biohacking_screen.dart';

class MainNavigation extends StatefulWidget {
  final BLEService bleService;
  final BackgroundBLEService backgroundBleService; // Add this line

  const MainNavigation({
    super.key,
    required this.bleService,
    required this.backgroundBleService, // Add this line
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  final PageController _pageController = PageController();

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      DashboardScreen(
        bleService: widget.bleService,
        backgroundBleService:
            widget.backgroundBleService, // Pass the background service
      ),
      AnalysisScreen(bleService: widget.bleService),
      AIChatScreen(bleService: widget.bleService),
      TargetScreen(bleService: widget.bleService),
      BiohackingScreen(bleService: widget.bleService),
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const BouncingScrollPhysics(),
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        children: _screens,
      ),
      bottomNavigationBar: _buildPremiumNavBar(),
    );
  }

  // Classic Premium Navigation Bar
  Widget _buildPremiumNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        border: Border(
          top: BorderSide(color: const Color(0xFF1A1A1A), width: 1),
        ),
      ),
      child: SafeArea(
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildNavItem(Icons.space_dashboard_rounded, 'Home', 0),
              _buildNavItem(Icons.insights_rounded, 'Stats', 1),
              _buildNavItem(Icons.auto_awesome_rounded, 'AI', 2),
              _buildNavItem(Icons.track_changes_rounded, 'Goals', 3),
              _buildNavItem(Icons.monitor_heart_rounded, 'Vitality', 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isActive = _currentIndex == index;
    final color = isActive ? _getActiveColor(index) : const Color(0xFF666666);

    return Expanded(
      child: GestureDetector(
        onTap: () {
          // Instant navigation without page animation
          _pageController.jumpToPage(index);
          setState(() {
            _currentIndex = index;
          });
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated Icon Container
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: isActive
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            color.withOpacity(0.15),
                            color.withOpacity(0.05),
                          ],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(12),
                  border: isActive
                      ? Border.all(color: color.withOpacity(0.3), width: 1)
                      : null,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 4),

              // Label with smooth animation
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                  height: 1.2,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getActiveColor(int index) {
    switch (index) {
      case 0: // Home/Dashboard
        return const Color(0xFF4A7BDB); // Premium Blue
      case 1: // Stats/Analysis
        return const Color(0xFF00BCD4); // Cyan
      case 2: // AI
        return const Color(0xFF9C27B0); // Purple
      case 3: // Goals/Target
        return const Color(0xFFFF9800); // Orange
      case 4: // Vitality Matrix
        return const Color(0xFF4CAF50); // Green
      default:
        return const Color(0xFF4A7BDB);
    }
  }
}
