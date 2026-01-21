import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:zyora_final/services/ble_service.dart';
import 'package:zyora_final/local_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AIDescriptionService {
  static const String _apiKey = 'AIzaSyCrWinSxqMFXgVzzTI9QT_hHRxsM6enxeg';
  
  late GenerativeModel _model;
  final LocalStorageService _localStorage = LocalStorageService();

  final Map<String, String> _descriptionCache = {};
  HealthData? _lastProcessedData;
  static const Duration _cacheExpiration = Duration(hours: 24);

  AIDescriptionService() {
    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.35,   // more deterministic, professional tone
        topK: 40,
        topP: 0.90,
        maxOutputTokens: 160, // shorter output (single concise paragraph)
      ),
      safetySettings: [
        SafetySetting(HarmCategory.harassment, HarmBlockThreshold.high),
        SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.high),
        SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.high),
        SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.high),
      ],
    );
    _loadCacheFromStorage();
  }

  Future<void> _loadCacheFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString('ai_description_cache');
      final lastProcessedDataJson = prefs.getString('last_processed_data');
      final cacheTimestamp = prefs.getInt('cache_timestamp') ?? 0;

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - cacheTimestamp > _cacheExpiration.inMilliseconds) {
        print('AI cache expired, clearing...');
        await clearAllCache();
        return;
      }

      if (cacheJson != null) {
        final Map<String, dynamic> cacheData = json.decode(cacheJson);
        _descriptionCache.clear();
        cacheData.forEach((key, value) {
          _descriptionCache[key] = value.toString();
        });
        print('Loaded ${_descriptionCache.length} AI descriptions from cache');
      }

      if (lastProcessedDataJson != null) {
        final Map<String, dynamic> data = json.decode(lastProcessedDataJson);
        _lastProcessedData = HealthData(
          heartRate: data['heartRate'] ?? 0,
          steps: data['steps'] ?? 0,
          spo2: data['spo2'] ?? 0,
          calories: data['calories'] ?? 0,
          sleep: data['sleep']?.toDouble() ?? 0.0,
          recovery: data['recovery'] ?? 0,
          stress: data['stress'] ?? 0,
          rhr: data['rhr'] ?? 0,
          hrv: data['hrv'] ?? 0,
          bodyTemperature: data['bodyTemperature']?.toDouble() ?? 0.0,
          breathingRate: data['breathingRate'] ?? 0,
        );
      }
    } catch (e) {
      print('Error loading AI cache: $e');
    }
  }

  Future<void> _saveCacheToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ai_description_cache', json.encode(_descriptionCache));
      
      if (_lastProcessedData != null) {
        await prefs.setString('last_processed_data', json.encode({
          'heartRate': _lastProcessedData!.heartRate,
          'steps': _lastProcessedData!.steps,
          'spo2': _lastProcessedData!.spo2,
          'calories': _lastProcessedData!.calories,
          'sleep': _lastProcessedData!.sleep,
          'recovery': _lastProcessedData!.recovery,
          'stress': _lastProcessedData!.stress,
          'rhr': _lastProcessedData!.rhr,
          'hrv': _lastProcessedData!.hrv,
          'bodyTemperature': _lastProcessedData!.bodyTemperature,
          'breathingRate': _lastProcessedData!.breathingRate,
        }));
      }
      
      await prefs.setInt('cache_timestamp', DateTime.now().millisecondsSinceEpoch);
      print('Saved ${_descriptionCache.length} AI descriptions to cache');
    } catch (e) {
      print('Error saving AI cache: $e');
    }
  }

  Future<String> getMetricDescription({
    required String metricName,
    required String currentValue,
    required String unit,
    required HealthData currentData,
    bool forceRefresh = false,
  }) async {
    try {
      final dataHash = _getDataHash(currentData);
      final cacheKey = '$metricName-$dataHash';
      
      if (!forceRefresh && _descriptionCache.containsKey(cacheKey) && _lastProcessedData == currentData) {
        print('Using cached description for $metricName');
        return _descriptionCache[cacheKey]!;
      }

      if (_lastProcessedData != null && !_hasDataChangedSignificantly(_lastProcessedData!, currentData, metricName)) {
        print('Data not changed significantly for $metricName, using cache if available');
        if (_descriptionCache.containsKey(cacheKey)) {
          return _descriptionCache[cacheKey]!;
        }
      }

      final historicalData = await _getHistoricalContext();
      final prompt = _buildMedicalPrompt(metricName, currentValue, unit, currentData, historicalData);
      final description = await _callGeminiAPI(prompt);
      
      _descriptionCache[cacheKey] = description;
      _lastProcessedData = currentData;
      await _saveCacheToStorage();
      
      print('Generated new AI description for $metricName');
      return description;
    } catch (e) {
      print('Error generating AI description: $e');
      return _getMedicalFallback(metricName, currentValue, unit, currentData);
    }
  }

  String _getDataHash(HealthData data) {
    return '${data.heartRate}-${data.steps}-${data.spo2}-${data.calories}-${data.sleep}-${data.recovery}-${data.stress}-${data.rhr}-${data.hrv}-${data.bodyTemperature}-${data.breathingRate}';
  }

  bool _hasDataChangedSignificantly(HealthData oldData, HealthData newData, String metricName) {
    final thresholds = {
      'Heart Rate': 5,
      'Steps': 100,
      'Sleep': 0.5,
      'Calories': 50,
      'SpO₂': 2,
      'Recovery': 5,
      'Stress Level': 5,
      'VO₂-max': 3,
      'Stress Resilience': 5,
      'Sleep Quality': 5,
      'Immunity Defense': 5,
      'Metabolic Health': 5,
      'Brain Performance': 5,
      'Biological Age': 5,
      'Training Readiness': 5,
      'Hormonal Balance': 5,
      'Inflammation Level': 5,
    };

    final threshold = thresholds[metricName] ?? 1;

    switch (metricName) {
      case 'Heart Rate':
        return (newData.heartRate - oldData.heartRate).abs() >= threshold;
      case 'Steps':
        return (newData.steps - oldData.steps).abs() >= threshold;
      case 'Sleep':
        return (newData.sleep - oldData.sleep).abs() >= threshold;
      case 'Calories':
        return (newData.calories - oldData.calories).abs() >= threshold;
      case 'SpO₂':
        return (newData.spo2 - oldData.spo2).abs() >= threshold;
      case 'Recovery':
        return (newData.recovery - oldData.recovery).abs() >= threshold;
      case 'Stress Level':
        return (newData.stress - oldData.stress).abs() >= threshold;
      default:
        return true;
    }
  }

  Future<List<HealthDataPoint>> _getHistoricalContext() async {
    try {
      final now = DateTime.now();
      final oneWeekAgo = now.subtract(const Duration(days: 7));
      return await _localStorage.getHourlyAverages(oneWeekAgo, now);
    } catch (e) {
      print('Error getting historical data: $e');
      return [];
    }
  }

  String _buildMedicalPrompt(
    String metricName,
    String currentValue,
    String unit,
    HealthData currentData,
    List<HealthDataPoint> historicalData,
  ) {
    return '''
You are Zyora Health Intelligence — a medical-grade health analyst. INSTRUCTIONS FOR CONTENT CREATION (do not include these instructions in the output):
- Output must be exactly one paragraph (no headings, no lists, no line breaks).
- Tone: premium, clinical-professional, succinct and compassionate (think "Whoop" UX).
- Purpose: explain **why** $metricName is $currentValue $unit given the supplied vitals, and provide 2–3 concise, actionable improvements embedded in the same paragraph.
- Do NOT display formulas, algorithm descriptions, or internal calculations; keep all algorithmic logic internal and never reveal it.
- Avoid technical jargon where possible; use clear medical phrasing suitable for informed consumers.
- Keep output length short but complete (about 1–3 sentences).
- If uncertain, say "based on available data" and avoid definitive claims beyond the data.

CURRENT DATA (use this to reason, do not show raw calculations):
- Heart Rate: ${currentData.heartRate} BPM | Resting HR: ${currentData.rhr} BPM
- HRV: ${currentData.hrv} ms | Stress: ${currentData.stress}/100
- Steps: ${currentData.steps} | Calories: ${currentData.calories} kcal
- Sleep: ${currentData.sleep} h | Recovery: ${currentData.recovery}%
- SpO2: ${currentData.spo2}% | Breathing: ${currentData.breathingRate} BPM
- Body Temp: ${currentData.bodyTemperature}°C

FOCUS: $metricName ($currentValue $unit)

Generate one concise paragraph that: (1) interprets the value medically, (2) says why it likely is at that level based on the current data, and (3) gives 2–3 clear actions to improve it (with expected short timeline). End the paragraph with a short reassurance sentence. Do not include code, formulas, or algorithmic text.
''';
  }

  Future<String> _callGeminiAPI(String prompt) async {
    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      
      String raw = response.text ?? '';
      if (raw.isEmpty) {
        throw Exception('Empty response from Gemini API');
      }

      // Post-process: collapse whitespace/newlines into a single paragraph
      String singleParagraph = raw.replaceAll(RegExp(r'\r?\n+'), ' ').trim();
      singleParagraph = singleParagraph.replaceAll(RegExp(r'\s{2,}'), ' ');

      // Remove obvious formula/algorithm fragments (simple heuristics)
      // - remove textile-like formulas or things containing '=', '->', '*', '/', '+' separated tokens
      singleParagraph = singleParagraph.replaceAll(RegExp(r'([0-9\.\-]+\s*[\+\-\*\/=]\s*[0-9\.\-]+)'), '');
      singleParagraph = singleParagraph.replaceAll(RegExp(r'\b(formula|algorithm|calculation|calculated|derived|VO2|VO₂|HRV_Impact|HR_Max|RHR_Impact)\b', caseSensitive: false), '');
      singleParagraph = singleParagraph.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

      // Trim to a safe maximum length (characters). Adjust as needed.
      final maxLen = 650;
      if (singleParagraph.length > maxLen) {
        singleParagraph = singleParagraph.substring(0, maxLen).trim();
        // ensure we don't cut mid-word
        final lastSpace = singleParagraph.lastIndexOf(' ');
        if (lastSpace > 0) singleParagraph = singleParagraph.substring(0, lastSpace) + '…';
      }

      // Final safety: if the assistant accidentally left headings, remove them
      singleParagraph = singleParagraph.replaceAll(RegExp(r'^(?:\*\*.*\*\*\s*)'), '');

      return singleParagraph;
    } catch (e) {
      print('Gemini API Error or post-processing failure: $e');
      throw Exception('Failed to generate description: ${e.toString()}');
    }
  }

  String _getMedicalFallback(String metricName, String currentValue, String unit, HealthData currentData) {
    final fallbacks = {
      'Recovery': 'Based on available data your recovery is $currentValue% — this likely reflects a combination of reduced HRV (${currentData.hrv}ms), elevated resting heart rate (${currentData.rhr} BPM) and limited sleep (${currentData.sleep}h). To improve, prioritize consistent nightly sleep (target 7–9 hours), add daily short breathing or guided HRV sessions (10 minutes), and reduce high-intensity training until recovery exceeds ~70%; with consistent changes you should see meaningful gains within 1–3 weeks. This offers a path to more stable energy and training readiness.',
      'VO₂-max': 'Your VO₂-max estimate of $currentValue suggests moderate aerobic fitness influenced by resting heart rate and recent activity; increasing structured interval training (2 sessions/week), raising daily steps toward 8–10k, and focused breathing during workouts will generally show measurable improvement in 4–8 weeks. Small, consistent changes improve endurance and metabolic efficiency.',
      'Stress Resilience': 'A stress resilience score of $currentValue points to elevated day-to-day strain possibly reflected in HRV (${currentData.hrv}ms) and subjective stress (${currentData.stress}/100); practical steps include a daily 10–20 minute mindfulness or breathing routine, predictable sleep timing, and brief technology breaks before bed — improvements are often perceptible in 1–3 weeks. Better stress resilience improves sleep, recovery, and cognitive clarity.',
      'Sleep Quality': 'Your sleep metric of $currentValue indicates suboptimal restorative sleep given ${currentData.sleep} hours and current recovery; improve by creating a consistent sleep schedule, a 60-minute wind-down without screens, and optimizing the bedroom environment (cool, dark, quiet); sleep architecture and daytime energy typically improve within days to a few weeks. Better sleep will lift recovery, mood, and daytime cognition.',
      'Heart Rate': 'At $currentValue $unit your heart rate likely reflects current activity, autonomic balance (HRV ${currentData.hrv}ms) and recovery status; focus on consistent aerobic conditioning, daily breathing practice to lower resting tone, and hydration/electrolyte balance — changes in resting patterns are often noticeable in 2–6 weeks, improving overall cardiovascular resilience.',
      'Steps': 'Your step count of $currentValue provides a foundation for daily activity; consider adding brief walking intervals and post-meal movement to naturally increase non-exercise thermogenesis while supporting metabolic health without compromising recovery. Consistent movement patterns enhance circulation and energy balance.',
      'Immunity Defense': 'Your immunity score of $currentValue reflects current resilience capacity; prioritize sleep consistency and stress management through daily relaxation to strengthen immune function, with noticeable improvements typically within 10–14 days of consistent practice. Enhanced immunity supports overall vitality and recovery.',
      'Training Readiness': 'With training readiness at $currentValue, focus on today\'s recovery priorities before intensifying workouts—adequate sleep and stress management will optimize your next performance session. Listen to these signals for sustainable progress and injury prevention.',
      'Metabolic Health': 'Your metabolic health score of $currentValue indicates current energy utilization efficiency; improve through consistent activity patterns, balanced nutrition timing, and adequate recovery sleep to enhance metabolic flexibility within 2–4 weeks. Better metabolic health supports sustained energy and body composition.',
      'Brain Performance': 'Your brain performance score of $currentValue reflects current cognitive resource availability; optimize through quality sleep, stress reduction, and brief mental breaks throughout the day to enhance focus and processing speed. Cognitive improvements often appear within days of better recovery practices.',
    };

    return fallbacks[metricName] ?? 'Your $metricName of $currentValue $unit indicates a measurable state influenced by recent activity, sleep and autonomic balance; focus on consistent monitoring, targeted lifestyle adjustments, and consult a clinician for persistent concerns. Expect improvements in 2–6 weeks with consistent practice.';
  }

  void clearMetricCache(String metricName) {
    final keysToRemove = _descriptionCache.keys.where((key) => key.startsWith(metricName)).toList();
    for (var key in keysToRemove) {
      _descriptionCache.remove(key);
    }
    _saveCacheToStorage();
    print('Cleared cache for $metricName');
  }

  Future<void> clearAllCache() async {
    _descriptionCache.clear();
    _lastProcessedData = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ai_description_cache');
    await prefs.remove('last_processed_data');
    await prefs.remove('cache_timestamp');
    print('Cleared all AI description cache');
  }

  Future<String> updateMetricDescriptionManual(
    String metricName, 
    String currentValue, 
    String unit, 
    HealthData currentData
  ) async {
    clearMetricCache(metricName);
    
    return await getMetricDescription(
      metricName: metricName,
      currentValue: currentValue,
      unit: unit,
      currentData: currentData,
      forceRefresh: true,
    );
  }

  bool hasCachedDescription(HealthData currentData, String metricName) {
    final dataHash = _getDataHash(currentData);
    final cacheKey = '$metricName-$dataHash';
    return _descriptionCache.containsKey(cacheKey);
  }

  String? getCachedDescription(HealthData currentData, String metricName) {
    final dataHash = _getDataHash(currentData);
    final cacheKey = '$metricName-$dataHash';
    return _descriptionCache[cacheKey];
  }
}