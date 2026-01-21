import 'package:google_generative_ai/google_generative_ai.dart';
import 'ble_service.dart';

class GeminiService {
  static const String _apiKey = 'AIzaSyDl4UA3gVJYqFbzXEiYJOa5NIZGaSkG-iE';

  static const String _assistantIdentity = '''
You are Zyora Health Intelligence - a medical-grade AI health analyst with deep expertise in physiology, biometrics, and health optimization.

ZYORA HEALTH ALGORITHMS YOU KNOW:

RECOVERY = HRV_Impact(40%) + RHR_Impact(25%) + Sleep_Impact(15%) + Stress_Vitals(10%) + SpO2_Impact(5%) + Questions(5%)
VO2MAX = (15.3 * (HR_Max/RHR) * 0.6) + (3.5 + 0.26*(Steps/Calories) + 0.2*SpO2 - 0.1*RHR) * 0.4
STRESS_RESILIENCE = 50 + 0.4*HRV - 0.3*Stress - 0.2*(RHR-60) + 0.2*Recovery
SLEEP_QUALITY = 0.5*(SleepDuration/8)*100 + 0.3*Sleep*10 + (FeltRested?10:0) - ScreenTime*5 - (SleepAid?5:0) + (UsualEnv?5:0)
IMMUNITY = 0.4*HRV + 0.3*Recovery + 0.2*Sleep*10 - 0.3*Stress - 0.2*(RHR-60)
METABOLIC = 0.5*(Steps/10000)*100 + 0.2*((2000-Calories)/20) - 0.2*(RHR-60) + 0.1*Sleep*10
BRAIN = 0.4*SleepQuality + 0.2*SpO2 - 0.3*Stress + (FeltRested?10:0) - ScreenTime*5
BIO_AGE = ChronoAge - (VO2max-35)*0.5 + (RHR-60)*0.3 - HRV*0.2 + Stress*0.2 - Sleep*0.1
TRAINING_READINESS = 0.4*Recovery + 0.3*Sleep*10 - 0.2*Stress - 0.1*(RHR-60)
HORMONAL = 50 + 0.3*HRV - 0.4*Stress + 0.2*Sleep*10 + (Napped?5:0) - (FeltStressed?5:0)
INFLAMMATION = 100 - (50 + 0.4*(RHR-60) - 0.3*HRV + 0.2*Stress - 0.1*Sleep*10)

YOUR CAPABILITIES:
1. Analyze health data using exact Zyora algorithms
2. Explain root causes using physiological principles
3. Provide specific numerical improvement targets
4. Create personalized optimization plans
5. Connect metrics to show system-wide impact
6. Estimate realistic improvement timelines
7. Suggest evidence-based interventions

ALWAYS:
- Use the actual health data provided to give personalized recommendations
- When user asks about meals, nutrition, or next meal, analyze their current metabolic data and provide specific food suggestions
- Don't tell user about algorithms and formulas - use them internally for calculations
- Provide numerical targets and timelines based on their actual metrics
- Explain physiological mechanisms using their real data
- Connect multiple health metrics from their actual readings
- Suggest measurable actions based on their current state

NEVER:
- Ask for data that's already provided
- Give generic advice without using their metrics
- Ignore the health data when making recommendations

Now introduce yourself as Zyora Health Intelligence and explain you can provide deep algorithmic analysis of their health data.
''';

  late GenerativeModel _model;
  late ChatSession _chat;

  GeminiService() {
    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.7,
        topK: 40,
        topP: 0.95,
        maxOutputTokens: 2048,
      ),
      safetySettings: [
        SafetySetting(HarmCategory.harassment, HarmBlockThreshold.high),
        SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.high),
        SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.high),
        SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.high),
      ],
    );

    _chat = _model.startChat();
  }

  Future<String> sendMessage(
    String message, {
    HealthData? currentHealthData,
  }) async {
    try {
      String contextMessage = _buildContextMessage(message, currentHealthData);
      
      print('Sending message to Gemini: $contextMessage');

      final response = await _chat.sendMessage(Content.text(contextMessage));

      if (response.text == null || response.text!.isEmpty) {
        return "I apologize, but I didn't receive a response. Please try again.";
      }

      print('Received response from Gemini: ${response.text}');
      return response.text!;
    } catch (e) {
      print('Gemini API Error: $e');
      return _handleError(e);
    }
  }

  String _buildContextMessage(String message, HealthData? currentHealthData) {
    String context = _assistantIdentity;
    
    // Always include current health data if available
    if (currentHealthData != null) {
      context += '''
      
CURRENT USER HEALTH DATA FOR ANALYSIS:
- Heart Rate: ${currentHealthData.heartRate} BPM
- Resting HR: ${currentHealthData.rhr} BPM 
- HRV: ${currentHealthData.hrv} ms
- Steps: ${currentHealthData.steps}
- Calories: ${currentHealthData.calories} kcal
- Sleep: ${currentHealthData.sleep} hours
- SpO2: ${currentHealthData.spo2}%
- Recovery: ${currentHealthData.recovery}%
- Stress: ${currentHealthData.stress}/100
- Body Temp: ${currentHealthData.bodyTemperature}°C
- Breathing Rate: ${currentHealthData.breathingRate} BPM

USER QUESTION: $message

IMPORTANT: Use the above health data to provide personalized, specific recommendations. For meal/nutrition questions, consider their metabolic data (calories burned: ${currentHealthData.calories}, steps: ${currentHealthData.steps}, current recovery: ${currentHealthData.recovery}%) to suggest appropriate foods and timing.
''';
    } else {
      context += '''
      
USER QUESTION: $message

Note: No current health data available. Ask user to connect their device or provide health metrics for personalized analysis.
''';
    }

    return context;
  }

  String _handleError(dynamic e) {
    if (e.toString().contains('API_KEY_INVALID')) {
      return "API key error. Please check your Gemini API configuration.";
    } else if (e.toString().contains('network') ||
        e.toString().contains('SocketException')) {
      return "Network error. Please check your internet connection and try again.";
    } else if (e.toString().contains('quota') ||
        e.toString().contains('rate limit')) {
      return "Service temporarily unavailable. Please try again in a few moments.";
    } else {
      return "I'm experiencing technical difficulties. Please try again. Error: ${e.toString()}";
    }
  }

  void clearChatHistory() {
    _chat = _model.startChat();
  }

  Future<String> getWelcomeMessage() async {
    return '''
Hello! I'm Zyora Health Intelligence, your medical-grade health analyst.

I'm equipped with Zyora's complete health algorithms and can provide deep analysis of your:
- Recovery scores and optimization strategies
- Cardiovascular fitness (VO2-max)
- Stress resilience patterns  
- Sleep quality factors
- Metabolic health indicators
- Nutrition and meal planning based on your energy expenditure
- And all other health metrics

I provide specific, numerical improvement targets and personalized recommendations using your real-time health data.

What would you like me to analyze in your health data today?
''';
  }
}