import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:zyora_final/services/gemini_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ble_service.dart';

class AIChatScreen extends StatefulWidget {
  final BLEService bleService;

  const AIChatScreen({super.key, required this.bleService});

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;
  late GeminiService _geminiService;
  HealthData? _currentHealthData;
  StreamSubscription<HealthData>? _healthDataSubscription;

  @override
  void initState() {
    super.initState();
    _geminiService = GeminiService();

    // Get current health data FIRST, then welcome message
    _loadInitialHealthData();

    // Listen for health data updates
    _healthDataSubscription = widget.bleService.dataStream.listen((data) {
      print(
        'New health data received: HR:${data.heartRate}, Steps:${data.steps}',
      );
      if (mounted) {
        setState(() {
          _currentHealthData = data;
        });
      }
    });
  }

  void _loadInitialHealthData() async {
    try {
      // Try to get the latest health data
      final data = await widget.bleService.getLatestHealthData();
      if (data != null) {
        HealthData syncedData = data;

        // SYNC SMART METRICS FROM STORAGE
        try {
          final prefs = await SharedPreferences.getInstance();
          final todayStr = DateTime.now().toIso8601String().split('T')[0];
          final lastScoreDate = prefs.getString('last_score_date');

          if (lastScoreDate == todayStr) {
            final smartRecovery = prefs.getInt('daily_recovery_score');
            final smartRHR = prefs.getInt('daily_calculated_rhr');
            final smartHRV = prefs.getInt('daily_calculated_hrv');

            if (smartRecovery != null || smartRHR != null || smartHRV != null) {
              syncedData = syncedData.copyWith(
                recovery: smartRecovery ?? syncedData.recovery,
                rhr: smartRHR ?? syncedData.rhr,
                hrv: smartHRV ?? syncedData.hrv,
              );
              print('📦 AI Chat initial sync: Recovery=${syncedData.recovery}');
            }
          }
        } catch (e) {
          print('Error syncing AI initial data: $e');
        }

        if (mounted) {
          setState(() {
            _currentHealthData = syncedData;
          });
        }
      } else {
        print('No initial health data available');
      }
    } catch (e) {
      print('Error loading initial health data: $e');
    }

    // Get welcome message after health data is loaded
    _getWelcomeMessage();
  }

  // Enhanced metallic border method
  Widget _buildGradientBorderCard({
    required Widget child,
    double borderRadius = 20,
    EdgeInsets? padding,
    Color? backgroundColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2C2C2C),
            Color(0xFF1A1A1A),
            Color(0xFF404040),
            Color(0xFF1A1A1A),
            Color(0xFF2C2C2C),
          ],
          stops: [0.0, 0.2, 0.5, 0.8, 1.0],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius - 1.5),
            color: backgroundColor ?? const Color(0xFF0D0D0D).withOpacity(0.95),
          ),
          child: padding != null
              ? Padding(padding: padding, child: child)
              : child,
        ),
      ),
    );
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(
        ChatMessage(text: text, isUser: true, timestamp: DateTime.now()),
      );
      _controller.clear();
      _isTyping = true;
    });

    _scrollToBottom();

    // SYNC SMART METRICS FROM STORAGE (Calculated by Dashboard)
    // This ensures AI chat doesn't see old/raw defaults (like 60/45/85)
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateTime.now().toIso8601String().split('T')[0];
      final lastScoreDate = prefs.getString('last_score_date');

      if (lastScoreDate == todayStr && _currentHealthData != null) {
        final smartRecovery = prefs.getInt('daily_recovery_score');
        final smartRHR = prefs.getInt('daily_calculated_rhr');
        final smartHRV = prefs.getInt('daily_calculated_hrv');

        if (smartRecovery != null && smartRHR != null && smartHRV != null) {
          _currentHealthData = _currentHealthData!.copyWith(
            recovery: smartRecovery,
            rhr: smartRHR,
            hrv: smartHRV,
          );
          print(
            '🔮 AI context synced with smart metrics: Recovery=$smartRecovery, RHR=$smartRHR, HRV=$smartHRV',
          );
        }
      }
    } catch (e) {
      print('Error syncing AI smart metrics: $e');
    }

    try {
      final response = await _geminiService.sendMessage(
        text,
        currentHealthData: _currentHealthData,
      );

      setState(() {
        _isTyping = false;
        _messages.add(
          ChatMessage(text: response, isUser: false, timestamp: DateTime.now()),
        );
      });
    } catch (e) {
      print('Error sending message: $e');
      setState(() {
        _isTyping = false;
        _messages.add(
          ChatMessage(
            text:
                "I apologize, but I'm having trouble connecting right now. Please check your internet connection and try again. Error: $e",
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      });
    }

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearChat() {
    setState(() {
      _messages.clear();
      _geminiService.clearChatHistory();
      _getWelcomeMessage();
    });
  }

  void _getWelcomeMessage() async {
    try {
      final welcomeMessage = await _geminiService.getWelcomeMessage();
      if (mounted) {
        setState(() {
          _messages.clear();
          _messages.add(
            ChatMessage(
              text: welcomeMessage,
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );

          // Add a system message if health data is available
          if (_currentHealthData != null) {
            _messages.add(
              ChatMessage(
                text:
                    "I can see your current health data is available. Ask me anything about your metrics!",
                isUser: false,
                timestamp: DateTime.now(),
              ),
            );
          } else {
            _messages.add(
              ChatMessage(
                text:
                    "⚠️ I don't see your current health data. Please ensure your device is connected for personalized analysis.",
                isUser: false,
                timestamp: DateTime.now(),
              ),
            );
          }
        });
      }
    } catch (e) {
      print('Error getting welcome message: $e');
      setState(() {
        _messages.clear();
        _messages.add(
          ChatMessage(
            text:
                "Hello! I'm your Zyora AI assistant. I can help you with health insights, activity analysis, and wellness recommendations based on your real-time health data. How can I assist you today?",
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      });
    }
  }

  Widget _buildRecommendedQuestions() {
    if (_currentHealthData == null) return const SizedBox.shrink();

    final List<Map<String, dynamic>> questions = [];

    // Data-driven logic for "Aha" prompts
    if (_currentHealthData!.recovery < 70) {
      questions.add({
        'text': "Why is my recovery low?",
        'icon': Icons.battery_alert_rounded,
      });
    } else {
      questions.add({
        'text': "Best time to workout today?",
        'icon': Icons.fitness_center_rounded,
      });
    }

    if (_currentHealthData!.stress > 60) {
      questions.add({
        'text': "Quick stress reduction plan?",
        'icon': Icons.spa_rounded,
      });
    } else {
      questions.add({
        'text': "How to maintain focus?",
        'icon': Icons.psychology_rounded,
      });
    }

    if (_currentHealthData!.sleep < 6.5) {
      questions.add({
        'text': "Handle sleep debt effectively?",
        'icon': Icons.nightlight_round,
      });
    } else {
      questions.add({
        'text': "Analyze my sleep quality",
        'icon': Icons.auto_graph_rounded,
      });
    }

    if (_currentHealthData!.hrv < 40 && _currentHealthData!.hrv > 0) {
      questions.add({
        'text': "Specific ways to improve HRV?",
        'icon': Icons.favorite_border_rounded,
      });
    } else if (_currentHealthData!.hrv > 70) {
      questions.add({
        'text': "Am I primed for a PR today?",
        'icon': Icons.bolt_rounded,
      });
    }

    // Always add a few high-value biohacking questions
    questions.add({
      'text': "Predict tomorrow's recovery",
      'icon': Icons.query_stats_rounded,
    });
    questions.add({
      'text': "Biohacking tips for longevity",
      'icon': Icons.auto_awesome_rounded,
    });
    questions.add({
      'text': "Analyze my heart health trend",
      'icon': Icons.monitor_heart_rounded,
    });
    questions.add({
      'text': "Am I overtraining?",
      'icon': Icons.warning_amber_rounded,
    });
    questions.add({
      'text': "Daily metabolic insight",
      'icon': Icons.waves_rounded,
    });

    return Container(
      height: 45,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: questions.length,
        itemBuilder: (context, index) {
          final q = questions[index];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _buildDiscoveryChip(q['text'], q['icon']),
          );
        },
      ),
    );
  }

  Widget _buildDiscoveryChip(String text, IconData icon) {
    return GestureDetector(
      onTap: () {
        _controller.text = text;
        _sendMessage();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF3A3A3C), width: 1),
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1C1C1E).withOpacity(0.9),
              const Color(0xFF2C2C2E).withOpacity(0.6),
            ],
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF0A84FF)),
            const SizedBox(width: 8),
            Text(
              text,
              style: const TextStyle(
                color: Color(0xFFE5E5EA),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _healthDataSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            // Premium Zyora AI logo
            _buildGradientBorderCard(
              borderRadius: 25,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(23.5),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF325DAD), Color(0xFF4A7BDB)],
                  ),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFFE8E8E8),
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Zyora AI',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFE8E8E8),
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Health data status indicator
          _buildGradientBorderCard(
            borderRadius: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    _currentHealthData != null
                        ? Icons.monitor_heart
                        : Icons.device_unknown,
                    color: _currentHealthData != null
                        ? Colors.green
                        : Colors.orange,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _currentHealthData != null ? 'Live' : 'Offline',
                    style: TextStyle(
                      color: _currentHealthData != null
                          ? Colors.green
                          : Colors.orange,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Refresh button with metallic style
          _buildGradientBorderCard(
            borderRadius: 12,
            child: Material(
              color: Colors.transparent,
              child: IconButton(
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: Color(0xFFE8E8E8),
                  size: 20,
                ),
                onPressed: _clearChat,
                tooltip: 'Clear Chat',
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Messages area
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0D0D0D), Color(0xFF151515)],
                ),
              ),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(20),
                itemCount: _messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (_isTyping && index == _messages.length) {
                    return const TypingIndicator();
                  }

                  final message = _messages[index];
                  return ChatBubble(message: message, isUser: message.isUser);
                },
              ),
            ),
          ),

          // Recommended Questions (Discovery Chips)
          _buildRecommendedQuestions(),

          // Input Area with enhanced styling
          _buildGradientBorderCard(
            borderRadius: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(0),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A1A1A), Color(0xFF0D0D0D)],
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildGradientBorderCard(
                      borderRadius: 25,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(23.5),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF1A1A1A), Color(0xFF151515)],
                          ),
                        ),
                        child: TextField(
                          controller: _controller,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: const Color(0xFFE8E8E8),
                                fontSize: 16,
                              ),
                          decoration: InputDecoration(
                            hintText: _currentHealthData != null
                                ? "Ask about your health data (${_currentHealthData!.heartRate} BPM, ${_currentHealthData!.steps} steps)..."
                                : "Ask about health... (device not connected)",
                            hintStyle: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: const Color(0xFF808080)),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _sendMessage(),
                          maxLines: null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Send button
                  _buildGradientBorderCard(
                    borderRadius: 25,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(23.5),
                        onTap: _sendMessage,
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(23.5),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF325DAD), Color(0xFF4A7BDB)],
                            ),
                          ),
                          child: const Icon(
                            Icons.send_rounded,
                            color: Color(0xFFE8E8E8),
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

// Enhanced ChatBubble with professional formatting
class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isUser;

  const ChatBubble({required this.message, required this.isUser, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _buildAvatar(isUser: false),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // Name label for AI
                if (!isUser) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6, left: 8),
                    child: Text(
                      'Zyora AI',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF808080),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
                // Message bubble
                _buildMessageBubble(context),
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 12),
            _buildAvatar(isUser: true),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar({required bool isUser}) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: isUser
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF404040), Color(0xFF282828)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF325DAD), Color(0xFF4A7BDB)],
              ),
      ),
      child: Icon(
        isUser ? Icons.person_rounded : Icons.auto_awesome_rounded,
        color: const Color(0xFFE8E8E8),
        size: 16,
      ),
    );
  }

  Widget _buildMessageBubble(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: isUser
              ? const Radius.circular(20)
              : const Radius.circular(8),
          bottomRight: isUser
              ? const Radius.circular(8)
              : const Radius.circular(20),
        ),
        gradient: isUser
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2C59A8), Color(0xFF3E72D1)],
              )
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1C1C1E).withOpacity(0.8),
                  const Color(0xFF2C2C2E).withOpacity(0.4),
                ],
              ),
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Use Markdown for AI messages, plain text for user
            if (isUser)
              Text(
                message.text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFE8E8E8),
                  fontSize: 14,
                  height: 1.5,
                  fontWeight: FontWeight.w400,
                ),
              )
            else
              MarkdownBody(
                data: message.text,
                styleSheet: MarkdownStyleSheet(
                  p: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFE8E8E8),
                    fontSize: 14,
                    height: 1.6,
                    fontWeight: FontWeight.w400,
                  ),
                  h1: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFFE8E8E8),
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    height: 1.4,
                  ),
                  h2: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFFE8E8E8),
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    height: 1.4,
                  ),
                  h3: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFFE8E8E8),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    height: 1.4,
                  ),
                  listBullet: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFFE8E8E8),
                    fontSize: 16,
                    height: 1.6,
                  ),
                  blockquote: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFFB0B0B0),
                    fontStyle: FontStyle.italic,
                    fontSize: 15,
                    height: 1.6,
                  ),
                  blockquoteDecoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  code: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFE8E8E8),
                    backgroundColor: const Color(0xFF252525),
                    fontFamily: 'Monospace',
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: const Color(0xFF252525),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  strong: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFE8E8E8),
                  ),
                  em: const TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Color(0xFFE8E8E8),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              _formatTime(message.timestamp),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFFA0A0A0).withOpacity(0.7),
                fontSize: 11,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }
}

// Enhanced TypingIndicator
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation1;
  late Animation<double> _animation2;
  late Animation<double> _animation3;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _animation1 = Tween(begin: 0.0, end: -6.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.3, curve: Curves.easeInOut),
      ),
    );
    _animation2 = Tween(begin: 0.0, end: -6.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.5, curve: Curves.easeInOut),
      ),
    );
    _animation3 = Tween(begin: 0.0, end: -6.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 0.7, curve: Curves.easeInOut),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildDot(Animation<double> animation) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, animation.value),
        child: Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: const BoxDecoration(
            color: Color(0xFF4A7BDB),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF325DAD), Color(0xFF4A7BDB)],
              ),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFFE8E8E8),
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 8),
                child: Text(
                  'Zyora AI',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF808080),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(20),
                  ),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDot(_animation1),
                    _buildDot(_animation2),
                    _buildDot(_animation3),
                    const SizedBox(width: 12),
                    Text(
                      'Analyzing...',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFA0A0A0),
                        fontSize: 12,
                      ),
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
}
