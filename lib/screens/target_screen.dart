// target_screen.dart - COMPLETE UPDATED VERSION
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:zyora_final/services/gemini_service.dart';
import 'package:zyora_final/services/ble_service.dart';
import 'package:zyora_final/local_storage_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class TargetScreen extends StatefulWidget {
  final BLEService bleService;
  const TargetScreen({super.key, required this.bleService});

  @override
  State<TargetScreen> createState() => _TargetScreenState();
}

class _TargetScreenState extends State<TargetScreen>
    with SingleTickerProviderStateMixin {
  /* ----------------------------------------------------------
                               DATA
  -----------------------------------------------------------*/
  late AnimationController _controller;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  final _curW = TextEditingController();
  final _tarW = TextEditingController();
  final _height = TextEditingController();
  final _age = TextEditingController();

  String _time = '7';
  String _goal = 'Weight Loss';
  String _activity = 'Moderate';
  String _gender = 'Male';

  final List<String> _goals = [
    'Weight Loss',
    'Muscle Gain',
    'Maintenance',
    'Endurance',
    'General Fitness',
  ];
  final List<String> _times = ['3', '7', '14', '21', '30'];
  final List<String> _acts = [
    'Sedentary',
    'Light',
    'Moderate',
    'Active',
    'Very Active',
  ];
  final List<String> _genders = ['Male', 'Female'];

  bool _isGenerating = false;
  bool _showCongrats = false;
  Map<String, dynamic>? _plan;
  int _today = 0;
  DateTime? _planStartDate;

  /* ----------------------------------------------------------
                          PLAN DATABASE
  -----------------------------------------------------------*/
  static Database? _planDatabase;

  Future<Database> get planDatabase async {
    if (_planDatabase != null) return _planDatabase!;
    _planDatabase = await _initPlanDatabase();
    return _planDatabase!;
  }

  Future<Database> _initPlanDatabase() async {
    String path = p.join(await getDatabasesPath(), 'user_plans.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE plans(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            plan_data TEXT,
            start_date TEXT,
            current_day INTEGER DEFAULT 0,
            total_days INTEGER,
            is_completed INTEGER DEFAULT 0,
            created_at TEXT
          )
        ''');
      },
    );
  }

  Future<void> _savePlanToDatabase(Map<String, dynamic> plan) async {
    final db = await planDatabase;
    final now = DateTime.now();

    // Clear any existing plans
    await db.delete('plans');

    // Insert new plan
    await db.insert('plans', {
      'plan_data': json.encode(plan),
      'start_date': now.toIso8601String(),
      'current_day': 0,
      'total_days': plan['duration'],
      'is_completed': 0,
      'created_at': now.toIso8601String(),
    });
  }

  Future<Map<String, dynamic>?> _loadPlanFromDatabase() async {
    final db = await planDatabase;
    final List<Map<String, dynamic>> maps = await db.query(
      'plans',
      where: 'is_completed = ?',
      whereArgs: [0],
      limit: 1,
    );

    if (maps.isEmpty) return null;

    final planData = maps.first;
    final plan = Map<String, dynamic>.from(json.decode(planData['plan_data']));
    final startDate = DateTime.parse(planData['start_date']);
    final currentDay = planData['current_day'] as int;

    setState(() {
      _planStartDate = startDate;
      _today = currentDay;
    });

    return plan;
  }

  Future<void> _updateCurrentDay(int day) async {
    final db = await planDatabase;
    await db.update(
      'plans',
      {'current_day': day},
      where: 'is_completed = ?',
      whereArgs: [0],
    );
  }

  Future<void> _markPlanAsCompleted() async {
    final db = await planDatabase;
    await db.update(
      'plans',
      {'is_completed': 1},
      where: 'is_completed = ?',
      whereArgs: [0],
    );
  }

  Future<void> _deleteCompletedPlans() async {
    final db = await planDatabase;
    await db.delete('plans', where: 'is_completed = ?', whereArgs: [1]);
  }

  /* ----------------------------------------------------------
                             LIFECYCLE
  -----------------------------------------------------------*/
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _slide = Tween<Offset>(
      begin: const Offset(0, .3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
    _loadPlan();

    // Check for day progression daily
    _startDailyChecker();
  }

  void _startDailyChecker() {
    // Check every hour if day has changed
    Future.delayed(const Duration(hours: 1), () {
      _checkDayProgression();
      _startDailyChecker();
    });
  }

  Future<void> _checkDayProgression() async {
    if (_plan == null || _planStartDate == null) return;

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfPlanDay = DateTime(
      _planStartDate!.year,
      _planStartDate!.month,
      _planStartDate!.day,
    );
    final daysPassed = startOfToday.difference(startOfPlanDay).inDays;
    final totalDays = _plan!['duration'] as int;

    if (daysPassed != _today && daysPassed < totalDays) {
      // Day has changed, update to new day
      setState(() {
        _today = daysPassed;
      });
      await _updateCurrentDay(daysPassed);
    } else if (daysPassed >= totalDays && !_showCongrats) {
      // Plan completed
      setState(() {
        _showCongrats = true;
      });
      await _markPlanAsCompleted();
      await _deleteCompletedPlans();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _curW.dispose();
    _tarW.dispose();
    _height.dispose();
    _age.dispose();
    super.dispose();
  }

  /* ----------------------------------------------------------
                          STORAGE / BLE
  -----------------------------------------------------------*/
  Future<void> _loadPlan() async {
    final plan = await _loadPlanFromDatabase();
    if (plan != null) {
      setState(() {
        _plan = plan;
      });
      // Check current day immediately
      await _checkDayProgression();
    }
  }

  Future<List<HealthDataPoint>> _history() async {
    try {
      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7));
      return await widget.bleService.getHourlyAverages(weekAgo, now);
    } catch (_) {
      return [];
    }
  }

  /* ----------------------------------------------------------
                            AI PLAN
  -----------------------------------------------------------*/
  Future<void> _generate() async {
    if (_curW.text.isEmpty ||
        _tarW.text.isEmpty ||
        _height.text.isEmpty ||
        _age.text.isEmpty) {
      _error('Please fill every field');
      return;
    }
    setState(() => _isGenerating = true);

    try {
      final hist = await _history();
      final prompt = _buildPrompt(hist);
      final gemini = GeminiService();
      final resp = await gemini.sendMessage(prompt);
      final plan = _parse(resp);
      await _savePlanToDatabase(plan);
      if (mounted) {
        setState(() {
          _plan = plan;
          _today = 0;
          _planStartDate = DateTime.now();
          _isGenerating = false;
          _showCongrats = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isGenerating = false);
      _error('Failed to generate plan: $e');
    }
  }

  String _buildPrompt(List<HealthDataPoint> h) {
    final steps = h.isEmpty
        ? 0
        : h.map((e) => e.steps).reduce((a, b) => a + b) / h.length;
    final cals = h.isEmpty
        ? 0
        : h.map((e) => e.calories).reduce((a, b) => a + b) / h.length;
    final hr = h.isEmpty
        ? 0
        : h.map((e) => e.heartRate).reduce((a, b) => a + b) / h.length;

    return '''
  You are a professional fitness & nutrition AI.

  User:
  Gender: $_gender  
  Age: ${_age.text}  
  Height: ${_height.text} cm  
  Current weight: ${_curW.text} kg  
  Target weight: ${_tarW.text} kg  
  Activity level: $_activity  
  Goal: $_goal  
  Duration: $_time days  

  Recent 7-day wearable data:
  • Avg steps: ${steps.round()}
  • Avg calories burned: ${cals.round()}
  • Avg heart rate: ${hr.round()} bpm

  GOAL RULES:

  If goal = Weight Loss:
  • Create calorie deficit  
  • High protein  
  • Higher cardio & steps  
  • Fat-loss focused workouts  

  If goal = Muscle Gain:
  • Create calorie surplus  
  • Very high protein  
  • Heavy strength training  
  • Low cardio  

  If goal = Maintenance:
  • Balanced calories  
  • Mixed training  

  If goal = Endurance:
  • High carbs  
  • Cardio-focused workouts  

  If goal = General Fitness:
  • Balanced mix  

  IMPORTANT:
  You must calculate all calories, macros, steps, and workouts based on the user's data.
  Do NOT use fixed numbers. and use the user's data to calculate the values. and the goal you provided make sure it should be accurate like if user follow it should be able to achieve the goal. 

  Return ONLY valid JSON in this exact format no extra text or description:

  {
    "name":"Premium $_goal Plan",
    "duration":${int.parse(_time)},
    "goal":"$_goal",
    "days":[
      {
        "day":1,
        "focus":"AI generated",
        "morning":[ "..." ],
        "workout":{
          "type":"...",
          "warm":[ "..." ],
          "main":[
            {"name":"...","sets":0,"reps":"...","rest":"...","tip":"..."}
          ],
          "cool":[ "..." ]
        },
        "nutrition":{
          "cal": AI_CALCULATED,
          "pro": AI_CALCULATED,
          "carb": AI_CALCULATED,
          "fat": AI_CALCULATED,
          "water":"AI_CALCULATED",
          "meals":[ "..." ],
          "supps":[ "..." ]
        },
        "targets":{
          "steps": AI_CALCULATED,
          "cal": AI_CALCULATED,
          "active": AI_CALCULATED
        },
        "recovery":[ "..." ],
        "challenges":[ "..." ],
        "motivation":"..."
      }
    ]
  }
  ''';
  }

  Map<String, dynamic> _parse(String resp) {
    try {
      final jsonStart = resp.indexOf('{');
      final jsonEnd = resp.lastIndexOf('}') + 1;
      if (jsonStart != -1 && jsonEnd != -1) {
        return json.decode(resp.substring(jsonStart, jsonEnd));
      }
    } catch (_) {}
    return _fallback();
  }

  Map<String, dynamic> _fallback() {
    final days = int.parse(_time);
    final list = List.generate(days, (i) {
      final d = i + 1;
      final dayOffset = d - 1;
      return {
        "day": d,
        "focus": "Day $d Focus",
        "morning": ["Drink water", "Mobility 10min"],
        "workout": {
          "type": "Full-Body",
          "warm": ["5min jog", "5min stretch"],
          "main": [
            {"name": "Squats", "sets": 3, "reps": "15", "rest": "45s"},
          ],
          "cool": ["5min walk"],
        },
        "nutrition": {
          "cal": 2000 + dayOffset * 50,
          "pro": 80 + dayOffset * 2,
          "carb": 220 + dayOffset * 5,
          "fat": 55,
          "water": "3L",
          "meals": ["Oats + protein", "Chicken salad", "Salmon dinner"],
          "supps": ["Multivitamin"],
        },
        "targets": {
          "steps": 7000 + dayOffset * 300,
          "cal": 400 + dayOffset * 20,
          "active": 45 + dayOffset * 5,
        },
        "recovery": ["Stretch", "Sleep 8h"],
        "challenges": ["Extra 10min walk"],
        "motivation": "Keep pushing – you got this!",
      };
    });
    return {
      "name": "Quick $_goal Plan",
      "duration": days,
      "goal": _goal,
      "days": list,
    };
  }

  /* ----------------------------------------------------------
                               UI
  -----------------------------------------------------------*/
  /// Glass-card wrapper
  Widget _card({
    required Widget child,
    double radius = 20,
    EdgeInsets? pad,
    Color? tint,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: tint != null
              ? [tint.withOpacity(.35), tint.withOpacity(.15)]
              : [
                  Colors.black,
                  const Color(0xff111111),
                  const Color(0xff888888).withOpacity(.25),
                  const Color(0xff111111),
                  Colors.black,
                ],
          stops: tint != null ? null : const [0, .2, .5, .8, 1],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: Container(
          padding: pad ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xff0d0d0d).withOpacity(.93),
            borderRadius: BorderRadius.circular(radius - 1.5),
          ),
          child: child,
        ),
      ),
    );
  }

  /// Animated entrance wrapper
  Widget _in(Widget child) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: child),
    );
  }

  /// Text-field with glass style
  Widget _field({
    required String label,
    required String hint,
    required String unit,
    required IconData icon,
    required TextEditingController ctrl,
  }) {
    return _in(
      _card(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.grey.withOpacity(.4),
                    Colors.grey.withOpacity(.2),
                  ],
                ),
                border: Border.all(color: Colors.grey.withOpacity(.3)),
              ),
              child: Icon(icon, color: Colors.white70, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: hint,
                      border: InputBorder.none,
                      hintStyle: TextStyle(color: Colors.white38),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              unit,
              style: const TextStyle(
                color: Colors.white38,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Dropdown with glass style
  Widget _drop({
    required String label,
    required String value,
    required List<String> items,
    required IconData icon,
    required Function(String?) onChange,
  }) {
    return _in(
      _card(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.grey.withOpacity(.4),
                    Colors.grey.withOpacity(.2),
                  ],
                ),
                border: Border.all(color: Colors.grey.withOpacity(.3)),
              ),
              child: Icon(icon, color: Colors.white70, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  DropdownButton<String>(
                    value: value,
                    isExpanded: true,
                    dropdownColor: const Color(0xff1a1a1a),
                    underline: const SizedBox(),
                    style: const TextStyle(color: Colors.white),
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.white54,
                    ),
                    items: items
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: onChange,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Big CTA button
  Widget _btn() {
    return _in(
      _card(
        tint: const Color.fromARGB(255, 50, 93, 173),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _isGenerating ? null : _generate,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isGenerating)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else ...[
                    const Icon(Icons.auto_awesome, color: Colors.white),
                    const SizedBox(width: 12),
                    const Text(
                      'Generate AI Plan',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /* ----------------------------------------------------------
                         CREATION FORM PAGE
  -----------------------------------------------------------*/
  Widget _createPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create Your Fitness Plan',
            style: TextStyle(
              color: Colors.white,
              fontSize: (MediaQuery.of(context).size.width * 0.07).clamp(
                24.0,
                28.0,
              ),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Get a personalised AI-generated fitness plan',
            style: TextStyle(color: Colors.white.withOpacity(.6)),
          ),
          const SizedBox(height: 32),
          _field(
            label: 'Current Weight',
            hint: 'Enter weight',
            unit: 'kg',
            icon: Icons.monitor_weight,
            ctrl: _curW,
          ),
          const SizedBox(height: 12),
          _field(
            label: 'Target Weight',
            hint: 'Enter target',
            unit: 'kg',
            icon: Icons.flag,
            ctrl: _tarW,
          ),
          const SizedBox(height: 12),
          _field(
            label: 'Height',
            hint: 'Enter height',
            unit: 'cm',
            icon: Icons.height,
            ctrl: _height,
          ),
          const SizedBox(height: 12),
          _field(
            label: 'Age',
            hint: 'Enter age',
            unit: 'yrs',
            icon: Icons.person,
            ctrl: _age,
          ),
          const SizedBox(height: 16),
          _drop(
            label: 'Gender',
            value: _gender,
            items: _genders,
            icon: Icons.person_outline,
            onChange: (v) => setState(() => _gender = v!),
          ),
          const SizedBox(height: 12),
          _drop(
            label: 'Primary Goal',
            value: _goal,
            items: _goals,
            icon: Icons.track_changes,
            onChange: (v) => setState(() => _goal = v!),
          ),
          const SizedBox(height: 12),
          _drop(
            label: 'Activity Level',
            value: _activity,
            items: _acts,
            icon: Icons.directions_run,
            onChange: (v) => setState(() => _activity = v!),
          ),
          const SizedBox(height: 12),
          _drop(
            label: 'Plan Duration',
            value: _time,
            items: _times,
            icon: Icons.calendar_today,
            onChange: (v) => setState(() => _time = v!),
          ),
          const SizedBox(height: 32),
          _btn(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  /* ----------------------------------------------------------
                           TODAY PAGE
  -----------------------------------------------------------*/
  Widget _todayPage() {
    final days = _plan?['days'] as List? ?? [];
    if (days.isEmpty || _today >= days.length) return const SizedBox();

    final day = days[_today] ?? {};
    if (day.isEmpty) return const SizedBox();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _plan?['name'] ?? 'Plan',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: (MediaQuery.of(context).size.width * 0.06)
                            .clamp(20.0, 24.0),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Day ${_today + 1} of ${_plan?['duration']} • $_goal',
                      style: TextStyle(color: Colors.white.withOpacity(.6)),
                    ),
                  ],
                ),
              ),
              _card(
                radius: 12,
                child: IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: () async {
                    await _checkDayProgression(); // refresh day counter
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // progress
          _card(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Plan Progress',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${(((_today + 1) / (_plan?['duration'] ?? 1)) * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Color.fromARGB(255, 50, 93, 173),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: (_today + 1) / (_plan?['duration'] ?? 1),
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(
                    Color.fromARGB(255, 50, 93, 173),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // big tinted header for today
          _card(
            tint: const Color.fromARGB(255, 50, 93, 173),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color.fromARGB(255, 50, 93, 173).withOpacity(.25),
                    const Color.fromARGB(255, 50, 93, 173).withOpacity(.1),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Day ${_today + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            day['focus'] ?? 'Focus',
                            style: const TextStyle(
                              color: Color.fromARGB(255, 50, 93, 173),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(
                            255,
                            50,
                            93,
                            173,
                          ).withOpacity(.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color.fromARGB(
                              255,
                              50,
                              93,
                              173,
                            ).withOpacity(.4),
                          ),
                        ),
                        child: const Text(
                          'TODAY',
                          style: TextStyle(
                            color: Color.fromARGB(255, 50, 93, 173),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: (_today + 1) / (_plan?['duration'] ?? 1),
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // LONG CONTENT STARTS HERE
          ..._buildLongSections(day),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  List<Widget> _buildLongSections(Map<String, dynamic> day) {
    final morning = (day['morning'] as List?)?.cast<String>() ?? [];
    final workout = day['workout'] ?? {};
    final nutrition = day['nutrition'] ?? {};
    final targets = day['targets'] ?? {};
    final recovery = (day['recovery'] as List?)?.cast<String>() ?? [];
    final challenges = (day['challenges'] as List?)?.cast<String>() ?? [];
    final motivation = day['motivation'] ?? '';

    return [
      _section('🌅 Morning Routine', morning, Colors.orange),
      _workoutSection(workout),
      _nutritionSection(nutrition),
      _targetsSection(targets),
      _section('💤 Recovery & Wellness', recovery, Colors.purple),
      _section('🏆 Daily Challenges', challenges, Colors.amber),
      if (motivation.isNotEmpty) ...[
        const SizedBox(height: 20),
        _card(
          tint: Colors.green,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                colors: [
                  Colors.green.withOpacity(.15),
                  Colors.green.withOpacity(.05),
                ],
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.psychology_rounded,
                  color: Colors.green,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    motivation,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontStyle: FontStyle.italic,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ];
  }

  Widget _section(String title, List<String> items, Color color) {
    if (items.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle, color: color, size: 10),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map(
            (i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _card(
                radius: 12,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      colors: [color.withOpacity(.1), color.withOpacity(.05)],
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          i,
                          style: const TextStyle(
                            color: Colors.white70,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _workoutSection(Map<String, dynamic> w) {
    final warm = (w['warm'] as List?)?.cast<String>() ?? [];
    final main = (w['main'] as List?) ?? [];
    final cool = (w['cool'] as List?)?.cast<String>() ?? [];
    final ins = (w['instructions'] as List?)?.cast<String>() ?? [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.fitness_center_rounded,
                color: Colors.red,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '💪 ${w['type'] ?? 'Workout'}  (${w['duration'] ?? '60-75min'})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (warm.isNotEmpty) ...[
            const Text(
              '🔥 Warm-up',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            ...warm.map((i) => _workoutItem(i, Colors.red)),
            const SizedBox(height: 12),
          ],
          if (main.isNotEmpty) ...[
            const Text(
              '🎯 Main Set',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            ...main.map((ex) => _exerciseCard(ex)),
            const SizedBox(height: 12),
          ],
          if (cool.isNotEmpty) ...[
            const Text(
              '🧊 Cool-down',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            ...cool.map((i) => _workoutItem(i, Colors.red)),
            const SizedBox(height: 12),
          ],
          if (ins.isNotEmpty) ...[
            const Text(
              '📝 Instructions',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            ...ins.map((i) => _workoutItem(i, Colors.red)),
          ],
        ],
      ),
    );
  }

  Widget _workoutItem(String txt, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              txt,
              style: TextStyle(color: Colors.white.withOpacity(.8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _exerciseCard(Map<String, dynamic> ex) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: _card(
        radius: 12,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              colors: [
                const Color(0xff1a1a1a).withOpacity(.8),
                const Color(0xff0d0d0d).withOpacity(.9),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      ex['name'] ?? 'Exercise',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(.3)),
                    ),
                    child: Text(
                      '${ex['sets']} sets',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _detailChip('Reps', ex['reps'] ?? 'N/A', Colors.green),
                  const SizedBox(width: 8),
                  _detailChip('Rest', ex['rest'] ?? 'N/A', Colors.orange),
                ],
              ),
              if (ex['tip'] != null) ...[
                const SizedBox(height: 8),
                Text(
                  '💡 ${ex['tip']}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.6),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailChip(String label, String val, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(.6),
                fontSize: 11,
              ),
            ),
            Text(
              val,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nutritionSection(Map<String, dynamic> n) {
    final meals = (n['meals'] as List?)?.cast<String>() ?? [];
    final supps = (n['supps'] as List?)?.cast<String>() ?? [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.restaurant_rounded,
                color: Colors.blue,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                '🍽️ Nutrition Plan',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // macro circles
          _card(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: [
                    Colors.blue.withOpacity(.1),
                    Colors.blue.withOpacity(.05),
                  ],
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _macroCircle(
                        'Calories',
                        '${n['cal'] ?? 0}',
                        'kcal',
                        Colors.orange,
                      ),
                      _macroCircle(
                        'Protein',
                        '${n['pro'] ?? 0}',
                        'g',
                        Colors.blue,
                      ),
                      _macroCircle(
                        'Carbs',
                        '${n['carb'] ?? 0}',
                        'g',
                        Colors.green,
                      ),
                      _macroCircle(
                        'Fats',
                        '${n['fat'] ?? 0}',
                        'g',
                        Colors.purple,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.local_drink_rounded,
                        color: Colors.blue,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Water: ${n['water'] ?? '3L'}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // meals
          const Text(
            '🍴 Meals',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ...meals.map(
            (m) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _card(
                radius: 8,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xff1a1a1a).withOpacity(.8),
                        const Color(0xff0d0d0d).withOpacity(.9),
                      ],
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          m,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (supps.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              '💊 Supplements',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: supps
                  .map(
                    (s) => _card(
                      radius: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: LinearGradient(
                            colors: [
                              Colors.blue.withOpacity(.1),
                              Colors.blue.withOpacity(.05),
                            ],
                          ),
                        ),
                        child: Text(
                          s,
                          style: TextStyle(
                            color: Colors.blue.shade200,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _macroCircle(String label, String val, String unit, Color color) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [color.withOpacity(.3), color.withOpacity(.1)],
            ),
            border: Border.all(color: color.withOpacity(.5)),
          ),
          child: Center(
            child: Text(
              val,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(.6), fontSize: 11),
        ),
        Text(
          unit,
          style: TextStyle(color: Colors.white.withOpacity(.4), fontSize: 10),
        ),
      ],
    );
  }

  Widget _targetsSection(Map<String, dynamic> t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_rounded, color: Colors.teal, size: 20),
              const SizedBox(width: 8),
              const Text(
                '🎯 Daily Targets',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.1,
            children: [
              _targetCard(
                'Steps',
                '${t['steps'] ?? 0}',
                Icons.directions_walk,
                Colors.green,
              ),
              _targetCard(
                'Calories Burned',
                '${t['cal'] ?? 0}',
                Icons.local_fire_department,
                Colors.orange,
              ),
              _targetCard(
                'Active Time',
                '${t['active'] ?? 0} min',
                Icons.timer,
                Colors.blue,
              ),
              _targetCard(
                'Water',
                t['water'] ?? '3L',
                Icons.local_drink,
                Colors.lightBlue,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _targetCard(String title, String val, IconData ic, Color color) {
    return _card(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [color.withOpacity(.1), color.withOpacity(.05)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(ic, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              val,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(title, style: TextStyle(color: Colors.white.withOpacity(.6))),
          ],
        ),
      ),
    );
  }

  /* ----------------------------------------------------------
                         CONGRATS / RESET
  -----------------------------------------------------------*/
  Widget _congrats() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _card(
              radius: 60,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(58.5),
                  gradient: const LinearGradient(
                    colors: [
                      Color.fromARGB(255, 50, 93, 173),
                      Color.fromARGB(255, 50, 93, 173),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.celebration_rounded,
                  color: Colors.white,
                  size: 60,
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Plan Completed! 🎉',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'You finished your ${_plan?['duration']}-day $_goal journey. Amazing dedication!',
              style: TextStyle(color: Colors.white.withOpacity(.7)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _card(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: _reset,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_rounded, color: Colors.white),
                        SizedBox(width: 12),
                        Text(
                          'Start New Plan',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reset() async {
    await _deleteCompletedPlans();
    final db = await planDatabase;
    await db.delete('plans'); // Clear any active plans

    setState(() {
      _showCongrats = false;
      _plan = null;
      _today = 0;
      _planStartDate = null;
      _curW.clear();
      _tarW.clear();
      _height.clear();
      _age.clear();
    });
  }

  void _error(String msg) =>
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );

  /* ----------------------------------------------------------
                           BUILD
  -----------------------------------------------------------*/
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff0d0d0d),
      body: SafeArea(
        child: _showCongrats
            ? _congrats()
            : _plan == null
            ? _createPage()
            : _todayPage(),
      ),
    );
  }
}
